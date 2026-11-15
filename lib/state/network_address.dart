import 'dart:io';

/// Resolves the address peers should use to reach this device.
///
/// The distinction that matters is *which* interface an address belongs to. A
/// phone that is hosting a hotspot also keeps its cellular interface up, and
/// that interface routinely owns a carrier-NAT address (typically `10.x`, or
/// the `100.64.0.0/10` CGNAT range). Advertising such an address is useless to
/// a peer sitting on the hotspot: the address is not routable from the local
/// link, and the QR code simply fails to connect.
///
/// So when hotspot mode is active only genuine private-AP addresses are
/// accepted, and the cellular ones are rejected outright rather than shown.
class NetworkAddress {
  NetworkAddress._();

  /// Ranges used by carrier NAT / mobile data. Never a valid hotspot address.
  static const List<String> _cellularPrefixes = ['10.', '100.'];

  static final RegExp _private172 =
      RegExp(r'^172\.(1[6-9]|2\d|3[01])\.');

  /// True for addresses a peer on the local link could actually reach.
  ///
  /// `192.168.43.x` is the classic Android tethering subnet and is treated as
  /// the strongest signal, followed by any other `192.168.x.x`, then the
  /// private `172.16-31.x.x` block.
  static bool isHotspotAddress(String ip) {
    if (ip.isEmpty) return false;
    if (isCellularAddress(ip)) return false;
    if (ip.startsWith('192.168.')) return true;
    if (_private172.hasMatch(ip)) return true;
    return false;
  }

  /// True for carrier-assigned addresses that must never be advertised while
  /// the device is hosting its own hotspot.
  static bool isCellularAddress(String ip) =>
      _cellularPrefixes.any((prefix) => ip.startsWith(prefix));

  /// Ranks candidate addresses so the most reachable one wins.
  static int rank(String ip) {
    if (ip.startsWith('192.168.43.')) return 0;
    if (ip.startsWith('192.168.')) return 1;
    if (_private172.hasMatch(ip)) return 2;
    if (isCellularAddress(ip)) return 4;
    return 3;
  }

  /// Scans local interfaces for the best hotspot-capable address.
  ///
  /// Returns null when the device has no private-AP address at all, which is
  /// the honest answer — the caller surfaces an error instead of advertising a
  /// cellular address that cannot work.
  static Future<String?> findHotspotAddress() async {
    List<NetworkInterface> interfaces;
    try {
      interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
    } catch (_) {
      return null;
    }

    final candidates = <String>[];
    for (final interface in interfaces) {
      for (final addr in interface.addresses) {
        final ip = addr.address;
        if (isHotspotAddress(ip)) candidates.add(ip);
      }
    }

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => rank(a).compareTo(rank(b)));
    return candidates.first;
  }
}
