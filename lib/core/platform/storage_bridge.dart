import 'dart:io';

import 'package:flutter/services.dart';

/// Total / free bytes for the primary storage volume.
class StorageInfo {
  const StorageInfo({required this.totalBytes, required this.freeBytes});

  final int totalBytes;
  final int freeBytes;

  int get usedBytes => (totalBytes - freeBytes).clamp(0, totalBytes);
}

/// Reads device storage statistics. Returns null when unavailable so the UI
/// can fall back to an "unavailable" label instead of guessing.
class StorageBridge {
  StorageBridge._();

  static const MethodChannel _channel =
      MethodChannel('com.<secret-hidden>.libreshare/storage');

  static Future<StorageInfo?> getStorageInfo() async {
    if (!Platform.isAndroid) return null;
    try {
      final raw = await _channel.invokeMethod<Map>('getStorageInfo');
      if (raw == null) return null;
      final total = int.tryParse(raw['total']?.toString() ?? '');
      final free = int.tryParse(raw['free']?.toString() ?? '');
      if (total == null || free == null) return null;
      return StorageInfo(totalBytes: total, freeBytes: free);
    } catch (_) {
      return null;
    }
  }
}
