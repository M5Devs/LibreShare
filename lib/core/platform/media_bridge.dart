import 'dart:io';

import 'package:flutter/services.dart';

/// One row returned by the native MediaStore query.
class MediaRow {
  const MediaRow({
    required this.name,
    required this.uri,
    required this.sizeBytes,
    required this.modifiedAt,
    this.filePath,
    this.mimeType,
    this.isVideo = false,
  });

  final String name;

  /// `content://` URI on Android, `file://` for scanned documents.
  final String uri;

  /// Real filesystem path when the platform could resolve one. The embedded
  /// server streams from this, because `dart:io` cannot open a `content://`
  /// URI. Null when only a content URI is available.
  final String? filePath;

  final int sizeBytes;
  final DateTime? modifiedAt;
  final String? mimeType;
  final bool isVideo;

  static MediaRow? fromMap(Map<dynamic, dynamic> map) {
    final name = map['name']?.toString();
    final uri = map['uri']?.toString();
    if (name == null || name.isEmpty || uri == null || uri.isEmpty) return null;

    final path = map['path']?.toString();
    final seconds = int.tryParse(map['modified']?.toString() ?? '');
    return MediaRow(
      name: name,
      uri: uri,
      filePath: (path == null || path.isEmpty) ? null : path,
      sizeBytes: int.tryParse(map['size']?.toString() ?? '0') ?? 0,
      modifiedAt: seconds == null || seconds <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(seconds),
      mimeType: map['mime']?.toString(),
      isVideo: map['video'] == true,
    );
  }
}

/// Raw result of a device media query, keyed by category.
class MediaPayload {
  const MediaPayload({
    this.photos = const [],
    this.videos = const [],
    this.music = const [],
    this.documents = const [],
  });

  final List<MediaRow> photos;
  final List<MediaRow> videos;
  final List<MediaRow> music;
  final List<MediaRow> documents;

  static const empty = MediaPayload();

  int get totalCount =>
      photos.length + videos.length + music.length + documents.length;

  static List<MediaRow> _rows(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => MediaRow.fromMap(Map<dynamic, dynamic>.from(e)))
        .whereType<MediaRow>()
        .toList();
  }

  static MediaPayload fromMap(Map<dynamic, dynamic> map) => MediaPayload(
        photos: _rows(map['photos']),
        videos: _rows(map['videos']),
        music: _rows(map['music']),
        documents: _rows(map['documents']),
      );
}

/// Loads a [MediaPayload], or null when the platform has no media store.
typedef MediaBridgeLoader = Future<MediaPayload?> Function();

/// Queries device media through the platform.
///
/// On Android this must go through MediaStore: scoped storage hides
/// `/storage/emulated/0` from `dart:io`, so a filesystem walk finds nothing
/// even with permission granted. Everywhere else (and when the channel is
/// missing) this returns null so callers can fall back to a directory scan.
class MediaBridge {
  MediaBridge._();

  static const MethodChannel channel =
      MethodChannel('com.m5dev.libreshare/media');

  /// Overridable so tests can exercise the channel off-device, matching the
  /// override seams already used by [PermissionHelper].
  static bool? usesPlatformStoreOverride;

  /// True when media must be read through the platform channel.
  static bool get usesPlatformStore =>
      usesPlatformStoreOverride ?? Platform.isAndroid;

  static Future<MediaPayload?> listMedia() async {
    if (!usesPlatformStore) return null;
    try {
      final raw = await channel.invokeMethod<Map>('listMedia');
      if (raw == null) return null;
      return MediaPayload.fromMap(Map<dynamic, dynamic>.from(raw));
    } catch (_) {
      return null;
    }
  }
}
