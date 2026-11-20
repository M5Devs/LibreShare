import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libreshare/app_routes.dart';
import 'package:libreshare/core/network/peer_connector.dart';
import 'package:libreshare/core/platform/app_catalog_bridge.dart';
import 'package:libreshare/core/platform/media_bridge.dart';
import 'package:libreshare/core/platform/storage_bridge.dart';
import 'package:libreshare/core/server/embedded_server.dart';
import 'package:libreshare/core/server/file_storage_service.dart';
import 'package:libreshare/core/server/shared_file.dart';
import 'package:libreshare/core/utils/permission_helper.dart';
import 'package:libreshare/features/common/ui_kit.dart';
import 'package:libreshare/features/connect/connect_kaios_screen.dart';
import 'package:libreshare/features/connect/connect_pc_screen.dart';
import 'package:libreshare/features/files/files_screen.dart';
import 'package:libreshare/features/home/home_screen.dart';
import 'package:libreshare/features/picker/file_picker_screen.dart';
import 'package:libreshare/features/picker/media_catalog.dart';
import 'package:libreshare/features/radar/qr_scanner_sheet.dart';
import 'package:libreshare/features/radar/receive_screen.dart';
import 'package:libreshare/features/session/transfer_session_screen.dart';
import 'package:libreshare/state/share_controller.dart';
import 'package:libreshare/state/share_scope.dart';
import 'package:libreshare/theme/app_theme.dart';
import 'package:permission_handler/permission_handler.dart';

/// Builds a controller whose server is never actually started.
ShareController buildController({
  FileStorageService? storage,
  Future<bool> Function(PeerEndpoint endpoint)? peerProbe,
}) {
  final resolved = storage ?? FileStorageService();
  final server = EmbeddedServer(
    htmlContentOverride: '<html></html>',
    storageService: resolved,
  );
  return ShareController(
    server: server,
    storageService: resolved,
    peerProbe: peerProbe,
  );
}

/// Loaders so widget tests never touch the real filesystem.
Future<MediaLibrary> emptyLibrary() async => MediaLibrary.empty;

Future<List<InstalledAppInfo>> noApps() async => const [];

Future<List<MediaItem>> noApks() async => const [];

Future<StorageInfo?> noStorage() async => null;

/// Captures named-route pushes so a test can assert navigation without
/// building the destination screen (which may start real services).
class _RouteRecorder extends NavigatorObserver {
  final List<String> pushedNames = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = route.settings.name;
    if (name != null) pushedNames.add(name);
    super.didPush(route, previousRoute);
  }
}

