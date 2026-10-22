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
    } on PlatformException catch (_) {
      rethrow;
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
