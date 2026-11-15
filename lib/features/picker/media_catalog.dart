import 'dart:io';

import '../../core/utils/transfer_metrics.dart';

/// A device media file surfaced in the picker.
class MediaItem {
  const MediaItem({
    required this.path,
    required this.name,
    required this.sizeBytes,
    this.modifiedAt,
  });

  final String path;
  final String name;
  final int sizeBytes;
  final DateTime? modifiedAt;

  String get sizeLabel => TransferMetrics.formatSize(sizeBytes);
}

/// Scans the device for photos, videos, music and documents.
///
/// The scan walks a bounded set of well-known media directories. When
/// [rootDirectories] is supplied (tests, alternate storage roots) only those
/// are scanned. Directory walking is depth-limited so a deep tree cannot
/// stall the UI isolate.
class MediaCatalog {
  MediaCatalog({List<String>? rootDirectories})
      : rootDirectories = rootDirectories ?? defaultRootDirectories();

  final List<String> rootDirectories;

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
  Future<MediaLibrary> scan() async {
    final photos = <MediaItem>[];
    final videos = <MediaItem>[];
    final music = <MediaItem>[];
    final documents = <MediaItem>[];

    for (final root in rootDirectories) {
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      await _walk(dir, 0, photos, videos, music, documents);
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

    return MediaLibrary(
      photos: photos,
      videos: videos,
      music: music,
      documents: documents,
    );
  }

  Future<void> _walk(
    Directory dir,
    int depth,
    List<MediaItem> photos,
    List<MediaItem> videos,
    List<MediaItem> music,
    List<MediaItem> documents,
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
        await _walk(entity, depth + 1, photos, videos, music, documents);
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

      if (photoExtensions.contains(ext)) {
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
  });

  final List<MediaItem> photos;
  final List<MediaItem> videos;
  final List<MediaItem> music;
  final List<MediaItem> documents;

  static const empty = MediaLibrary(
    photos: [],
    videos: [],
    music: [],
    documents: [],
  );

  int get totalCount =>
      photos.length + videos.length + music.length + documents.length;
}
