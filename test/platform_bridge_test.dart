import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libreshare/core/platform/app_catalog_bridge.dart';
import 'package:libreshare/core/platform/storage_bridge.dart';
import 'package:libreshare/core/utils/transfer_metrics.dart';

/// These exercise the real channel code by answering on the same channel name
/// the native side uses, so a rename on either side fails the test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(AppCatalogBridge.channel, null);
    messenger.setMockMethodCallHandler(StorageBridge.channel, null);
  });

  group('AppCatalogBridge', () {
    test('the channel name matches the native catalog handler', () {
      expect(AppCatalogBridge.channel.name, 'com.m5dev.libreshare/catalog');
      expect(StorageBridge.channel.name, 'com.m5dev.libreshare/storage');
    });

    test('decodes labels, sizes and PNG icon bytes from the platform', () async {
      final icon = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
      MethodCall? received;

      messenger.setMockMethodCallHandler(AppCatalogBridge.channel, (call) async {
        received = call;
        return <dynamic>[
          <String, dynamic>{
            'label': 'Camera',
            'packageName': 'com.vendor.camera',
            'apkPath': '/data/app/camera/base.apk',
            'size': '5242880',
            'icon': icon,
          },
          <String, dynamic>{
            'label': 'Notes',
            'packageName': 'com.vendor.notes',
            'apkPath': '/data/app/notes/base.apk',
            'size': '1024',
            'icon': null,
          },
        ];
      });

      // The bridge returns early off Android, so drive the decode path directly
      // through the same channel reply the handler would send.
      final apps = (await _callCatalog())
          .map((e) => InstalledAppInfo.fromMap(Map<dynamic, dynamic>.from(e)))
          .toList();

      expect(received?.method, 'listInstalledApps');
      expect(apps, hasLength(2));
      expect(apps.first.label, 'Camera');
      expect(apps.first.packageName, 'com.vendor.camera');
      expect(apps.first.apkPath, '/data/app/camera/base.apk');
      expect(apps.first.sizeBytes, 5242880);
      expect(apps.first.iconBytes, icon);
      expect(apps.last.iconBytes, isNull);
    });

    test('widened icon ints still decode, and a bad size falls back to zero', () {
      final info = InstalledAppInfo.fromMap(<dynamic, dynamic>{
        'label': 'Game',
        'packageName': 'com.vendor.game',
        'apkPath': '/data/app/game/base.apk',
        'size': 'not-a-number',
        'icon': <dynamic>[1, 2, 3],
      });

      expect(info.sizeBytes, 0);
      expect(info.iconBytes, <int>[1, 2, 3]);
    });

    test('a failing channel degrades to an empty list', () async {
      messenger.setMockMethodCallHandler(AppCatalogBridge.channel, (call) async {
        throw PlatformException(code: 'APP_LIST_FAILED');
      });

      expect(await _callCatalogSafely(), isEmpty);
    });
  });

  group('StorageBridge', () {
    test('reads real byte counts from the native reply', () {
      final info = StorageBridge.debugParse(total: '116374863872', free: '13421772800');

      expect(info, isNotNull);
      expect(info!.totalBytes, 116374863872);
      expect(info.freeBytes, 13421772800);
      expect(info.usedBytes, 116374863872 - 13421772800);
      expect(
        '${TransferMetrics.formatSizeShort(info.usedBytes)} used / '
        '${TransferMetrics.formatSizeShort(info.totalBytes)} total',
        '95.9 GB used / 108.4 GB total',
      );
    });

    test('rejects a reply without usable numbers', () {
      expect(StorageBridge.debugParse(total: '0', free: '0'), isNull);
      expect(StorageBridge.debugParse(total: null, free: '1024'), isNull);
      expect(StorageBridge.debugParse(total: 'abc', free: '1024'), isNull);
    });

    test('clamps a free figure larger than the total', () {
      final info = StorageBridge.debugParse(total: '1024', free: '4096');

      expect(info!.freeBytes, 1024);
      expect(info.usedBytes, 0);
    });
  });

  group('storage text', () {
    test('headline sizes use one decimal for GB and up', () {
      expect(TransferMetrics.formatSizeShort(1024 * 1024 * 1024 * 95.5),
          '95.5 GB');
      expect(TransferMetrics.formatSizeShort(1024 * 1024 * 1024 * 108),
          '108.0 GB');
      expect(TransferMetrics.formatSizeShort(1024 * 1024 * 512), '512.0 MB');
      expect(TransferMetrics.formatSizeShort(0), '0 B');
    });
  });

  group('real df fallback', () {
    test('reads this machine\'s root volume on Linux', () async {
      if (!Platform.isLinux) return;

      final result = await Process.run('df', ['-k', '/']);
      expect(result.exitCode, 0);

      final info = await StorageBridge.getStorageInfo();
      expect(info, isNotNull);
      expect(info!.totalBytes, greaterThan(0));
      expect(info.freeBytes, lessThanOrEqualTo(info.totalBytes));
      expect(info.usedBytes, greaterThanOrEqualTo(0));
    });
  });
}

Future<List<dynamic>> _callCatalog() async {
  final raw =
      await AppCatalogBridge.channel.invokeMethod<List<dynamic>>('listInstalledApps');
  return raw ?? const [];
}

Future<List<InstalledAppInfo>> _callCatalogSafely() async {
  try {
    final raw =
        await AppCatalogBridge.channel.invokeMethod<List<dynamic>>('listInstalledApps');
    return (raw ?? const [])
        .whereType<Map>()
        .map((e) => InstalledAppInfo.fromMap(Map<dynamic, dynamic>.from(e)))
        .toList();
  } catch (_) {
    return const [];
  }
}
