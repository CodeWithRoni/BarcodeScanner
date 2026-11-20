import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/device_identity.dart';
import '../core/models.dart';
import '../core/storage.dart';
import 'connection_service.dart';
import 'discovery_service.dart';
import 'feedback_service.dart';

/// Wires discovery, the connection and feedback together and owns settings.
class AppController extends ChangeNotifier {
  AppController._(this.storage, this.identity, this.discovery, this.connection, this.feedback, this._settings);

  final AppStorage storage;
  final DeviceIdentity identity;
  final DiscoveryService discovery;
  final ConnectionService connection;
  final FeedbackService feedback;
  ScannerSettings _settings;
  StreamSubscription<ScanEvent>? _events;

  ScannerSettings get settings => _settings;
  List<PairedDesktop> get paired => storage.pairedDesktops;

  static Future<AppController> bootstrap() async {
    final storage = await AppStorage.open();
    final identity = await DeviceIdentity.resolve(storage.deviceId);
    final discovery = DiscoveryService(identity);
    final connection = ConnectionService(identity: identity, storage: storage, discovery: discovery);
    final feedback = FeedbackService();
    final controller = AppController._(storage, identity, discovery, connection, feedback, storage.settings);
    await feedback.init();
    controller._wire();
    return controller;
  }

  void _wire() {
    discovery.addListener(_onDiscovery);
    connection.addListener(_onConnection);
    _events = connection.events.listen((e) => unawaited(feedback.onAck(e.status, _settings)));
    unawaited(discovery.start());
    final last = paired.isEmpty ? null : paired.first;
    if (_settings.autoConnect && last != null) {
      unawaited(connection.connect(last.toTarget()));
    }
  }

  /// Auto-connects to a previously paired desktop as soon as it is seen.
  void _onDiscovery() {
    if (!_settings.autoConnect || connection.userDisconnected) return;
    if (connection.phase == ConnectionPhase.reconnecting) {
      final id = connection.desktopId;
      if (id != null && discovery.find(id) != null) connection.retryNow();
      return;
    }
    if (connection.isActive || connection.phase == ConnectionPhase.rejected) return;
    for (final p in paired) {
      if (discovery.find(p.deviceId) != null) {
        unawaited(connection.connect(p.toTarget()));
        return;
      }
    }
  }

  /// Discovery only runs while we are not connected, to save battery.
  void _onConnection() {
    if (connection.isConnected) {
      if (discovery.isRunning) unawaited(discovery.stop());
    } else if (!discovery.isRunning) {
      unawaited(discovery.start());
    }
    notifyListeners();
  }

  Future<void> connectTo(DesktopTarget target) => connection.connect(target);

  Future<void> connectDiscovered(DiscoveredDesktop desktop) {
    String? token;
    for (final p in paired) {
      if (p.deviceId == desktop.deviceId) token = p.pairingToken;
    }
    return connection.connect(desktop.toTarget(token: token));
  }

  Future<void> forget(String deviceId) async {
    if (connection.desktopId == deviceId) {
      await connection.disconnect(forget: true);
    } else {
      await storage.forgetPaired(deviceId);
    }
    notifyListeners();
  }

  Future<void> updateSettings(ScannerSettings next) async {
    _settings = next;
    notifyListeners();
    await storage.saveSettings(next);
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    discovery.removeListener(_onDiscovery);
    connection.removeListener(_onConnection);
    connection.dispose();
    discovery.dispose();
    unawaited(feedback.dispose());
    super.dispose();
  }
}
