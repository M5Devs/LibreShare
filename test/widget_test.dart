import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libreshare/app_routes.dart';
import 'package:libreshare/core/platform/app_catalog_bridge.dart';
import 'package:libreshare/core/platform/storage_bridge.dart';
import 'package:libreshare/core/server/embedded_server.dart';
import 'package:libreshare/core/server/file_storage_service.dart';
import 'package:libreshare/core/server/shared_file.dart';
import 'package:libreshare/core/utils/permission_helper.dart';
import 'package:libreshare/features/common/ui_kit.dart';
import 'package:libreshare/features/files/files_screen.dart';
import 'package:libreshare/features/home/home_screen.dart';
import 'package:libreshare/features/picker/file_picker_screen.dart';
import 'package:libreshare/features/picker/media_catalog.dart';
import 'package:libreshare/features/radar/receive_screen.dart';
import 'package:libreshare/features/session/transfer_session_screen.dart';
import 'package:libreshare/state/share_controller.dart';
import 'package:libreshare/state/share_scope.dart';
import 'package:libreshare/theme/app_theme.dart';
import 'package:permission_handler/permission_handler.dart';

/// Builds a controller whose server is never actually started.
ShareController buildController({FileStorageService? storage}) {
  final resolved = storage ?? FileStorageService();
  final server = EmbeddedServer(
    htmlContentOverride: '<html></html>',
    storageService: resolved,
  );
  return ShareController(server: server, storageService: resolved);
}

/// Loaders so widget tests never touch the real filesystem.
Future<MediaLibrary> emptyLibrary() async => MediaLibrary.empty;

Future<List<InstalledAppInfo>> noApps() async => const [];

Future<List<MediaItem>> noApks() async => const [];

Future<StorageInfo?> noStorage() async => null;

Widget wrap(ShareController controller, Widget child, {bool routes = false}) {
  return ShareScope(
    controller: controller,
    child: routes
        ? MaterialApp(
            theme: AppTheme.dark(),
            initialRoute: AppRoutes.home,
            routes: AppRoutes.map(),
          )
        : MaterialApp(theme: AppTheme.dark(), home: child),
  );
}

