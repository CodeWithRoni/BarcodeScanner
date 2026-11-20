/// Strictly typed JSON wire protocol shared with the BarcodeSync desktop app.
library;

import 'dart:convert';

const String kServiceType = '_barcodesync._tcp';
const int kDiscoveryPort = 47810;
const int kDefaultWsPort = 47800;
const int kProtocolVersion = 1;

int nowMs() => DateTime.now().millisecondsSinceEpoch;

enum HandshakeStatus { accepted, pending, rejected }

enum AckStatus { ok, duplicate, paused, unauthorized, error }

/// Frames received from the desktop.
sealed class DesktopFrame {
  const DesktopFrame();

  static DesktopFrame? parse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final json = decoded;
    switch (json['type']) {
      case 'handshake_ack':
        return HandshakeAck.fromJson(json);
      case 'ack':
        return AckFrame.fromJson(json);
      case 'ping':
        return PingFrame(_int(json['timestamp']));
      case 'pong':
        return PongFrame(_int(json['timestamp']));
      case 'status':
        return StatusFrame(paused: json['paused'] == true);
      default:
        return null;
    }
  }
}

class HandshakeAck extends DesktopFrame {
  const HandshakeAck({
    required this.status,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.appVersion,
    required this.paused,
    this.pairingToken,
    this.reason,
  });

  factory HandshakeAck.fromJson(Map<String, dynamic> json) => HandshakeAck(
    status: HandshakeStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => HandshakeStatus.rejected,
    ),
    deviceId: _str(json['deviceId']),
    deviceName: _str(json['deviceName'], 'Desktop'),
    platform: _str(json['platform']),
    appVersion: _str(json['appVersion']),
    paused: json['paused'] == true,
    pairingToken: json['pairingToken'] as String?,
    reason: json['reason'] as String?,
  );

  final HandshakeStatus status;
  final String deviceId;
  final String deviceName;
  final String platform;
  final String appVersion;
  final bool paused;
  final String? pairingToken;
  final String? reason;
}

class AckFrame extends DesktopFrame {
  const AckFrame({required this.messageId, required this.status, this.detail});

  factory AckFrame.fromJson(Map<String, dynamic> json) => AckFrame(
    messageId: _str(json['messageId']),
    status: AckStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => AckStatus.error,
    ),
    detail: json['detail'] as String?,
  );

  final String messageId;
  final AckStatus status;
  final String? detail;
}

class PingFrame extends DesktopFrame {
  const PingFrame(this.timestamp);
  final int timestamp;
}

class PongFrame extends DesktopFrame {
  const PongFrame(this.timestamp);
  final int timestamp;
}

class StatusFrame extends DesktopFrame {
  const StatusFrame({required this.paused});
  final bool paused;
}

/// Frames sent to the desktop.
abstract final class Frames {
  static String handshake({
    required String deviceId,
    required String deviceName,
    required String platform,
    required String appVersion,
    String? pairingToken,
  }) => jsonEncode({
    'type': 'handshake',
    'deviceId': deviceId,
    'deviceName': deviceName,
    'platform': platform,
    'appVersion': appVersion,
    if (pairingToken != null) 'pairingToken': pairingToken,
  });

  static String scan({
    required String messageId,
    required String code,
    required String format,
    required int timestamp,
  }) => jsonEncode({
    'type': 'scan',
    'messageId': messageId,
    'code': code,
    'format': format,
    'timestamp': timestamp,
  });

  static String ping(int timestamp) => jsonEncode({'type': 'ping', 'timestamp': timestamp});

  static String pong(int timestamp) => jsonEncode({'type': 'pong', 'timestamp': timestamp});

  static String bye() => jsonEncode({'type': 'bye'});

  static String discover({
    required String deviceId,
    required String deviceName,
    required String platform,
    required String appVersion,
  }) => jsonEncode({
    'type': 'discover',
    'deviceId': deviceId,
    'deviceName': deviceName,
    'platform': platform,
    'appVersion': appVersion,
  });
}

/// UDP `announce` reply from a desktop.
class AnnouncePacket {
  const AnnouncePacket({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.appVersion,
    required this.port,
    required this.ips,
  });

  static AnnouncePacket? tryParse(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic> || json['type'] != 'announce') return null;
      final port = _int(json['port']);
      final id = _str(json['deviceId']);
      if (port <= 0 || id.isEmpty) return null;
      return AnnouncePacket(
        deviceId: id,
        deviceName: _str(json['deviceName'], 'Desktop'),
        platform: _str(json['platform']),
        appVersion: _str(json['appVersion']),
        port: port,
        ips: (json['ips'] is List) ? (json['ips'] as List).whereType<String>().toList() : const [],
      );
    } on FormatException {
      return null;
    }
  }

  final String deviceId;
  final String deviceName;
  final String platform;
  final String appVersion;
  final int port;
  final List<String> ips;
}

String _str(Object? v, [String fallback = '']) => v is String && v.isNotEmpty ? v : fallback;

int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
