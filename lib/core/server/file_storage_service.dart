import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:mime/mime.dart';
import 'shared_file.dart';

class MaxBytesExceededException implements Exception {
  final String message;
  MaxBytesExceededException(this.message);
  @override
  String toString() => message;
}

class FileStorageService {
  final Directory? storageDirectoryOverride;
  final int maxUploadBytes;
  final List<SharedFile> _sharedFiles = [];

  FileStorageService({
    this.storageDirectoryOverride,
    this.maxUploadBytes = 4 * 1024 * 1024 * 1024, // 4 GiB default
  });

  List<SharedFile> get sharedFiles => List.unmodifiable(_sharedFiles);

  Future<Directory> getStorageDirectory() async {
    if (storageDirectoryOverride != null) {
      if (!await storageDirectoryOverride!.exists()) {
        await storageDirectoryOverride!.create(recursive: true);
      }
      return storageDirectoryOverride!;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final uploadDir = Directory('${dir.path}/libreshare_uploads');
      if (!await uploadDir.exists()) {
        await uploadDir.create(recursive: true);
      }
      return uploadDir;
    } catch (_) {
      // Fallback for test environments where path_provider channel is unmocked
      final tempDir = Directory.systemTemp.createTempSync('libreshare_docs_');
      final uploadDir = Directory('${tempDir.path}/libreshare_uploads');
      if (!await uploadDir.exists()) {
        await uploadDir.create(recursive: true);
      }
      return uploadDir;
    }
  }

  SharedFile? getFileById(String id) {
    try {
      return _sharedFiles.firstWhere((file) => file.id == id);
    } catch (_) {
      return null;
    }
  }

  void addSharedFile(SharedFile file) {
    _sharedFiles.removeWhere((f) => f.id == file.id);
    _sharedFiles.add(file);
  }

  String sanitizeFilename(String filename) {
    var name = filename.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
    name = name.replaceAll('\\', '_').replaceAll('/', '_');
    name = name.replaceAll('..', '_');
    name = name.replaceAll(RegExp(r'[?%*:|"<>]'), '_');
    if (name.trim().isEmpty) {
      name = 'file_${DateTime.now().millisecondsSinceEpoch}';
    }
    if (name.length > 200) {
      final dotIdx = name.lastIndexOf('.');
      if (dotIdx > 0 && dotIdx > name.length - 20) {
        final ext = name.substring(dotIdx);
        final base = name.substring(0, 200 - ext.length);
        name = base + ext;
      } else {
        name = name.substring(0, 200);
      }
    }
    return name;
  }

  Future<SharedFile> saveStream({
    required String filename,
    required Stream<List<int>> stream,
    String? mimeType,
    int? maxBytes,
  }) async {
    final limit = maxBytes ?? maxUploadBytes;
    final storageDir = await getStorageDirectory();
    final fileId = SharedFile.generateId();
    final safeName = sanitizeFilename(filename);
    final partFilePath = '${storageDir.path}/$fileId.part';
    final finalFilePath = '${storageDir.path}/$fileId-$safeName';

    final partFile = File(partFilePath);
    final IOSink sink = partFile.openWrite();
    int size = 0;

    try {
      final byteCountingStream = stream.map((chunk) {
        size += chunk.length;
        if (size > limit) {
          throw MaxBytesExceededException('File size exceeds limit of $limit bytes');
        }
        return chunk;
      });

      await sink.addStream(byteCountingStream);
      await sink.flush();
      await sink.close();

      final finalFile = await partFile.rename(finalFilePath);
      final detectedMime = mimeType ?? lookupMimeType(finalFile.path) ?? 'application/octet-stream';

      final sharedFile = SharedFile(
        id: fileId,
        name: safeName,
        size: size,
        type: detectedMime,
        filePath: finalFile.path,
        ownedByApp: true,
      );

      addSharedFile(sharedFile);
      return sharedFile;
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      if (await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> removeSharedFile(String id) async {
    final index = _sharedFiles.indexWhere((file) => file.id == id);
    if (index != -1) {
      final file = _sharedFiles[index];
      _sharedFiles.removeAt(index);
      if (file.ownedByApp) {
        try {
          final diskFile = File(file.filePath);
          if (await diskFile.exists()) {
            await diskFile.delete();
          }
        } catch (_) {}
      }
    }
  }

  void clear() {
    for (final file in _sharedFiles) {
      if (file.ownedByApp) {
        try {
          final diskFile = File(file.filePath);
          if (diskFile.existsSync()) {
            diskFile.deleteSync();
          }
        } catch (_) {}
      }
    }
    _sharedFiles.clear();
  }
}
