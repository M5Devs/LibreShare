import 'package:flutter_test/flutter_test.dart';
import 'package:libreshare/state/network_address.dart';

void main() {
  group('isCellularAddress', () {
    test('flags carrier NAT ranges', () {
      expect(NetworkAddress.isCellularAddress('10.135.24.241'), isTrue);
      expect(NetworkAddress.isCellularAddress('10.0.0.1'), isTrue);
      expect(NetworkAddress.isCellularAddress('100.64.1.5'), isTrue);
    });

    test('does not flag private AP ranges', () {
      expect(NetworkAddress.isCellularAddress('192.168.43.1'), isFalse);
      expect(NetworkAddress.isCellularAddress('192.168.1.10'), isFalse);
      expect(NetworkAddress.isCellularAddress('172.16.0.1'), isFalse);
    });
  });

  group('isHotspotAddress', () {
    test('accepts tethering and private ranges', () {
      expect(NetworkAddress.isHotspotAddress('192.168.43.1'), isTrue);
      expect(NetworkAddress.isHotspotAddress('192.168.1.5'), isTrue);
      expect(NetworkAddress.isHotspotAddress('172.20.10.1'), isTrue);
    });

    test('rejects cellular addresses that would break the QR link', () {
      // The exact bug seen in the field: hotspot up, cellular IP advertised.
      expect(NetworkAddress.isHotspotAddress('10.135.24.241'), isFalse);
      expect(NetworkAddress.isHotspotAddress('100.64.0.9'), isFalse);
    });

    test('rejects empty and public addresses', () {
      expect(NetworkAddress.isHotspotAddress(''), isFalse);
      expect(NetworkAddress.isHotspotAddress('8.8.8.8'), isFalse);
    });

    test('rejects the 172 block outside the private range', () {
      expect(NetworkAddress.isHotspotAddress('172.15.0.1'), isFalse);
      expect(NetworkAddress.isHotspotAddress('172.32.0.1'), isFalse);
    });
  });

  group('rank', () {
    test('orders tethering above generic private above cellular', () {
      final ordered = ['10.135.24.241', '192.168.1.5', '192.168.43.1']
        ..sort((a, b) => NetworkAddress.rank(a).compareTo(NetworkAddress.rank(b)));
      expect(ordered, ['192.168.43.1', '192.168.1.5', '10.135.24.241']);
    });
  });
}
