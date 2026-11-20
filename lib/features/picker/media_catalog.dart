import 'dart:io';

import '../../core/platform/media_bridge.dart';
import '../../core/utils/transfer_metrics.dart';

/// A device media file surfaced in the picker.
class MediaItem {
  const MediaItem({
    required this.path,
    required this.name,
    required this.sizeBytes,
    this.modifiedAt,
    this.contentUri,
  });

  final String path;
  final String name;
  final int sizeBytes;
  final DateTime? modifiedAt;

  /// `content://` handle used to decode a real thumbnail on Android. Null on
  /// desktop, where the picker falls back to an extension icon.
  final String? contentUri;

  String get sizeLabel => TransferMetrics.formatSize(sizeBytes);
}

/// Scans the device for photos, videos, music and documents.
///
/// The scan walks a bounded set of well-known media directories. When
/// [rootDirectories] is supplied (tests, alternate storage roots) only those
/// are scanned. Directory walking is depth-limited so a deep tree cannot
/// stall the UI isolate.
class MediaCatalog {
  MediaCatalog({List<String>? rootDirectories, MediaBridgeLoader? mediaBridge})
      : rootDirectories = rootDirectories ?? defaultRootDirectories(),
        _mediaBridge = mediaBridge ??
            (rootDirectories == null ? MediaBridge.listMedia : null);

  final List<String> rootDirectories;

  /// Platform media query. Null disables it, which is what the directory-walk
  /// tests want; on Android it is the only source that can see anything.
  final MediaBridgeLoader? _mediaBridge;

  static const int _maxDepth = 4;
  static const int _maxItemsPerCategory = 2000;

  static const Set<String> photoExtensions = {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif',
  };
  static const Set<String> videoExtensions = {
    'mp4', 'mkv', 'avi', 'mov', '3gp', 'webm', 'm4v', 'flv', 'wmv',
  };
  static const Set<String> audioExtensions = {
    'mp3', 'wav', 'm4a', 'ogg', 'flac', 'aac', 'opus', 'wma',
  };
  static const Set<String> documentExtensions = {
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf',
    'csv', 'zip', 'rar', '7z', 'tar', 'gz', 'json', 'xml',
  };
  static const Set<String> apkExtensions = {'apk'};

  static List<String> defaultRootDirectories() {
    if (Platform.isAndroid) {
      return const [
        '/storage/emulated/0/DCIM',
        '/storage/emulated/0/Pictures',
        '/storage/emulated/0/Movies',
        '/storage/emulated/0/Music',
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Documents',
      ];
    }
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return const [];
    return [
      '$home/Pictures',
      '$home/Downloads',
      '$home/Music',
      '$home/Videos',
      '$home/Documents',
    ];
  }

  static String extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  /// Scans every category in one pass over the configured roots.
  ///
  /// On Android the platform MediaStore query is authoritative: scoped storage
  /// hides the storage roots from `dart:io`, so the walk below would report
  /// zero files. The walk still runs on desktop and as a fallback when the
  /// channel is unavailable.
  Future<MediaLibrary> scan() async {
    final platform = await _loadFromPlatform();
    if (platform != null) return platform;

    final photos = <MediaItem>[];
    final videos = <MediaItem>[];
    final music = <MediaItem>[];
    final documents = <MediaItem>[];
    final apks = <MediaItem>[];

    for (final root in rootDirectories) {
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      await _walk(dir, 0, photos, videos, music, documents, apks);
    }

    int byNewest(MediaItem a, MediaItem b) {
      final at = a.modifiedAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.modifiedAt?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    }

    photos.sort(byNewest);
    videos.sort(byNewest);
    music.sort(byNewest);
    documents.sort(byNewest);
    apks.sort(byNewest);

    return MediaLibrary(
      photos: photos,
      videos: videos,
      music: music,
      documents: documents,
      apks: apks,
    );
  }

  /// Reads photos, videos, music and documents from the platform store.
  ///
  /// Returns null when the platform has no store to query (desktop) or the
  /// channel failed, so the caller can fall back to the directory walk.
  Future<MediaLibrary?> _loadFromPlatform() async {
    final loader = _mediaBridge;
    if (loader == null) return null;

    final MediaPayload? payload;
    try {
      payload = await loader();
    } catch (_) {
      return null;
    }
    if (payload == null) return null;

    MediaItem toItem(MediaRow row) => MediaItem(
          path: row.filePath ?? row.uri,
          name: row.name,
          sizeBytes: row.sizeBytes,
          modifiedAt: row.modifiedAt,
          contentUri: row.uri.startsWith('content://') ? row.uri : null,
        );

    // The platform already sorted newest-first; keep that order.
    return MediaLibrary(
      photos: payload.photos.map(toItem).toList(),
      videos: payload.videos.map(toItem).toList(),
      music: payload.music.map(toItem).toList(),
      documents: payload.documents.map(toItem).toList(),
      apks: payload.documents
          .where((r) => apkExtensions.contains(extensionOf(r.name)))
          .map(toItem)
          .toList(),
    );
  }

