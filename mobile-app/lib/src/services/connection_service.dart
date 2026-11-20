import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../core/device_identity.dart';
import '../core/models.dart';
import '../core/protocol.dart';
import '../core/storage.dart';
import 'discovery_service.dart';

enum ConnectionPhase { idle, connecting, awaitingApproval, connected, reconnecting, rejected }

/// Emitted when the desktop acknowledges (or refuses) a scan.
class ScanEvent {
  const ScanEvent(this.record, this.status);
  final ScanRecord record;
  final AckStatus status;
}

/// Persistent, self-healing WebSocket session with the desktop.
///
/// * 5 s application-level ping/pong heartbeat in both directions.
/// * Exponential back-off reconnection (0.5 s → 15 s, with jitter).
/// * Reconnects immediately when the app returns to the foreground.
/// * Unacknowledged scans are kept in an outbox and replayed after
///   reconnecting; the desktop de-duplicates by `messageId`.
class ConnectionService extends ChangeNotifier with WidgetsBindingObserver {
  ConnectionService({required this.identity, required this.storage, required this.discovery}) {
    WidgetsBinding.instance.addObserver(this);
  }

  final DeviceIdentity identity;
  final AppStorage storage;
  final DiscoveryService discovery;

  static const _heartbeatEvery = Duration(seconds: 5);
  static const _deadAfterMs = 12000;
  static const _connectTimeout = Duration(seconds: 4);
  static const _handshakeTimeout = Duration(seconds: 8);
  static const _ackTimeout = Duration(seconds: 6);
  static const _maxBackoffMs = 15000;
  static const _maxOutbox = 200;
  static const _maxRecent = 60;

  ConnectionPhase _phase = ConnectionPhase.idle;
  DesktopTarget? _target;
  String? _desktopId;
  String? _desktopName;
  String _desktopPlatform = '';
  String? _connectedHost;
  int? _latencyMs;
  bool _desktopPaused = false;
  String? _message;
  int _attempt = 0;
  DateTime? _nextRetryAt;
  bool _wanted = false;
  bool _userDisconnected = false;
  bool _disposed = false;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeat;
  Timer? _retryTimer;
  Timer? _handshakeTimer;
  Timer? _resumeCheck;
  int _session = 0;
  int _lastInboundMs = 0;

  final LinkedHashMap<String, ScanRecord> _outbox = LinkedHashMap();
  final Map<String, Timer> _ackTimers = {};
  final List<ScanRecord> _recent = [];
  int _sessionScans = 0;
  final StreamController<ScanEvent> _events = StreamController.broadcast();

  ConnectionPhase get phase => _phase;
  DesktopTarget? get target => _target;
  String get desktopName => _desktopName ?? _target?.name ?? 'Desktop';
  String get desktopPlatform => _desktopPlatform.isNotEmpty ? _desktopPlatform : (_target?.platform ?? '');
  String? get desktopId => _desktopId ?? _target?.deviceId;
  String? get connectedHost => _connectedHost;
  int? get latencyMs => _latencyMs;
  bool get desktopPaused => _desktopPaused;
  String? get message => _message;
  int get attempt => _attempt;
  DateTime? get nextRetryAt => _nextRetryAt;
  bool get isConnected => _phase == ConnectionPhase.connected;
  bool get userDisconnected => _userDisconnected;
  bool get isActive => switch (_phase) {
    ConnectionPhase.connecting || ConnectionPhase.awaitingApproval || ConnectionPhase.connected || ConnectionPhase.reconnecting => true,
    _ => false,
  };
  int get queuedCount => _outbox.length;
  int get sessionScans => _sessionScans;
  List<ScanRecord> get recent => List.unmodifiable(_recent);
  Stream<ScanEvent> get events => _events.stream;

  /// Connects to [target], replacing any existing session.
  Future<void> connect(DesktopTarget target) async {
    _wanted = true;
    _userDisconnected = false;
    _target = target;
    _desktopName = target.name;
    _desktopPlatform = target.platform;
    _desktopId = target.deviceId;
    _attempt = 0;
    _message = null;
    _cancelRetry();
    await _open();
  }