/// Gives the test window enough height that list content is laid out.
Future<void> useTallWindow(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

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

  testWidgets('Home screen shows logo, hero actions and quick share', (tester) async {
    await useTallWindow(tester);
    final controller = buildController();
    await tester.pumpWidget(wrap(controller, const HomeScreen()));

    expect(find.text('LibreShare ⚡'), findsOneWidget);
    expect(find.widgetWithText(HeroActionButton, 'Send'), findsOneWidget);
    expect(find.widgetWithText(HeroActionButton, 'Receive'), findsOneWidget);
    expect(find.widgetWithText(HeroActionButton, 'Files'), findsOneWidget);
    expect(find.text('Quick Text / URL'), findsOneWidget);
    expect(find.text('Idle'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('Home overflow menu exposes the four actions', (tester) async {
    await useTallWindow(tester);
    final controller = buildController();
    await tester.pumpWidget(wrap(controller, const HomeScreen()));

    await tester.tap(find.byIcon(Icons.add_circle_outline_rounded));
    await tester.pumpAndSettle();

    expect(find.text('💻  Connect to PC / Tablet'), findsOneWidget);
    expect(find.text('🌐  Web & KaiOS Share'), findsOneWidget);
    expect(find.text('📡  Invite via Bluetooth'), findsOneWidget);
    expect(find.text('⚙️  Settings'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('Quick share sends text into the session feed', (tester) async {
    await useTallWindow(tester);
    final controller = buildController();
    await tester.pumpWidget(wrap(controller, const HomeScreen()));

    await tester.enterText(find.byType(TextField), 'https://example.com');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
    await tester.pump();

    final messages = controller.entries.whereType<ChatMessage>().toList();
    expect(messages.length, 1);
    expect(messages.first.text, 'https://example.com');

    controller.dispose();
  });

  testWidgets('File picker shows all five tabs and a selection bar', (tester) async {
    await useTallWindow(tester);
    final controller = buildController();
    await tester.pumpWidget(wrap(
      controller,
      FilePickerScreen(
        libraryLoader: emptyLibrary,
        appLoader: noApps,
        apkLoader: noApks,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Apps 📦'), findsOneWidget);
    expect(find.text('Photos 📸'), findsOneWidget);
    expect(find.text('Videos 🎬'), findsOneWidget);
    expect(find.text('Music 🎵'), findsOneWidget);
    expect(find.text('Files 📄'), findsOneWidget);
    expect(find.text('Select files to send'), findsOneWidget);
    expect(find.text('Next / Send'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('Apps tab renders real installed apps with icons and sizes', (tester) async {
    await useTallWindow(tester);
    final controller = buildController();
    final apps = [
      const InstalledAppInfo(
        label: 'Signal',
        packageName: 'org.thoughtcrime.securesms',
        apkPath: '/data/app/signal/base.apk',
        sizeBytes: 42 * 1024 * 1024,
      ),
      const InstalledAppInfo(
        label: 'VLC',
        packageName: 'org.videolan.vlc',
        apkPath: '/data/app/vlc/base.apk',
        sizeBytes: 31 * 1024 * 1024,
      ),
    ];

    await tester.pumpWidget(wrap(
      controller,
      FilePickerScreen(
        libraryLoader: emptyLibrary,
        appLoader: () async => apps,
        apkLoader: noApks,
      ),
    ));
    await tester.pumpAndSettle();

    // Real labels, not an empty-state placeholder.
    expect(find.text('Signal.apk'), findsOneWidget);
    expect(find.text('VLC.apk'), findsOneWidget);
    expect(find.textContaining('Installed (2)'), findsOneWidget);
    expect(find.text('No apps found'), findsNothing);

    controller.dispose();
  });

  testWidgets('Apps tab switches to real stored APKs', (tester) async {
    await useTallWindow(tester);
    final controller = buildController();
    final stored = [
      const MediaItem(
        path: '/storage/emulated/0/Download/telegram.apk',
        name: 'telegram.apk',
        sizeBytes: 5 * 1024 * 1024,
      ),
    ];

    await tester.pumpWidget(wrap(
      controller,
      FilePickerScreen(
        libraryLoader: emptyLibrary,
        appLoader: noApps,
        apkLoader: () async => stored,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Stored APKs (1)'), findsOneWidget);

    await tester.tap(find.textContaining('Stored APKs'));
    await tester.pumpAndSettle();

    expect(find.text('telegram.apk'), findsOneWidget);
    expect(find.text('No stored APKs found'), findsNothing);

    controller.dispose();
  });

  testWidgets('Receive screen renders radar, PIN and pairing details', (tester) async {
    await useTallWindow(tester);
    final controller = buildController();
    await tester.pumpWidget(wrap(controller, const ReceiveScreen(autoStart: false)));
    await tester.pump();

    expect(find.text('Receive'), findsOneWidget);
    expect(find.text('PAIRING PIN'), findsOneWidget);
    expect(find.text('PIN: ${controller.pin}'), findsOneWidget);
    expect(find.textContaining('LAN / Wi-Fi'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('Session screen renders messages and transfer cards', (tester) async {
    await useTallWindow(tester);
    final controller = buildController();
    controller.sendText('Hello from LibreShare');
    controller.shareFiles([
      SharedFile(
        id: 'f1',
        name: 'a_very_long_video_file_name_here.mp4',
        size: 68 * 1024 * 1024,
        type: 'video/mp4',
        filePath: '/tmp/a_very_long_video_file_name_here.mp4',
      ),
    ]);

    await tester.pumpWidget(wrap(controller, const TransferSessionScreen()));
    await tester.pump();

    expect(find.text('Hello from LibreShare'), findsOneWidget);
    expect(find.text('Shared'), findsOneWidget);
    expect(find.byIcon(Icons.attach_file_rounded), findsOneWidget);
    // The long name must be middle-truncated rather than overflowing.
    expect(find.textContaining('…'), findsWidgets);

    controller.dispose();
  });

  testWidgets('Files screen shows storage card and empty received state', (tester) async {
    await useTallWindow(tester);
    final controller = buildController();
    await tester.pumpWidget(wrap(
      controller,
      FilesScreen(libraryLoader: emptyLibrary, storageInfoLoader: noStorage),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Files & Storage'), findsOneWidget);
    expect(find.text('Device Storage'), findsOneWidget);
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('No files received yet'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('Files screen renders real storage numbers', (tester) async {
    await useTallWindow(tester);
    final controller = buildController();
    // 95.5 GB used of 108 GB total.
    const total = 108 * 1024 * 1024 * 1024;
    const used = 102 * 1024 * 1024 * 1024;

    await tester.pumpWidget(wrap(
      controller,
      FilesScreen(
        libraryLoader: emptyLibrary,
        storageInfoLoader: () async => const StorageInfo(
          totalBytes: total,
          freeBytes: total - used,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('used /'), findsOneWidget);
    expect(find.textContaining('total'), findsOneWidget);
    expect(find.text('Storage details unavailable'), findsNothing);

    controller.dispose();
  });

  testWidgets('Files screen counts stored APKs in the Apps tile', (tester) async {
    await useTallWindow(tester);
    final controller = buildController();
    const library = MediaLibrary(
      photos: [],
      videos: [],
      music: [],
      documents: [],
      apks: [
        MediaItem(path: '/a.apk', name: 'a.apk', sizeBytes: 10),
        MediaItem(path: '/b.apk', name: 'b.apk', sizeBytes: 10),
      ],
    );

    await tester.pumpWidget(wrap(
      controller,
      FilesScreen(
        libraryLoader: () async => library,
        storageInfoLoader: noStorage,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Apps'), findsOneWidget);
    expect(find.text('2 files'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('Files screen lists received files and deletes them', (tester) async {
    await useTallWindow(tester);
    final tempDir = Directory.systemTemp.createTempSync('libreshare_files_test_');
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    final storage = FileStorageService(storageDirectoryOverride: tempDir);
    final controller = buildController(storage: storage);

    // Real filesystem work must run outside the fake-async test zone.
    await tester.runAsync(() => storage.saveStream(
          filename: 'received_photo.jpg',
          stream: Stream.value(List<int>.filled(2048, 0x42)),
        ));

    await tester.pumpWidget(wrap(
      controller,
      FilesScreen(libraryLoader: emptyLibrary, storageInfoLoader: noStorage),
    ));
    await tester.pumpAndSettle();

    expect(find.text('received_photo.jpg'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();

    expect(find.text('received_photo.jpg'), findsNothing);

    controller.dispose();
  });

  testWidgets('Hero button navigates to the picker route', (tester) async {
    await useTallWindow(tester);
    final controller = buildController();
    await tester.pumpWidget(wrap(controller, const HomeScreen(), routes: true));

    await tester.tap(find.widgetWithText(HeroActionButton, 'Send'));
    // Advance the route transition without waiting for the picker's real
    // device scan to finish.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(FilePickerScreen), findsOneWidget);

    controller.dispose();
  });

  test('CategoryStyle maps known categories', () {
    expect(CategoryStyle.of('Videos').icon, Icons.movie_rounded);
    expect(CategoryStyle.of('Images').icon, Icons.photo_rounded);
    expect(CategoryStyle.of('Apps').icon, Icons.android_rounded);
    expect(CategoryStyle.of('Audio').icon, Icons.music_note_rounded);
    expect(CategoryStyle.of('Documents').icon, Icons.description_rounded);
  });
}
