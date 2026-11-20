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
      iconBytes: _decodeIcon(icon),
    );
  }

  /// The platform side ships PNG bytes; a `Uint8List` arrives as one, but a
  /// channel that only carries ints yields a `List<dynamic>`. Both must work,
  /// and a list of doubles (some platforms widen) must not corrupt icons.
  static List<int>? _decodeIcon(Object? icon) {
    if (icon is Uint8List) return icon.isEmpty ? null : icon;
    if (icon is List) {
      final bytes = icon.whereType<int>().toList(growable: false);
      return bytes.isEmpty ? null : bytes;
    }
    return null;
  }
}

/// Read-only bridge used to enumerate installed apps for the picker.
///
/// Kept separate from [NativeBridge] so the protected platform layer stays
/// untouched. Every call degrades to an empty list when the native side is
/// unavailable (desktop, tests, missing permission).
class AppCatalogBridge {
  AppCatalogBridge._();

  static const MethodChannel channel =
      MethodChannel('com.m5dev.libreshare/catalog');

  static Future<List<InstalledAppInfo>> listInstalledApps() async {
    if (!Platform.isAndroid) return const [];
    try {
      final raw = await channel.invokeMethod<List<dynamic>>('listInstalledApps');
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
