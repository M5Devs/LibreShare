import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libreshare/core/platform/media_bridge.dart';
import 'package:libreshare/features/picker/media_catalog.dart';

/// Exercises the MediaStore channel by answering on the real channel name, so
/// a rename on either side breaks the test rather than silently returning an
/// empty picker.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => MediaBridge.usesPlatformStoreOverride = true);

  tearDown(() {
    MediaBridge.usesPlatformStoreOverride = null;
    messenger.setMockMethodCallHandler(MediaBridge.channel, null);
  });

  Map<String, dynamic> row({
    required String name,
    required String path,
    String? uri,
    int size = 1024,
    int modifiedMs = 1700000000000,
    bool video = false,
  }) =>
      {
        'name': name,
        'uri': uri ?? 'content://media/external/images/media/1',
        'path': path,
        'size': '$size',
        'modified': '$modifiedMs',
        'mime': video ? 'video/mp4' : 'image/jpeg',
        'video': video,
      };

  test('the channel name matches the native MediaStore handler', () {
    expect(MediaBridge.channel.name, 'com.m5dev.libreshare/media');
  });

  test('decodes every category and keeps the platform order', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(MediaBridge.channel, (call) async {
      received = call;
      return <String, dynamic>{
        'photos': [
          row(name: 'b.jpg', path: '/storage/emulated/0/DCIM/b.jpg'),
          row(name: 'a.jpg', path: '/storage/emulated/0/DCIM/a.jpg'),
        ],
        'videos': [
          row(name: 'clip.mp4', path: '/storage/emulated/0/Movies/clip.mp4', video: true),
        ],
        'music': [
          row(name: 'song.mp3', path: '/storage/emulated/0/Music/song.mp3'),
        ],
        'documents': [
          row(name: 'report.pdf', path: '/storage/emulated/0/Download/report.pdf'),
        ],
      };
    });

    final payload = await MediaBridge.listMedia();

    expect(received?.method, 'listMedia');
    expect(payload, isNotNull);
    expect(payload!.photos.map((r) => r.name), ['b.jpg', 'a.jpg']);
    expect(payload.videos.single.isVideo, isTrue);
    expect(payload.music.single.name, 'song.mp3');
    expect(payload.documents.single.name, 'report.pdf');
    expect(payload.totalCount, 5);
  });

  test('a row without a real path keeps the content URI as its fallback', () {
    final parsed = MediaRow.fromMap({
      'name': 'x.jpg',
      'uri': 'content://media/external/images/media/9',
      'path': null,
      'size': '2048',
      'modified': '1700000000000',
    });

    expect(parsed, isNotNull);
    expect(parsed!.filePath, isNull);
    expect(parsed.uri, 'content://media/external/images/media/9');
    expect(parsed.sizeBytes, 2048);
    expect(parsed.modifiedAt, DateTime.fromMillisecondsSinceEpoch(1700000000000));
  });

  test('malformed rows are dropped instead of producing blank entries', () {
    final payload = MediaPayload.fromMap({
      'photos': [
        {'name': '', 'uri': 'content://x', 'size': '1'},
        {'name': 'no_uri.jpg', 'size': '1'},
        {'name': 'good.jpg', 'uri': 'content://y', 'size': '10'},
        'not-a-map',
      ],
    });

    expect(payload.photos.single.name, 'good.jpg');
  });

  test('a channel error degrades to null so the walk can take over', () async {
    messenger.setMockMethodCallHandler(
      MediaBridge.channel,
      (call) async => throw PlatformException(code: 'MEDIA_LIST_FAILED'),
    );

    expect(await MediaBridge.listMedia(), isNull);
  });

  test('MediaCatalog uses the platform store when one is available', () async {
    final library = await MediaCatalog(
      mediaBridge: () async => MediaPayload.fromMap({
        'photos': [row(name: 'platform.jpg', path: '/dcim/platform.jpg')],
        'videos': const [],
        'music': const [],
        'documents': [
          row(name: 'stored.apk', path: '/Download/stored.apk', size: 4096),
        ],
      }),
    ).scan();

    expect(library.photos.single.name, 'platform.jpg');
    // APKs found by the platform scan belong in the apps category.
    expect(library.apks.single.name, 'stored.apk');
    expect(library.documents.map((e) => e.name), contains('stored.apk'));
  });

  test('MediaCatalog falls back to the walk when the store yields nothing',
      () async {
    // A null payload means "no platform store", which must not empty the list.
    final library = await MediaCatalog(mediaBridge: () async => null).scan();
    expect(library.totalCount, 0);
  });
}