  /// Retries right away (e.g. after discovery sees the desktop again).
  void retryNow() {
    if (!_wanted || _target == null) return;
    if (_phase == ConnectionPhase.connected || _phase == ConnectionPhase.connecting || _phase == ConnectionPhase.awaitingApproval) {
      return;
    }
    _cancelRetry();
    unawaited(_open());
  }

  Future<void> disconnect({bool forget = false}) async {
    _wanted = false;
    _userDisconnected = true;
    _cancelRetry();
    final socket = _socket;
    if (socket != null && _phase == ConnectionPhase.connected) {
      try {
        socket.add(Frames.bye());
      } on Object {
        // Socket already closing.
      }
    }
    _session++;
    _teardownSocket();
    if (forget && desktopId != null) {
      await storage.forgetPaired(desktopId!);
    }
    _phase = ConnectionPhase.idle;
    _latencyMs = null;
    _message = null;
    for (final r in _outbox.values) {
      r.delivery = ScanDelivery.queued;
    }
    _notify();
  }

  /// Queues [code] for delivery and sends it immediately when connected.
  ScanRecord sendScan(String code, String format) {
    final record = ScanRecord(messageId: randomId(), code: code, format: format, timestamp: nowMs());
    _sessionScans++;
    _recent.insert(0, record);
    if (_recent.length > _maxRecent) _recent.removeLast();
    _outbox[record.messageId] = record;
    while (_outbox.length > _maxOutbox) {
      final oldest = _outbox.keys.first;
      final dropped = _outbox.remove(oldest);
      _ackTimers.remove(oldest)?.cancel();
      if (dropped != null) {
        dropped.delivery = ScanDelivery.failed;
        dropped.detail = 'Dropped: offline queue full';
      }
    }
    if (isConnected) {
      _transmit(record);
    } else {
      record.delivery = ScanDelivery.queued;
    }
    _notify();
    return record;
  }

  void _transmit(ScanRecord record) {
    record.delivery = ScanDelivery.sending;
    _send(Frames.scan(messageId: record.messageId, code: record.code, format: record.format, timestamp: record.timestamp));
    _ackTimers.remove(record.messageId)?.cancel();
    _ackTimers[record.messageId] = Timer(_ackTimeout, () {
      _ackTimers.remove(record.messageId);
      if (_outbox.containsKey(record.messageId) && record.delivery == ScanDelivery.sending) {
        record.delivery = ScanDelivery.queued;
        _notify();
      }
    });
  }

