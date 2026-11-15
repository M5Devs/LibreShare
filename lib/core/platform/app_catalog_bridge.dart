import 'dart:io';

import 'package:flutter/services.dart';

/// Metadata for an installed app surfaced by the picker.
class InstalledAppInfo {
  const InstalledAppInfo({
    required this.label,
    required this.packageName,
    required this.apkPath,
    required this.sizeBytes,
    this.iconBytes,
  });

  final String label;
  final String packageName;
  final String apkPath;
  final int sizeBytes;
  final List<int>? iconBytes;

  static InstalledAppInfo fromMap(Map<dynamic, dynamic> map) {
    final icon = map['icon'];
    return InstalledAppInfo(
      label: map['label']?.toString() ?? 'Unknown',
      packageName: map['packageName']?.toString() ?? '',
      apkPath: map['apkPath']?.toString() ?? '',
      sizeBytes: int.tryParse(map['size']?.toString() ?? '0') ?? 0,
      iconBytes: icon is List ? icon.whereType<int>().toList() : null,
    );
  }
}

/// Read-only bridge used to enumerate installed apps for the picker.
///
/// Kept separate from [NativeBridge] so the protected platform layer stays
/// untouched. Every call degrades to an empty list when the native side is
/// unavailable (desktop, tests, missing permission).
class AppCatalogBridge {
  AppCatalogBridge._();

  static const MethodChannel _channel =
      MethodChannel('com.<secret-hidden>.libreshare/apps');

  static Future<List<InstalledAppInfo>> listInstalledApps() async {
    if (!Platform.isAndroid) return const [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('listInstalledApps');
      if (raw == null) return const [];
      return raw
          .whereType<Map>()
          .map((e) => InstalledAppInfo.fromMap(Map<dynamic, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
