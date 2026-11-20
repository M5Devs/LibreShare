import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Total / free bytes for the primary storage volume.
class StorageInfo {
  const StorageInfo({required this.totalBytes, required this.freeBytes});

  final int totalBytes;
  final int freeBytes;

  int get usedBytes => (totalBytes - freeBytes).clamp(0, totalBytes);
}

/// Reads device storage statistics.
///
/// Android answers through the native `storage` channel (StatFs on /data).
/// Desktop platforms fall back to `df`, which reports the same numbers without
/// a plugin. Returns null only when neither source can produce a figure, so the
/// UI can distinguish "unknown" from a genuine zero.
class StorageBridge {
  StorageBridge._();

  static const MethodChannel channel =
      MethodChannel('com.m5dev.libreshare/storage');

  static Future<StorageInfo?> getStorageInfo() async {
    if (Platform.isAndroid) return _fromChannel();
    if (Platform.isLinux || Platform.isMacOS) return _fromDf();
    return null;
  }

  static Future<StorageInfo?> _fromChannel() async {
    try {
      final raw = await channel.invokeMethod<Map>('getStorageInfo');
      if (raw == null) return null;
      return _fromParts(raw['total'], raw['free']);
    } catch (_) {
      return null;
    }
  }

  /// Parses `df -k` output; the second line is the volume holding the path.
  static Future<StorageInfo?> _fromDf() async {
    try {
      final result = await Process.run('df', ['-k', '/']);
      if (result.exitCode != 0) return null;
      final lines = const LineSplitter().convert(result.stdout.toString());
      if (lines.length < 2) return null;
      final columns = lines[1].trim().split(RegExp(r'\s+'));
      if (columns.length < 4) return null;
      // 1K blocks: total, used, available.
      final totalKb = int.tryParse(columns[1]);
      final freeKb = int.tryParse(columns[3]);
      if (totalKb == null || freeKb == null) return null;
      return StorageInfo(totalBytes: totalKb * 1024, freeBytes: freeKb * 1024);
    } catch (_) {
      return null;
    }
  }

  static StorageInfo? _fromParts(Object? total, Object? free) {
    final totalBytes = int.tryParse(total?.toString() ?? '');
    final freeBytes = int.tryParse(free?.toString() ?? '');
    if (totalBytes == null || freeBytes == null || totalBytes <= 0) return null;
    return StorageInfo(
      totalBytes: totalBytes,
      freeBytes: freeBytes.clamp(0, totalBytes),
    );
  }

  /// Parses a raw channel reply. Exposed so tests can cover the exact
  /// conversion the native handler's string payload goes through.
  static StorageInfo? debugParse({Object? total, Object? free}) =>
      _fromParts(total, free);
}
