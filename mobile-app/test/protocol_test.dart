import 'dart:convert';

import 'package:barcodesync/src/core/models.dart';
import 'package:barcodesync/src/core/protocol.dart';
import 'package:barcodesync/src/core/storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('protocol', () {
    test('parses an accepted handshake', () {
      final frame = DesktopFrame.parse(
        '{"type":"handshake_ack","status":"accepted","deviceId":"d1","deviceName":"Office PC",'
        '"platform":"windows","appVersion":"1.0.0","protocolVersion":1,"paused":false,"pairingToken":"tok"}',
      );
      expect(frame, isA<HandshakeAck>());
      final ack = frame! as HandshakeAck;
      expect(ack.status, HandshakeStatus.accepted);
      expect(ack.deviceName, 'Office PC');
      expect(ack.pairingToken, 'tok');
    });

    test('parses scan acks and ignores junk', () {
      final ack = DesktopFrame.parse('{"type":"ack","messageId":"m1","status":"duplicate"}');
      expect(ack, isA<AckFrame>());
      expect((ack! as AckFrame).status, AckStatus.duplicate);
      expect(DesktopFrame.parse('not json'), isNull);
      expect(DesktopFrame.parse('{"type":"unknown"}'), isNull);
    });

    test('encodes scan and handshake frames', () {
      final scan = jsonDecode(Frames.scan(messageId: 'm', code: '4006381333931', format: 'ean13', timestamp: 7)) as Map<String, dynamic>;
      expect(scan, {'type': 'scan', 'messageId': 'm', 'code': '4006381333931', 'format': 'ean13', 'timestamp': 7});
      final hs = jsonDecode(
        Frames.handshake(deviceId: 'p', deviceName: 'Pixel 9', platform: 'android', appVersion: '1.0.0'),
      ) as Map<String, dynamic>;
      expect(hs.containsKey('pairingToken'), isFalse);
      expect(hs['type'], 'handshake');
    });

    test('parses announce packets', () {
      final p = AnnouncePacket.tryParse(
        '{"type":"announce","deviceId":"d","deviceName":"Mac","platform":"macos","appVersion":"1.0.0","port":47800,"ips":["10.0.0.4"]}',
      );
      expect(p?.port, 47800);
      expect(p?.ips, ['10.0.0.4']);
    });
  });

  group('targets', () {
    test('parses a pairing QR code', () {
      final t = DesktopTarget.fromPairingUri(
        'barcodesync://pair?v=1&host=192.168.1.5&port=47800&token=abc&id=dev&name=Roni%27s%20PC&platform=windows&alt=10.0.0.2',
      );
      expect(t, isNotNull);
      expect(t!.hosts, ['192.168.1.5', '10.0.0.2']);
      expect(t.name, "Roni's PC");
      expect(t.pairingToken, 'abc');
      expect(DesktopTarget.fromPairingUri('https://example.com'), isNull);
    });

    test('parses manual addresses', () {
      expect(DesktopTarget.fromManualInput('192.168.0.9')?.port, kDefaultWsPort);
      expect(DesktopTarget.fromManualInput('192.168.0.9:5000')?.port, 5000);
      expect(DesktopTarget.fromManualInput('  '), isNull);
    });
  });

  test('random ids look like UUID v4', () {
    final id = randomId();
    expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(id), isTrue);
  });
}
