import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;

import '../core/device_identity.dart';
import '../core/models.dart';
import '../core/protocol.dart';

/// Finds BarcodeSync desktops on the local network using mDNS
/// (`_barcodesync._tcp`) with a UDP broadcast fallback.
class DiscoveryService extends ChangeNotifier {
  DiscoveryService(this._identity);

  final DeviceIdentity _identity;
  static const _udpTtl = Duration(seconds: 9);

  final Map<String, DiscoveredDesktop> _mdns = {};
  final Map<String, DiscoveredDesktop> _udp = {};
  nsd.Discovery? _discovery;
  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  Timer? _pruneTimer;
  bool _running = false;
  bool _starting = false;
  bool _disposed = false;
  String? lastError;

  bool get isRunning => _running;

  /// Desktops merged from every source, most recently seen first.
  List<DiscoveredDesktop> get desktops {
    final merged = <String, DiscoveredDesktop>{};
    for (final d in [..._udp.values, ..._mdns.values]) {
      final existing = merged[d.deviceId];
      if (existing == null) {
        merged[d.deviceId] = d;
      } else {
        merged[d.deviceId] = DiscoveredDesktop(
          deviceId: d.deviceId,
          name: d.name,
          platform: d.platform.isNotEmpty ? d.platform : existing.platform,
          hosts: {...existing.hosts, ...d.hosts}.toList(),
          port: d.port,
          source: existing.source,
          lastSeen: d.lastSeen.isAfter(existing.lastSeen) ? d.lastSeen : existing.lastSeen,
          serviceName: d.serviceName ?? existing.serviceName,
        );
      }
    }
    return merged.values.toList()..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
  }

  DiscoveredDesktop? find(String deviceId) {
    for (final d in desktops) {
      if (d.deviceId == deviceId) return d;
    }
    return null;
  }

  Future<void> start() async {
    if (_running || _starting) return;
    _starting = true;
    lastError = null;
    try {
      await Future.wait([_startMdns(), _startUdp()]);
      _running = true;
      _pruneTimer = Timer.periodic(const Duration(seconds: 3), (_) => _prune());
    } finally {
      _starting = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _broadcastTimer?.cancel();
    _pruneTimer?.cancel();
    _broadcastTimer = null;
    _pruneTimer = null;
    _socket?.close();
    _socket = null;
    final discovery = _discovery;
    _discovery = null;
    if (discovery != null) {
      try {
        await nsd.stopDiscovery(discovery);
      } on Object catch (e) {
        debugPrint('[discovery] stop mdns failed: $e');
      }
    }
    _udp.clear();
    _mdns.clear();
    if (!_disposed) notifyListeners();
  }

  /// Sends an immediate burst of discovery packets (pull-to-refresh).
  void refresh() {
    _sendDiscover();
    Future<void>.delayed(const Duration(milliseconds: 400), _sendDiscover);
  }

  Future<void> _startMdns() async {
    try {
      final discovery = await nsd.startDiscovery(kServiceType, ipLookupType: nsd.IpLookupType.v4);
      discovery.addServiceListener(_onService);
      _discovery = discovery;
    } on Object catch (e) {
      lastError = 'mDNS unavailable: $e';
      debugPrint('[discovery] $lastError');
    }
  }

  void _onService(nsd.Service service, nsd.ServiceStatus status) {
    final name = service.name;
    if (name == null) return;
    if (status == nsd.ServiceStatus.lost) {
      if (_mdns.remove(name) != null) notifyListeners();
      return;
    }
    final txt = service.txt ?? const <String, Uint8List?>{};
    String prop(String key) {
      final v = txt[key];
      return v == null ? '' : utf8.decode(v, allowMalformed: true);
    }

    final hosts = (service.addresses ?? const <InternetAddress>[])
        .where((a) => a.type == InternetAddressType.IPv4 && !a.isLoopback)
        .map((a) => a.address)
        .toList();
    if (hosts.isEmpty && service.host != null && service.host!.isNotEmpty) {
      hosts.add(service.host!.endsWith('.') ? service.host!.substring(0, service.host!.length - 1) : service.host!);
    }
    final port = service.port;
    if (hosts.isEmpty || port == null) return;
    final id = prop('id');
    _mdns[name] = DiscoveredDesktop(
      deviceId: id.isEmpty ? name : id,
      name: prop('name').isEmpty ? name.replaceAll(RegExp(r'\s*\([^)]*\)$'), '') : prop('name'),
      platform: prop('platform'),
      hosts: hosts,
      port: port,
      source: DiscoverySource.mdns,
      lastSeen: DateTime.now(),
      serviceName: name,
    );
    notifyListeners();
  }

  Future<void> _startUdp() async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? dg;
        while ((dg = socket.receive()) != null) {
          _onDatagram(dg!);
        }
      });
      _socket = socket;
      _sendDiscover();
      _broadcastTimer = Timer.periodic(const Duration(seconds: 2), (_) => _sendDiscover());
    } on Object catch (e) {
      debugPrint('[discovery] udp unavailable: $e');
    }
  }

  void _sendDiscover() {
    final socket = _socket;
    if (socket == null) return;
    final payload = utf8.encode(
      Frames.discover(
        deviceId: _identity.deviceId,
        deviceName: _identity.deviceName,
        platform: _identity.platform,
        appVersion: _identity.appVersion,
      ),
    );
    try {
      socket.send(payload, InternetAddress('255.255.255.255'), kDiscoveryPort);
    } on Object catch (e) {
      // iOS blocks broadcast without the multicast entitlement; mDNS still works.
      debugPrint('[discovery] broadcast failed: $e');
    }
  }

  void _onDatagram(Datagram dg) {
    final packet = AnnouncePacket.tryParse(utf8.decode(dg.data, allowMalformed: true));
    if (packet == null) return;
    final source = dg.address.address;
    _udp[packet.deviceId] = DiscoveredDesktop(
      deviceId: packet.deviceId,
      name: packet.deviceName,
      platform: packet.platform,
      hosts: {source, ...packet.ips}.toList(),
      port: packet.port,
      source: DiscoverySource.udp,
      lastSeen: DateTime.now(),
    );
    notifyListeners();
  }

  void _prune() {
    final cutoff = DateTime.now().subtract(_udpTtl);
    final before = _udp.length;
    _udp.removeWhere((_, d) => d.lastSeen.isBefore(cutoff));
    if (_udp.length != before) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}
