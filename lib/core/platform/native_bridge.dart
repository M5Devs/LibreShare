import 'dart:io';
import 'package:flutter/services.dart';

class NativeBridge {
  static const _serviceChannel = MethodChannel('com.m5dev.libreshare/service');
  static const _eventChannel = EventChannel('com.m5dev.libreshare/events');

  static Stream<Map<String, dynamic>> get events {
    if (!Platform.isAndroid) return const Stream.empty();
    return _eventChannel.receiveBroadcastStream().map((e) => Map<String, dynamic>.from(e as Map));
  }

  static Future<void> startForegroundService({required String text}) async {
    if (!Platform.isAndroid) return;
    try {
      await _serviceChannel.invokeMethod('start', {'text': text});
    } catch (_) {}
  }

  static Future<void> stopForegroundService() async {
    if (!Platform.isAndroid) return;
    try {
      await _serviceChannel.invokeMethod('stop');
    } catch (_) {}
  }
}