Widget wrap(
  ShareController controller,
  Widget child, {
  bool routes = false,
  NavigatorObserver? observer,
  Map<String, WidgetBuilder>? routeOverrides,
}) {
  // `home` plus a routes table keeps [child] as the first screen while still
  // letting it push the real named routes, so a screen under test can hand off
  // to the transfer room exactly like it does in the app.
  final table = AppRoutes.map()..remove(AppRoutes.home);
  return ShareScope(
    controller: controller,
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: child,
      routes: routes ? {...table, ...?routeOverrides} : const {},
      navigatorObservers: observer == null ? const [] : [observer],
    ),
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
    PermissionHelper.requestPermissionOverride = null;
    PermissionHelper.openAppSettingsOverride = null;
  });

  testWidgets('Home screen is just the logo bar and three hero actions',
      (tester) async {
    await useTallWindow(tester);
    final controller = buildController();
    await tester.pumpWidget(wrap(controller, const HomeScreen()));

    expect(find.text('LibreShare ⚡'), findsOneWidget);
    expect(find.widgetWithText(HeroActionButton, 'Send'), findsOneWidget);
    expect(find.widgetWithText(HeroActionButton, 'Receive'), findsOneWidget);
    expect(find.widgetWithText(HeroActionButton, 'Files'), findsOneWidget);
    expect(find.text('Idle'), findsOneWidget);

    // Text/link sharing lives in the transfer room, never on the home screen.
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Quick Text / URL'), findsNothing);

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

  testWidgets('Session input bar sends text into the room feed', (tester) async {
    await useTallWindow(tester);
    final controller = buildController();
    await tester.pumpWidget(wrap(controller, const TransferSessionScreen()));

    await tester.enterText(find.byType(TextField), 'https://example.com');
    await tester.tap(find.byIcon(Icons.send_rounded));
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
    // Nothing selected is still a valid state: Next opens the room so the
    // user can receive or chat, which is the SHAREit behaviour.
    expect(find.text('Nothing selected'), findsOneWidget);
    expect(find.text('Tap Next to just open the room'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Next'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('Selection bar summarises picks and opens the review drawer',
      (tester) async {
    await useTallWindow(tester);
    final controller = buildController();
    final library = MediaLibrary(
      photos: [
        MediaItem(path: '/p/a.jpg', name: 'a.jpg', sizeBytes: 2 * 1024 * 1024),
        MediaItem(path: '/p/b.jpg', name: 'b.jpg', sizeBytes: 3 * 1024 * 1024),
      ],
      videos: const [],
      music: const [],
      documents: const [],
    );

    await tester.pumpWidget(wrap(
      controller,
      FilePickerScreen(
        libraryLoader: () async => library,
        appLoader: noApps,
        apkLoader: noApks,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Photos 📸'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('a.jpg'));
    await tester.pump();
    await tester.tap(find.text('b.jpg'));
    await tester.pump();

    expect(find.text('2 files selected'), findsOneWidget);
    expect(find.text('5.00 MB • tap to review'), findsOneWidget);

    // Tapping the bar reveals every pick with a remove action.
    await tester.tap(find.text('2 files selected'));
    await tester.pumpAndSettle();

    expect(find.text('a.jpg'), findsWidgets);
    expect(find.text('b.jpg'), findsWidgets);
    expect(find.byIcon(Icons.remove_circle_rounded), findsNWidgets(2));

    // Removing one drops it from the selection and the count follows.
    await tester.tap(find.byIcon(Icons.remove_circle_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('1 file selected'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('Send with nothing selected still opens the room', (tester) async {
    await useTallWindow(tester);
    final controller = buildController();
    final observer = _RouteRecorder();

    await tester.pumpWidget(wrap(
      controller,
      const FilePickerScreen(
        libraryLoader: emptyLibrary,
        appLoader: noApps,
        apkLoader: noApks,
      ),
      routes: true,
      observer: observer,
      // A stub stands in for the real screen: ReceiveScreen auto-starts the
      // server and leaves timers that outlive the test binding.
      routeOverrides: {AppRoutes.receive: (_) => const SizedBox.shrink()},
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Recorded rather than mounted: ReceiveScreen auto-starts the server, and
    // the resulting timers outlive the test binding's invariants check.
    expect(observer.pushedNames, contains(AppRoutes.receive));
    expect(controller.entries, isEmpty);

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
    // 95.5 GB used of 108.0 GB total, i.e. the figures the native StatFs
    // reply produces on a 128 GB device.
    const total = 108 * 1024 * 1024 * 1024;
    final used = (95.5 * 1024 * 1024 * 1024).round();

    await tester.pumpWidget(wrap(
      controller,
      FilesScreen(
        libraryLoader: emptyLibrary,
        storageInfoLoader: () async => StorageInfo(
          totalBytes: total,
          freeBytes: total - used,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('95.5 GB used / 108.0 GB total'), findsOneWidget);
    expect(find.text('12.5 GB free'), findsOneWidget);
    expect(find.text('Storage details unavailable'), findsNothing);

    controller.dispose();
  });

  testWidgets('Files screen shows the native media counts', (tester) async {
    await useTallWindow(tester);
    final controller = buildController();

    await tester.pumpWidget(wrap(
      controller,
      FilesScreen(
        libraryLoader: emptyLibrary,
        storageInfoLoader: noStorage,
        // The cheap COUNT(*) reply, without materialising a single row.
        countsLoader: () async => const MediaCounts(
          photos: 2431,
          videos: 118,
          music: 402,
          documents: 37,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('2431 files'), findsOneWidget);
    expect(find.text('118 files'), findsOneWidget);
    expect(find.text('402 files'), findsOneWidget);
    expect(find.text('37 files'), findsOneWidget);

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

  testWidgets('The linked badge shows even when this phone runs no server',
      (tester) async {
    await useTallWindow(tester);
    final controller = buildController(peerProbe: (_) async => true);
    await tester.pumpWidget(wrap(controller, const HomeScreen(), routes: true));
    await tester.pump();

    expect(controller.isRunning, isFalse);
    expect(find.text('Device linked'), findsNothing);

    await controller.connectToPeer('http://192.168.43.1:5000');
    await tester.pumpAndSettle();

    // Back on home, the strip reports the link even though no server runs.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Device linked'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('A linked device auto-opens the transfer room from home',
      (tester) async {
    await useTallWindow(tester);
    final controller = buildController(peerProbe: (_) async => true);
    await tester.pumpWidget(wrap(controller, const HomeScreen(), routes: true));
    await tester.pump();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(TransferSessionScreen), findsNothing);

    // Joining a peer is a real link event, not a mock flag.
    await controller.connectToPeer('http://192.168.43.1:5000/?t=abc');
    await tester.pumpAndSettle();

    expect(find.byType(TransferSessionScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);

    controller.dispose();
  });

  testWidgets('Auto-navigation dismisses an open sheet before opening the room',
      (tester) async {
    await useTallWindow(tester);
    final controller = buildController(peerProbe: (_) async => true);
    await tester.pumpWidget(wrap(controller, const HomeScreen(), routes: true));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add_circle_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.text('💻  Connect to PC / Tablet'), findsOneWidget);

    await controller.connectToPeer('http://192.168.43.1:5000');
    await tester.pumpAndSettle();

    expect(find.byType(TransferSessionScreen), findsOneWidget);
    expect(find.text('💻  Connect to PC / Tablet'), findsNothing);

    controller.dispose();
  });

  testWidgets('A message during the session does not remount the room',
      (tester) async {
    await useTallWindow(tester);
    final controller = buildController(peerProbe: (_) async => true);
    // Subscribes the controller to the storage streams the peer writes into.
    await controller.init();
    await tester.pumpWidget(wrap(controller, const HomeScreen(), routes: true));
    await tester.pump();

    await controller.connectToPeer('http://192.168.43.1:5000');
    await tester.pumpAndSettle();
    expect(find.byType(TransferSessionScreen), findsOneWidget);

    // Type into the room's composer, then let the peer send a message.
    final stateBefore = tester.state(find.byType(TransferSessionScreen));
    await tester.enterText(find.byType(TextField).last, 'draft');
    controller.storage.setLatestSharedText('hi from peer');
    await tester.pumpAndSettle();

    expect(find.byType(TransferSessionScreen), findsOneWidget);
    expect(
      tester.state(find.byType(TransferSessionScreen)),
      same(stateBefore),
      reason: 'the room must keep its state instead of being rebuilt',
    );
    expect(find.text('draft'), findsOneWidget);
    expect(find.text('hi from peer'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('Scanning a peer QR parses, connects and hands off to the room',
      (tester) async {
    await useTallWindow(tester);
    PeerEndpoint? probed;
    final controller = buildController(
      peerProbe: (endpoint) async {
        probed = endpoint;
        return true;
      },
    );

    await tester.pumpWidget(wrap(
      controller,
      Scaffold(
        body: QrScannerSheet(
          onPayload: controller.connectToPeer,
          previewBuilder: (context, onDetect) => Center(
            child: TextButton(
              onPressed: () => onDetect('http://192.168.43.1:5000/?t=abc123'),
              child: const Text('emit'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Scan Sender QR'), findsOneWidget);

    await tester.tap(find.text('emit'));
    await tester.pumpAndSettle();

    expect(probed?.host, '192.168.43.1');
    expect(probed?.port, 5000);
    expect(probed?.token, 'abc123');
    expect(controller.peerConnected, isTrue);
    expect(controller.connectedPeerUrl, 'http://192.168.43.1:5000');

    controller.dispose();
  });

  testWidgets('Scanning a non-LibreShare QR code is rejected, not connected',
      (tester) async {
    await useTallWindow(tester);
    var probed = false;
    final controller = buildController(
      peerProbe: (endpoint) async {
        probed = true;
        return true;
      },
    );

    await tester.pumpWidget(wrap(
      controller,
      Scaffold(
        body: QrScannerSheet(
          onPayload: controller.connectToPeer,
          previewBuilder: (context, onDetect) => Center(
            child: TextButton(
              onPressed: () => onDetect('WIFI:S:Home;T:WPA;P:secret;;'),
              child: const Text('emit'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('emit'));
    await tester.pumpAndSettle();

    expect(probed, isFalse);
    expect(controller.peerConnected, isFalse);
    expect(find.textContaining('not a LibreShare address'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('A granted camera renders the live preview and can scan',
      (tester) async {
    await useTallWindow(tester);
    PeerEndpoint? probed;
    final controller = buildController(
      peerProbe: (endpoint) async {
        probed = endpoint;
        return true;
      },
    );

    await tester.pumpWidget(wrap(
      controller,
      Scaffold(
        body: QrScannerSheet(
          onPayload: controller.connectToPeer,
          previewBuilder: (context, onDetect) => Center(
            child: TextButton(
              onPressed: () =>
                  onDetect('http://192.168.43.1:5000/?t=abc123'),
              child: const Text('emit'),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    // No permission prompt, because the override grants the camera.
    expect(find.text('Camera Permission Required'), findsNothing);
    expect(find.text('emit'), findsOneWidget);

    await tester.tap(find.text('emit'));
    await tester.pump();
    await tester.pump();

    expect(probed?.host, '192.168.43.1');
    expect(probed?.port, 5000);
    expect(probed?.token, 'abc123');
    expect(controller.connectedPeerUrl, 'http://192.168.43.1:5000');

    controller.dispose();
  });

  testWidgets('Scanner falls back to the address field without camera access',
      (tester) async {
    await useTallWindow(tester);
    PermissionHelper.checkPermissionOverride =
        (perm) async => PermissionStatus.permanentlyDenied;
    PermissionHelper.requestPermissionOverride =
        (perm) async => PermissionStatus.permanentlyDenied;
    PermissionHelper.openAppSettingsOverride = () async => true;

    final controller = buildController(peerProbe: (_) async => true);
    await tester.pumpWidget(wrap(
      controller,
      Scaffold(body: QrScannerSheet(onPayload: controller.connectToPeer)),
    ));
    // The sheet spins a progress indicator while the permission dialog is up,
    // so settle by pumping fixed frames rather than waiting for quiescence.
    await tester.pump();
    await tester.pump();

    expect(find.text('Camera Permission Required'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Camera permission is needed'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '192.168.43.1:5000');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Connect'));
    await tester.pump();
    await tester.pump();

    expect(controller.connectedPeerUrl, 'http://192.168.43.1:5000');

    controller.dispose();
  });

  testWidgets('Accepting a connection request opens the transfer room',
      (tester) async {
    await useTallWindow(tester);
    final controller = buildController(peerProbe: (_) async => true);
    await tester.pumpWidget(
      wrap(controller, const ReceiveScreen(autoStart: false), routes: true),
    );
    await tester.pump();

    final requestId = controller.server.sessionManager
        .createApprovalRequest(clientIp: '10.0.0.9', deviceLabel: 'Pixel')!;
    controller.pendingRequests
        .add(controller.server.sessionManager.getApprovalRequest(requestId)!);

    // Any public notification lets the screen surface the pending request.
    await controller.connectToPeer('http://10.0.0.9:5000');
    // The radar animates forever, so pump fixed frames instead of settling.
    await tester.pump();
    await tester.pump();

    expect(find.text('Connection Request'), findsOneWidget);
    expect(find.text('Device: Pixel'), findsOneWidget);

    await tester.tap(find.text('Allow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(TransferSessionScreen), findsOneWidget);
    expect(controller.peerConnected, isTrue);

    controller.dispose();
  });

  testWidgets('Transfer room toggles between chat and session files',
      (tester) async {
    await useTallWindow(tester);
    final controller = buildController();
    await tester.pumpWidget(wrap(controller, const TransferSessionScreen()));
    await tester.pump();

    expect(find.text('Live Chat'), findsOneWidget);
    expect(find.text('Session Files'), findsOneWidget);

    // Chat is the default view, so the composer is visible.
    expect(find.byType(TextField), findsOneWidget);

    // Nothing has moved yet, so the files tab explains itself.
    await tester.tap(find.text('Session Files'));
    await tester.pumpAndSettle();
    expect(find.text('No files in this session yet'), findsOneWidget);
    // The composer is chat-only; it must not cover the file list.
    expect(find.byType(TextField), findsNothing);

    controller.dispose();
  });

  testWidgets('Session files lists what moved in the room', (tester) async {
    await useTallWindow(tester);
    final controller = buildController();
    await tester.pumpWidget(wrap(controller, const TransferSessionScreen()));
    await tester.pump();

    controller.shareFiles([
      SharedFile(
        id: 'f1',
        name: 'holiday.jpg',
        size: 2 * 1024 * 1024,
        type: 'image/jpeg',
        filePath: '/tmp/holiday.jpg',
      ),
    ]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Session Files'));
    await tester.pumpAndSettle();

    expect(find.text('holiday.jpg'), findsOneWidget);
    expect(find.textContaining('Sent • 2.00 MB'), findsOneWidget);
    // A shared file is complete, so it offers an open action.
    expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);

    controller.dispose();
  });

  testWidgets('Connect to PC shows the address, PIN and copy actions',
      (tester) async {
    await useTallWindow(tester);
    final controller = buildController();
    controller.serverUrl = 'http://192.168.43.1:5000';

    await tester.pumpWidget(
      wrap(controller, ConnectPcScreen(controllerOverride: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connect to PC'), findsOneWidget);
    expect(find.text('http://192.168.43.1:5000/pc'), findsOneWidget);
    expect(find.text(controller.pin), findsOneWidget);
    expect(find.text('Join the same Wi-Fi'), findsOneWidget);
    expect(find.text('Enter the 6-digit PIN'), findsOneWidget);
    // Every value on this screen exists to be copied elsewhere.
    expect(find.byIcon(Icons.copy_rounded), findsNWidgets(3));

    controller.dispose();
  });

  testWidgets('The hotspot password is readable, never masked', (tester) async {
    await useTallWindow(tester);
    final controller = buildController();
    controller.serverUrl = 'http://192.168.43.1:5000';
    controller.hotspotSsid = 'LibreShare-7f3a';
    controller.hotspotPassword = 'k4m9qz2p';

    await tester.pumpWidget(
      wrap(controller, ConnectPcScreen(controllerOverride: controller)),
    );
    await tester.pumpAndSettle();

    // The whole point of this screen is retyping these values on another
    // device, so the password must be legible.
    expect(find.text('k4m9qz2p'), findsOneWidget);
    expect(find.text('LibreShare-7f3a'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('KaiOS screen shows the hotspot password in the clear',
      (tester) async {
    await useTallWindow(tester);
    final controller = buildController();
    controller.serverUrl = 'http://192.168.43.1:5000';
    controller.hotspotSsid = 'LibreShare-7f3a';
    controller.hotspotPassword = 'k4m9qz2p';

    await tester.pumpWidget(
      wrap(controller, ConnectKaiosScreen(controllerOverride: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('k4m9qz2p'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('Connect to PC explains itself before the server runs',
      (tester) async {
    await useTallWindow(tester);
    final controller = buildController();

    await tester.pumpWidget(
      wrap(controller, ConnectPcScreen(controllerOverride: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Start Receive first'), findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsNothing);

    controller.dispose();
  });

  testWidgets('KaiOS screen leads with the typed address', (tester) async {
    await useTallWindow(tester);
    final controller = buildController();
    controller.serverUrl = 'http://192.168.43.1:5000';

    await tester.pumpWidget(
      wrap(controller, ConnectKaiosScreen(controllerOverride: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('KaiOS & Feature Phones'), findsOneWidget);
    expect(find.text('http://192.168.43.1:5000'), findsOneWidget);
    expect(find.text('Works without installing anything'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('Home menu opens the dedicated connect screens, not a sheet',
      (tester) async {
    await useTallWindow(tester);
    final controller = buildController();
    final observer = _RouteRecorder();

    await tester.pumpWidget(wrap(
      controller,
      const HomeScreen(),
      routes: true,
      observer: observer,
      routeOverrides: {
        AppRoutes.connectPc: (_) => const SizedBox.shrink(),
        AppRoutes.connectKaios: (_) => const SizedBox.shrink(),
      },
    ));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add_circle_outline_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('💻  Connect to PC / Tablet'));
    await tester.pumpAndSettle();

    expect(observer.pushedNames, contains(AppRoutes.connectPc));
    // The old implementation raised a modal sheet; a full screen must not.
    expect(find.byType(BottomSheet), findsNothing);

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
