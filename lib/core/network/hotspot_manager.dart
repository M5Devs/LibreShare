import 'dart:io';
import 'package:flutter/services.dart';

class HotspotManager {
  static const MethodChannel _channel = MethodChannel('com.m5dev.libreshare/hotspot');

  static Future<Map<String, String>?> startHotspot() async {
    if (!Platform.isAndroid) {
      return {
        'ssid': 'LibreShare-Mock',
        'password': '123',
        'ip': '192.168.43.1',
      };
    }

    try {
      final result = await _channel.invokeMethod<Map>('startHotspot');
      if (result != null) {
        return result.map((key, value) => MapEntry(key.toString(), value.toString()));
      }
    } on PlatformException catch (e) {
      if (e.code == 'HOTSPOT_IP_NOT_FOUND') {
        throw Exception('Hotspot started but IP address could not be detected. Please try again.');
      } else if (e.code == 'PERMISSION_DENIED') {
        throw Exception('Hotspot permission denied by system.');
      } else if (e.code == 'UNSUPPORTED') {
        throw Exception('LocalOnlyHotspot requires Android 8.0 or newer.');
      } else if (e.code == 'HOTSPOT_FAILED') {
        throw Exception('Failed to start hotspot: ${e.message ?? e.code}');
      } else {
        throw Exception('Hotspot error (${e.code}): ${e.message}');
      }
    }
    return null;
  }

  static Future<void> stopHotspot() async {
    if (!Platform.isAndroid) {
      return;
    }

    try {
      await _channel.invokeMethod('stopHotspot');
    } on PlatformException catch (_) {
      rethrow;
    }
  }
}
