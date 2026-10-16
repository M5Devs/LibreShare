import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';

class NetworkHelper {
  static Future<String?> getLocalIpAddress() async {
    try {
      final info = NetworkInfo();
      final wifiIp = await info.getWifiIP();
      if (wifiIp != null && wifiIp.isNotEmpty && wifiIp != '127.0.0.1' && wifiIp != '0.0.0.0') {
        return wifiIp;
      }
    } catch (_) {
      // Fallback if plugin fails or platform isn't supported
    }

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }
    } catch (_) {}

    return null;
  }
}