  void _send(String frame) {
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.add(frame);
    } on Object catch (e) {
      debugPrint('[ws] send failed: $e');
    }
  }

  /// Prefers fresh addresses from discovery and the stored pairing token.
  DesktopTarget _resolve(DesktopTarget t) {
    var hosts = t.hosts;
    var port = t.port;
    var token = t.pairingToken;
    final id = t.deviceId;
    if (id != null) {
      final seen = discovery.find(id);
      if (seen != null) {
        hosts = {...seen.hosts, ...hosts}.toList();
        port = seen.port;
      }
      if (token == null || token.isEmpty) {
        for (final p in storage.pairedDesktops) {
          if (p.deviceId == id && p.pairingToken.isNotEmpty) token = p.pairingToken;
        }
      }
    }
    if (_connectedHost != null && hosts.contains(_connectedHost)) {
      hosts = [_connectedHost!, ...hosts.where((h) => h != _connectedHost)];
    }
    return t.copyWith(hosts: hosts, port: port, pairingToken: token);
  }

  Future<WebSocket> _connectOne(String host, int port) {
    final future = WebSocket.connect('ws://$host:$port');
    return future.timeout(
      _connectTimeout,
      onTimeout: () {
        unawaited(future.then<void>((s) => s.close(), onError: (Object _) {}));
        throw TimeoutException('Timed out connecting to $host:$port');
      },
    );
  }

  Future<void> _open() async {
    final base = _target;
    if (base == null) return;
    final session = ++_session;
    _teardownSocket();
    _phase = _attempt == 0 ? ConnectionPhase.connecting : ConnectionPhase.reconnecting;
    _nextRetryAt = null;
    _notify();

    final target = _resolve(base);
    _target = target;
    WebSocket? socket;
    String? host;
    for (final h in target.hosts) {
      try {
        socket = await _connectOne(h, target.port);
        host = h;
        break;
      } on Object catch (e) {
        debugPrint('[ws] $h:${target.port} unreachable: $e');
      }
      if (session != _session) return;
    }
    if (session != _session || _disposed) {
      await socket?.close();
      return;
    }
    if (socket == null) {
      _scheduleRetry('Can\'t reach ${target.name}. Make sure both devices are on the same Wi-Fi.');
      return;
    }

    _socket = socket;
    _connectedHost = host;
    _lastInboundMs = nowMs();
    _subscription = socket.listen(
      (data) => _onData(session, data),
      onDone: () => _onClosed(session),
      onError: (Object _) => _onClosed(session),
      cancelOnError: true,
    );
    _send(
      Frames.handshake(
        deviceId: identity.deviceId,
        deviceName: identity.deviceName,
        platform: identity.platform,
        appVersion: identity.appVersion,
        pairingToken: target.pairingToken,
      ),
    );
    _handshakeTimer = Timer(_handshakeTimeout, () {
      if (session == _session && _phase != ConnectionPhase.connected && _phase != ConnectionPhase.awaitingApproval) {
        _onClosed(session);
      }
    });
    _heartbeat = Timer.periodic(_heartbeatEvery, (_) => _beat(session));
  }

  void _beat(int session) {
    if (session != _session) return;
    if (nowMs() - _lastInboundMs > _deadAfterMs) {
      debugPrint('[ws] heartbeat lost');
      _onClosed(session);
      return;
    }
    _send(Frames.ping(nowMs()));
  }

  void _onData(int session, dynamic data) {
    if (session != _session) return;
    _lastInboundMs = nowMs();
    final text = data is String ? data : (data is List<int> ? utf8.decode(data, allowMalformed: true) : null);
    if (text == null) return;
    final frame = DesktopFrame.parse(text);
    switch (frame) {
      case final HandshakeAck ack:
        unawaited(_onHandshake(ack));
      case final AckFrame ack:
        _onAck(ack);
      case PingFrame(:final timestamp):
        _send(Frames.pong(timestamp));
      case PongFrame(:final timestamp):
        if (timestamp > 0) {
          _latencyMs = max(0, nowMs() - timestamp);
          _notify();
        }
      case StatusFrame(:final paused):
        _desktopPaused = paused;
        _notify();
      case null:
        break;
    }
  }

  Future<void> _onHandshake(HandshakeAck ack) async {
    _desktopId = ack.deviceId.isEmpty ? _desktopId : ack.deviceId;
    _desktopName = ack.deviceName;
    _desktopPlatform = ack.platform;
    _desktopPaused = ack.paused;
    switch (ack.status) {
      case HandshakeStatus.accepted:
        _handshakeTimer?.cancel();
        _phase = ConnectionPhase.connected;
        _attempt = 0;
        _message = null;
        final token = ack.pairingToken ?? _target?.pairingToken ?? '';
        final hosts = {?_connectedHost, ...?_target?.hosts}.toList();
        _target = _target?.copyWith(pairingToken: token, hosts: hosts, name: ack.deviceName);
        if (ack.deviceId.isNotEmpty && token.isNotEmpty) {
          await storage.upsertPaired(
            PairedDesktop(
              deviceId: ack.deviceId,
              name: ack.deviceName,
              platform: ack.platform,
              hosts: hosts,
              port: _target?.port ?? kDefaultWsPort,
              pairingToken: token,
              lastConnected: DateTime.now(),
            ),
          );
        }
        _send(Frames.ping(nowMs()));
        for (final record in _outbox.values.toList()) {
          _transmit(record);
        }
      case HandshakeStatus.pending:
        _handshakeTimer?.cancel();
        _phase = ConnectionPhase.awaitingApproval;
        _message = ack.reason ?? 'Approve this phone on your computer';
      case HandshakeStatus.rejected:
        _wanted = false;
        _phase = ConnectionPhase.rejected;
        _message = ack.reason ?? 'The desktop declined this phone';
        _session++;
        _teardownSocket();
        if (ack.deviceId.isNotEmpty) await storage.forgetPaired(ack.deviceId);
    }
    _notify();
  }

  void _onAck(AckFrame ack) {
    final record = _outbox[ack.messageId];
    if (record == null) return;
    _ackTimers.remove(ack.messageId)?.cancel();
    switch (ack.status) {
      case AckStatus.ok:
      case AckStatus.duplicate:
        record.delivery = ScanDelivery.delivered;
        _outbox.remove(ack.messageId);
      case AckStatus.paused:
        record.delivery = ScanDelivery.paused;
        _outbox.remove(ack.messageId);
      case AckStatus.error:
        record.delivery = ScanDelivery.failed;
        record.detail = ack.detail;
        _outbox.remove(ack.messageId);
      case AckStatus.unauthorized:
        record.delivery = ScanDelivery.queued;
    }
    _events.add(ScanEvent(record, ack.status));
    _notify();
  }

  void _onClosed(int session) {
    if (session != _session) return;
    _session++;
    _teardownSocket();
    for (final r in _outbox.values) {
      if (r.delivery == ScanDelivery.sending) r.delivery = ScanDelivery.queued;
    }
    if (!_wanted || _phase == ConnectionPhase.rejected) {
      if (_phase != ConnectionPhase.rejected) _phase = ConnectionPhase.idle;
      _notify();
      return;
    }
    _scheduleRetry(_phase == ConnectionPhase.connected ? 'Connection lost — reconnecting…' : null);
  }

  void _scheduleRetry([String? reason]) {
    if (!_wanted || _disposed) return;
    _attempt++;
    final backoff = min(_maxBackoffMs, 500 * pow(2, min(_attempt - 1, 10)).toInt());
    final delay = Duration(milliseconds: backoff + Random().nextInt(300));
    _phase = ConnectionPhase.reconnecting;
    _latencyMs = null;
    if (reason != null) _message = reason;
    _nextRetryAt = DateTime.now().add(delay);
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () => unawaited(_open()));
    _notify();
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _nextRetryAt = null;
  }

  void _teardownSocket() {
    _heartbeat?.cancel();
    _handshakeTimer?.cancel();
    _resumeCheck?.cancel();
    _heartbeat = null;
    _handshakeTimer = null;
    _resumeCheck = null;
    for (final t in _ackTimers.values) {
      t.cancel();
    }
    _ackTimers.clear();
    unawaited(_subscription?.cancel());
    _subscription = null;
    final socket = _socket;
    _socket = null;
    if (socket != null) unawaited(socket.close().catchError((Object _) {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_wanted) return;
    if (_phase == ConnectionPhase.connected) {
      // The OS may have silently dropped the socket while suspended: probe it.
      final resumedAt = nowMs();
      _send(Frames.ping(resumedAt));
      _resumeCheck?.cancel();
      final session = _session;
      _resumeCheck = Timer(const Duration(seconds: 3), () {
        if (session == _session && _lastInboundMs < resumedAt) _onClosed(session);
      });
    } else if (_phase == ConnectionPhase.reconnecting || _phase == ConnectionPhase.idle) {
      _attempt = 0;
      _cancelRetry();
      unawaited(_open());
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _session++;
    _cancelRetry();
    _teardownSocket();
    unawaited(_events.close());
    super.dispose();
  }
}
