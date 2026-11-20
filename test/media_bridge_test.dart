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

  test('countMedia reads the per-category counts from the channel', () async {
    messenger.setMockMethodCallHandler(MediaBridge.channel, (call) async {
      if (call.method != 'countMedia') return null;
      return <String, Object?>{'photos': 12, 'videos': 3, 'music': 7, 'documents': 5};
    });

    final counts = await MediaBridge.countMedia();

    expect(counts, isNotNull);
    expect(counts!.photos, 12);
    expect(counts.videos, 3);
    expect(counts.music, 7);
    expect(counts.documents, 5);
    expect(counts.total, 27);
  });

  test('countMedia parses string counts, which is what the channel sends',
      () async {
    messenger.setMockMethodCallHandler(MediaBridge.channel, (call) async {
      if (call.method != 'countMedia') return null;
      return <String, Object?>{'photos': '4', 'videos': '0', 'music': '9', 'documents': '1'};
    });

    final counts = await MediaBridge.countMedia();
    expect(counts!.photos, 4);
    expect(counts.music, 9);
  });

  test('countMedia returns null when the platform store is unavailable',
      () async {
    MediaBridge.usesPlatformStoreOverride = false;
    expect(await MediaBridge.countMedia(), isNull);
  });

  test('thumbnail memoises bytes so a rebuild does not re-decode', () async {
    MediaBridge.clearThumbnailCache();
    var calls = 0;
    messenger.setMockMethodCallHandler(MediaBridge.channel, (call) async {
      if (call.method != 'thumbnail') return null;
      calls++;
      return Uint8List.fromList(<int>[1, 2, 3]);
    });

    final first = await MediaBridge.thumbnail('content://media/external/images/media/9');
    final second = await MediaBridge.thumbnail('content://media/external/images/media/9');

    expect(first, isNotNull);
    expect(second, isNotNull);
    // One native decode, one cache hit.
    expect(calls, 1);
  });

  test('thumbnail passes the uri the native handler expects', () async {
    MediaBridge.clearThumbnailCache();
    String? seenUri;
    messenger.setMockMethodCallHandler(MediaBridge.channel, (call) async {
      if (call.method != 'thumbnail') return null;
      seenUri = (call.arguments as Map)['uri'] as String?;
      return Uint8List.fromList(<int>[9]);
    });

    await MediaBridge.thumbnail('content://media/external/video/media/42');
    expect(seenUri, 'content://media/external/video/media/42');
  });

  test('a thumbnail failure is null, not an exception', () async {
    MediaBridge.clearThumbnailCache();
    messenger.setMockMethodCallHandler(MediaBridge.channel, (call) async {
      throw PlatformException(code: 'DECODE_FAILED');
    });

    expect(await MediaBridge.thumbnail('content://media/external/images/media/3'), isNull);
  });

  test('MediaCatalog counts prefers the native count query', () async {
    var listed = false;
    messenger.setMockMethodCallHandler(MediaBridge.channel, (call) async {
      if (call.method == 'countMedia') {
        return <String, Object?>{'photos': 100, 'videos': 20, 'music': 5, 'documents': 8};
      }
      if (call.method == 'listMedia') {
        listed = true;
        return <String, Object?>{'photos': [], 'videos': [], 'music': [], 'documents': []};
      }
      return null;
    });

    final counts = await MediaCatalog().counts();

    expect(counts.photos, 100);
    expect(counts.documents, 8);
    // The whole point: counting never materialises the rows.
    expect(listed, isFalse);
  });

  test('a scanned media row carries its content uri for thumbnails', () async {
    final library = await MediaCatalog(
      mediaBridge: () async => MediaPayload.fromMap({
        'photos': [
          row(name: 'pic.jpg', path: '/dcim/pic.jpg', uri: 'content://media/external/images/media/77'),
        ],
        'videos': const [],
        'music': const [],
        'documents': const [],
      }),
    ).scan();

    expect(library.photos.single.contentUri, 'content://media/external/images/media/77');
  });
}
