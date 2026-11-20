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

  /// Opens a file with whatever app the platform associates with its type.
  ///
  /// Returns false when no viewer is installed or the path is gone, so the UI
  /// can tell the user instead of appearing to do nothing.
  static Future<bool> openFile(String path, {String? mimeType}) async {
    if (Platform.isLinux || Platform.isMacOS) return _openOnDesktop(path);
    if (!Platform.isAndroid) return false;
    try {
      final opened = await _serviceChannel.invokeMethod<bool>(
        'openFile',
        {'path': path, 'mime': mimeType},
      );
      return opened ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Hands the file to the desktop's default handler.
  ///
  /// `xdg-open` and `open` exit non-zero when no association exists, which is
  /// the desktop equivalent of "no app can open this".
  static Future<bool> _openOnDesktop(String path) async {
    try {
      final result = Platform.isMacOS
          ? await Process.run('open', [path])
          : await Process.run('xdg-open', [path]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<void> scanMediaFile(String path) async {
    if (!Platform.isAndroid) return;
    try {
      await _serviceChannel.invokeMethod('scanMediaFile', {'path': path});
    } catch (_) {}
  }
}
