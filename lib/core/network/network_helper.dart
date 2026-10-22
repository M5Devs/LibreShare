import 'dart:io';

class NetworkHelper {
  static Future<String> getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      final cellularKeywords = ['rmnet', 'ccmni', 'pdp', 'dummy'];

      String? wifiIp;
      String? anyLocalIp;

      for (var interface in interfaces) {
        final isCellular = cellularKeywords.any((kw) => interface.name.toLowerCase().contains(kw));
        if (isCellular) continue;

        for (var addr in interface.addresses) {
          final ip = addr.address;

          if (ip.startsWith('192.168.43.')) {
            return ip;
          }

          if (ip.startsWith('192.168.')) {
            wifiIp = ip;
          } else if (ip.startsWith('10.') || ip.startsWith('172.')) {
            anyLocalIp = ip;
          }
        }
      }

      if (wifiIp != null) return wifiIp;
      if (anyLocalIp != null) return anyLocalIp;

    } catch (e) {
      // Ignore
    }

    return '192.168.43.1';
  }
}
