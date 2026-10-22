import 'dart:io';

class NetworkHelper {
  static Future<String> getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      // لستة بالكروت المشبوهة بتاعت باقات الخطوط عشان نطنشها تماماً
      final cellularKeywords = ['rmnet', 'ccmni', 'pdp', 'dummy'];

      String? hotspotIp;
      String? wifiIp;
      String? anyLocalIp;

      for (var interface in interfaces) {
        // لو الكرت بتاع شريحة الخط .. طنشه واعدي
        final isCellular = cellularKeywords.any((kw) => interface.name.toLowerCase().contains(kw));
        if (isCellular) continue;

        for (var addr in interface.addresses) {
          final ip = addr.address;

          // 1. لو لقى آي بي الهوتسبوت بتاع أندرويد (أعلى أولوية)
          if (ip.startsWith('192.168.43.')) {
            return ip;
          }

          // 2. لو لقى آي بي راوتر عادي (192.168.x.x)
          if (ip.startsWith('192.168.')) {
            wifiIp = ip;
          } else if (ip.startsWith('10.') || ip.startsWith('172.')) {
            anyLocalIp = ip;
          }
        }
      }

      // إرجاع الأفضل بالترتيب
      if (wifiIp != null) return wifiIp;
      if (anyLocalIp != null) return anyLocalIp;

    } catch (e) {
      // لو حصل أي خطأ
    }

    // لو الهوتسبوت شغال بس النظام لسه مسجلوش في Dart، الافتراضي هو:
    return '192.168.43.1';
  }
}