  /// Per-category counts for the storage screen.
  ///
  /// Prefers the native `COUNT(*)` query, which never materialises a row. When
  /// that is unavailable (desktop, or the channel failed) it falls back to
  /// counting a full scan.
  Future<MediaCounts> counts() async {
    final native = await _countFromPlatform();
    if (native != null) return native;
    final library = await scan();
    return MediaCounts(
      photos: library.photos.length,
      videos: library.videos.length,
      music: library.music.length,
      documents: library.documents.length,
    );
  }

  Future<MediaCounts?> _countFromPlatform() async {
    if (_mediaBridge == null) return null;
    try {
      return await MediaBridge.countMedia();
    } catch (_) {
      return null;
    }
  }

  /// Scans the configured roots for `.apk` files that can be re-shared.
  ///
  /// These are APKs sitting in storage (downloads, Telegram, backups), as
  /// opposed to the apps currently installed on the device.
  Future<List<MediaItem>> scanApks() async {
    // Stored APKs are documents as far as the platform store is concerned.
    final platform = await _loadFromPlatform();
    if (platform != null) return platform.apks;

    final apks = <MediaItem>[];
    for (final root in rootDirectories) {
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      await _walkApks(dir, 0, apks);
    }
    apks.sort((a, b) {
      final at = a.modifiedAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.modifiedAt?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });
    return apks;
  }

  Future<void> _walkApks(Directory dir, int depth, List<MediaItem> out) async {
    if (depth > _maxDepth || out.length >= _maxItemsPerCategory) return;

    List<FileSystemEntity> entities;
    try {
      entities = await dir.list(followLinks: false).toList();
    } catch (_) {
      return;
    }

    for (final entity in entities) {
      if (out.length >= _maxItemsPerCategory) return;
      if (entity is Directory) {
        await _walkApks(entity, depth + 1, out);
        continue;
      }
      if (entity is! File) continue;

      final name = entity.path.split(Platform.pathSeparator).last;
      if (!apkExtensions.contains(extensionOf(name))) continue;

      try {
        final stat = await entity.stat();
        out.add(MediaItem(
          path: entity.path,
          name: name,
          sizeBytes: stat.size,
          modifiedAt: stat.modified,
        ));
      } catch (_) {
        continue;
      }
    }
  }

  Future<void> _walk(
    Directory dir,
    int depth,
    List<MediaItem> photos,
    List<MediaItem> videos,
    List<MediaItem> music,
    List<MediaItem> documents,
    List<MediaItem> apks,
  ) async {
    if (depth > _maxDepth) return;

    List<FileSystemEntity> entities;
    try {
      entities = await dir.list(followLinks: false).toList();
    } catch (_) {
      return;
    }

    for (final entity in entities) {
      if (entity is Directory) {
        await _walk(entity, depth + 1, photos, videos, music, documents, apks);
        continue;
      }
      if (entity is! File) continue;

      final name = entity.path.split(Platform.pathSeparator).last;
      final ext = extensionOf(name);
      if (ext.isEmpty) continue;

      int size;
      DateTime? modified;
      try {
        final stat = await entity.stat();
        size = stat.size;
        modified = stat.modified;
      } catch (_) {
        continue;
      }

      final item = MediaItem(
        path: entity.path,
        name: name,
        sizeBytes: size,
        modifiedAt: modified,
      );

      if (apkExtensions.contains(ext)) {
        if (apks.length < _maxItemsPerCategory) apks.add(item);
      } else if (photoExtensions.contains(ext)) {
        if (photos.length < _maxItemsPerCategory) photos.add(item);
      } else if (videoExtensions.contains(ext)) {
        if (videos.length < _maxItemsPerCategory) videos.add(item);
      } else if (audioExtensions.contains(ext)) {
        if (music.length < _maxItemsPerCategory) music.add(item);
      } else if (documentExtensions.contains(ext)) {
        if (documents.length < _maxItemsPerCategory) documents.add(item);
      }
    }
  }
}

/// Result of a full device scan.
class MediaLibrary {
  const MediaLibrary({
    required this.photos,
    required this.videos,
    required this.music,
    required this.documents,
    this.apks = const [],
  });

  final List<MediaItem> photos;
  final List<MediaItem> videos;
  final List<MediaItem> music;
  final List<MediaItem> documents;

  /// `.apk` files found in storage (not installed packages).
  final List<MediaItem> apks;

  static const empty = MediaLibrary(
    photos: [],
    videos: [],
    music: [],
    documents: [],
    apks: [],
  );

  int get totalCount =>
      photos.length + videos.length + music.length + documents.length + apks.length;
}
