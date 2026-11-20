import 'protocol.dart';

/// Where discovery information came from.
enum DiscoverySource { mdns, udp, qr, manual, saved }

/// A desktop the phone can connect to.
class DesktopTarget {
  const DesktopTarget({
    required this.hosts,
    required this.port,
    this.deviceId,
    this.name = 'Desktop',
    this.platform = '',
    this.pairingToken,
    this.source = DiscoverySource.manual,
  });

  final String? deviceId;
  final String name;
  final String platform;
  final List<String> hosts;
  final int port;
  final String? pairingToken;
  final DiscoverySource source;

  String get primaryHost => hosts.isEmpty ? '' : hosts.first;

  DesktopTarget copyWith({List<String>? hosts, int? port, String? pairingToken, String? name}) => DesktopTarget(
    deviceId: deviceId,
    name: name ?? this.name,
    platform: platform,
    hosts: hosts ?? this.hosts,
    port: port ?? this.port,
    pairingToken: pairingToken ?? this.pairingToken,
    source: source,
  );

  /// Parses the desktop's pairing QR code:
  /// `barcodesync://pair?v=1&host=…&port=…&token=…&id=…&name=…&platform=…&alt=…`
  static DesktopTarget? fromPairingUri(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'barcodesync' || uri.host != 'pair') return null;
    final q = uri.queryParameters;
    final host = q['host'];
    final port = int.tryParse(q['port'] ?? '');
    if (host == null || host.isEmpty || port == null || port <= 0 || port > 65535) return null;
    final alt = (q['alt'] ?? '').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
    return DesktopTarget(
      deviceId: q['id'],
      name: (q['name'] ?? '').isEmpty ? 'Desktop' : q['name']!,
      platform: q['platform'] ?? '',
      hosts: {host, ...alt}.toList(),
      port: port,
      pairingToken: q['token'],
      source: DiscoverySource.qr,
    );
  }

  /// Parses `192.168.1.20`, `192.168.1.20:47800` or `ws://192.168.1.20:47800`.
  static DesktopTarget? fromManualInput(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'ws://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    final port = uri.hasPort ? uri.port : kDefaultWsPort;
    return DesktopTarget(hosts: [uri.host], port: port, name: uri.host, source: DiscoverySource.manual);
  }
}

/// A desktop found on the local network.
class DiscoveredDesktop {
  const DiscoveredDesktop({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.hosts,
    required this.port,
    required this.source,
    required this.lastSeen,
    this.serviceName,
  });

  final String deviceId;
  final String name;
  final String platform;
  final List<String> hosts;
  final int port;
  final DiscoverySource source;
  final DateTime lastSeen;
  final String? serviceName;

  DesktopTarget toTarget({String? token}) => DesktopTarget(
    deviceId: deviceId,
    name: name,
    platform: platform,
    hosts: hosts,
    port: port,
    pairingToken: token,
    source: source,
  );
}

/// A desktop this phone has paired with before.
class PairedDesktop {
  const PairedDesktop({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.hosts,
    required this.port,
    required this.pairingToken,
    required this.lastConnected,
  });

  factory PairedDesktop.fromJson(Map<String, dynamic> json) => PairedDesktop(
    deviceId: json['deviceId'] as String? ?? '',
    name: json['name'] as String? ?? 'Desktop',
    platform: json['platform'] as String? ?? '',
    hosts: (json['hosts'] as List<dynamic>? ?? const []).whereType<String>().toList(),
    port: (json['port'] as num?)?.toInt() ?? kDefaultWsPort,
    pairingToken: json['pairingToken'] as String? ?? '',
    lastConnected: DateTime.fromMillisecondsSinceEpoch((json['lastConnected'] as num?)?.toInt() ?? 0),
  );

  final String deviceId;
  final String name;
  final String platform;
  final List<String> hosts;
  final int port;
  final String pairingToken;
  final DateTime lastConnected;

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'name': name,
    'platform': platform,
    'hosts': hosts,
    'port': port,
    'pairingToken': pairingToken,
    'lastConnected': lastConnected.millisecondsSinceEpoch,
  };

  DesktopTarget toTarget() => DesktopTarget(
    deviceId: deviceId,
    name: name,
    platform: platform,
    hosts: hosts,
    port: port,
    pairingToken: pairingToken,
    source: DiscoverySource.saved,
  );
}

enum ScanDelivery { sending, delivered, queued, paused, failed }

/// One scan made on this phone during the current session.
class ScanRecord {
  ScanRecord({
    required this.messageId,
    required this.code,
    required this.format,
    required this.timestamp,
    this.delivery = ScanDelivery.sending,
    this.detail,
  });

  final String messageId;
  final String code;
  final String format;
  final int timestamp;
  ScanDelivery delivery;
  String? detail;
}

String platformLabel(String platform) => switch (platform.toLowerCase()) {
  'windows' => 'Windows',
  'macos' => 'macOS',
  'linux' => 'Linux',
  'android' => 'Android',
  'ios' => 'iOS',
  _ => platform.isEmpty ? 'Desktop' : platform,
};
