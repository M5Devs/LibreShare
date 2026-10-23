import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libreshare/core/utils/permission_helper.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  tearDown(() {
    PermissionHelper.isAndroidOverride = null;
    PermissionHelper.androidSdkVersionOverride = null;
    PermissionHelper.checkPermissionOverride = null;
    PermissionHelper.requestPermissionOverride = null;
    PermissionHelper.checkServiceStatusOverride = null;
    PermissionHelper.openAppSettingsOverride = null;
  });

  testWidgets('requestHotspotPermissions returns true when permissions granted and GPS enabled (Android 13+)', (tester) async {
    PermissionHelper.isAndroidOverride = true;
    PermissionHelper.androidSdkVersionOverride = 33;
    PermissionHelper.checkPermissionOverride = (perm) async => PermissionStatus.granted;
    PermissionHelper.checkServiceStatusOverride = (perm) async => ServiceStatus.enabled;

    late bool result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                result = await PermissionHelper.requestHotspotPermissions(context);
              },
              child: const Text('Test'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Test'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('requestHotspotPermissions requests permissions when denied and handles granted', (tester) async {
    PermissionHelper.isAndroidOverride = true;
    PermissionHelper.androidSdkVersionOverride = 30; // Android 11
    final requested = <Permission>[];
    PermissionHelper.checkPermissionOverride = (perm) async => PermissionStatus.denied;
    PermissionHelper.requestPermissionOverride = (perm) async {
      requested.add(perm);
      return PermissionStatus.granted;
    };
    PermissionHelper.checkServiceStatusOverride = (perm) async => ServiceStatus.enabled;

    late bool result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                result = await PermissionHelper.requestHotspotPermissions(context);
              },
              child: const Text('Test'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Test'));
    await tester.pumpAndSettle();

    expect(requested, contains(Permission.location));
    expect(result, isTrue);
  });

  testWidgets('requestHotspotPermissions shows dialog and returns false when permanently denied', (tester) async {
    PermissionHelper.isAndroidOverride = true;
    PermissionHelper.androidSdkVersionOverride = 33;
    PermissionHelper.checkPermissionOverride = (perm) async => PermissionStatus.permanentlyDenied;

    bool openedSettings = false;
    PermissionHelper.openAppSettingsOverride = () async {
      openedSettings = true;
      return true;
    };

    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                result = await PermissionHelper.requestHotspotPermissions(context);
              },
              child: const Text('Test'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Test'));
    await tester.pumpAndSettle();

    expect(find.text('Permission Required'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);

    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();

    expect(openedSettings, isTrue);
    expect(result, isFalse);
  });

  testWidgets('requestHotspotPermissions prompts GPS toggle when location service disabled', (tester) async {
    PermissionHelper.isAndroidOverride = true;
    PermissionHelper.androidSdkVersionOverride = 33;
    PermissionHelper.checkPermissionOverride = (perm) async => PermissionStatus.granted;
    PermissionHelper.checkServiceStatusOverride = (perm) async => ServiceStatus.disabled;

    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                result = await PermissionHelper.requestHotspotPermissions(context);
              },
              child: const Text('Test'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Test'));
    await tester.pumpAndSettle();

    expect(find.text('Location Service Disabled'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('requestStoragePermissions returns true on Android 13+', (tester) async {
    PermissionHelper.isAndroidOverride = true;
    PermissionHelper.androidSdkVersionOverride = 33;

    late bool result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                result = await PermissionHelper.requestStoragePermissions(context);
              },
              child: const Text('Test'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Test'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('requestCameraPermissions grants permission', (tester) async {
    PermissionHelper.checkPermissionOverride = (perm) async => PermissionStatus.granted;

    late bool result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                result = await PermissionHelper.requestCameraPermissions(context);
              },
              child: const Text('Test'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Test'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });
}
