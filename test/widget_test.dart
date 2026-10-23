import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libreshare/core/server/embedded_server.dart';
import 'package:libreshare/core/server/file_storage_service.dart';
import 'package:libreshare/core/server/shared_file.dart';
import 'package:libreshare/core/utils/permission_helper.dart';
import 'package:libreshare/features/home/home_screen.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  setUp(() {
    PermissionHelper.isAndroidOverride = false;
    PermissionHelper.androidSdkVersionOverride = 33;
    PermissionHelper.checkPermissionOverride = (perm) async => PermissionStatus.granted;
    PermissionHelper.checkServiceStatusOverride = (perm) async => ServiceStatus.enabled;
  });

  tearDown(() {
    PermissionHelper.isAndroidOverride = null;
    PermissionHelper.androidSdkVersionOverride = null;
    PermissionHelper.checkPermissionOverride = null;
    PermissionHelper.checkServiceStatusOverride = null;
  });

  testWidgets('HomeScreen displays initial state correctly', (WidgetTester tester) async {
    final storageService = FileStorageService();
    final server = EmbeddedServer(storageService: storageService);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          serverOverride: server,
          storageServiceOverride: storageService,
        ),
      ),
    );

    expect(find.text('LibreShare'), findsOneWidget);
    expect(find.text('Server Stopped'), findsOneWidget);
    expect(find.text('No files shared yet'), findsOneWidget);
    expect(find.text('No files received yet'), findsOneWidget);
  });

  testWidgets('HomeScreen lists shared files and allows removal', (WidgetTester tester) async {
    final storageService = FileStorageService();
    final server = EmbeddedServer(storageService: storageService);

    storageService.addSharedFile(
      SharedFile(
        id: 'test-1',
        name: 'sample_file.pdf',
        size: 1024,
        type: 'application/pdf',
        filePath: '/tmp/sample_file.pdf',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          serverOverride: server,
          storageServiceOverride: storageService,
        ),
      ),
    );

    expect(find.text('sample_file.pdf'), findsOneWidget);
    expect(find.text('1.0 KB • application/pdf'), findsOneWidget);

    // Tap delete icon to remove file
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();

    expect(find.text('sample_file.pdf'), findsNothing);
    expect(find.text('No files shared yet'), findsOneWidget);
  });

  testWidgets('HomeScreen toggle server updates UI and displays PIN', (WidgetTester tester) async {
    final storageService = FileStorageService();
    final server = EmbeddedServer(htmlContentOverride: '<html></html>', storageService: storageService);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          serverOverride: server,
          storageServiceOverride: storageService,
        ),
      ),
    );

    expect(find.text('Server Stopped'), findsOneWidget);

    // Toggle server switch on (second Switch in the UI, first is Hotspot Switch)
    final serverSwitch = find.byType(Switch).at(1);

    await tester.runAsync(() async {
      await tester.tap(serverSwitch);
      await Future.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(find.text('Server Active'), findsOneWidget);
    expect(find.text('PIN: ${server.sessionManager.pin}'), findsOneWidget);
    expect(find.byIcon(Icons.copy), findsOneWidget);

    // Toggle switch off
    await tester.runAsync(() async {
      await tester.tap(serverSwitch);
      await Future.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(find.text('Server Stopped'), findsOneWidget);
  });
}
