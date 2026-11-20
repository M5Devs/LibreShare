import 'package:flutter_test/flutter_test.dart';
import 'package:libreshare/core/network/peer_connector.dart';

void main() {
  group('PeerConnector.parse', () {
    test('reads host, port and pairing token from an http URL', () {
      final endpoint =
          PeerConnector.parse('http://192.168.43.1:5000/?t=deadbeef');

      expect(endpoint, isNotNull);
      expect(endpoint!.host, '192.168.43.1');
      expect(endpoint.port, 5000);
      expect(endpoint.token, 'deadbeef');
      expect(endpoint.secure, isFalse);
      expect(endpoint.baseUrl, 'http://192.168.43.1:5000');
      expect(endpoint.pairingUrl, 'http://192.168.43.1:5000/?t=deadbeef');
    });

    test('accepts the libreshare:// scheme used by the native QR payload', () {
      final endpoint = PeerConnector.parse('libreshare://10.0.0.7:5000/?t=abc');

      expect(endpoint, isNotNull);
      expect(endpoint!.host, '10.0.0.7');
      expect(endpoint.port, 5000);
      expect(endpoint.token, 'abc');
      expect(endpoint.scheme, 'http');
    });

    test('accepts https and defaults the port to 443', () {
      final endpoint = PeerConnector.parse('https://share.example.com');

      expect(endpoint, isNotNull);
      expect(endpoint!.port, 443);
      expect(endpoint.secure, isTrue);
      expect(endpoint.pairingUrl, 'https://share.example.com:443');
    });

    test('accepts a bare host:port typed by the user', () {
      final endpoint = PeerConnector.parse('192.168.0.12:8080');

      expect(endpoint, isNotNull);
      expect(endpoint!.host, '192.168.0.12');
      expect(endpoint.port, 8080);
      expect(endpoint.token, isNull);
    });

    test('treats an empty token as absent', () {
      expect(PeerConnector.parse('http://10.0.0.1:5000/?t=')!.token, isNull);
    });

    test('rejects payloads that are not peer addresses', () {
      const rejected = [
        '',
        '   ',
        'WIFI:S:HomeNet;T:WPA;P:hunter2;;',
        'mailto:someone@example.com',
        'ftp://10.0.0.1:21',
        'just some text',
        'http://',
      ];

      for (final payload in rejected) {
        expect(
          PeerConnector.parse(payload),
          isNull,
          reason: 'should reject "$payload"',
        );
      }
    });
  });

  group('PeerConnector.probe', () {
    test('returns false instead of throwing when the peer is unreachable', () async {
      // Port 1 on localhost is never listening, so this exercises the real
      // socket error path rather than a stubbed failure.
      const endpoint = PeerEndpoint(host: '127.0.0.1', port: 1);

      final reachable = await PeerConnector.probe(
        endpoint,
        timeout: const Duration(milliseconds: 500),
      );

      expect(reachable, isFalse);
    });
  });
}
