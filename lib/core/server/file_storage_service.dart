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
  final List<SharedFile> _receivedFiles = [];

  FileStorageService({
    this.storageDirectoryOverride,
    this.maxUploadBytes = 4 * 1024 * 1024 * 1024, // 4 GiB default
  });

  List<SharedFile> get sharedFiles => List.unmodifiable(_sharedFiles);
  List<SharedFile> get receivedFiles => List.unmodifiable(_receivedFiles);

  String getCategoryForFilename(String filename) {
    final dotIdx = filename.lastIndexOf('.');
    final ext = dotIdx != -1 ? filename.substring(dotIdx + 1).toLowerCase() : '';
    switch (ext) {
      case 'mp4':
      case 'mkv':
      case 'avi':
      case 'mov':
      case '3gp':
        return 'Videos';
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return 'Images';
      case 'apk':
      case 'xapk':
        return 'Apps';
      case 'mp3':
      case 'wav':
      case 'm4a':
      case 'ogg':
        return 'Audio';
      default:
        return 'Documents';
    }
  }

  Future<Directory> getStorageDirectory([String? categorySubfolder]) async {
    if (storageDirectoryOverride != null) {
      final target = categorySubfolder != null
          ? Directory('${storageDirectoryOverride!.path}/$categorySubfolder')
          : storageDirectoryOverride!;
      if (!await target.exists()) {
        await target.create(recursive: true);
      }
      return target;
    }

    Directory baseDir;
    if (Platform.isAndroid) {
      try {
        baseDir = Directory('/storage/emulated/0/Download/LibreShare');
        if (!await baseDir.exists()) {
          await baseDir.create(recursive: true);
        }
      } catch (_) {
        try {
          final docs = await getApplicationDocumentsDirectory();
          baseDir = Directory('${docs.path}/LibreShare');
        } catch (_) {
          final tempDir = Directory.systemTemp.createTempSync('libreshare_docs_');
          baseDir = Directory('${tempDir.path}/LibreShare');
        }
      }
    } else {
      try {
        final docs = await getApplicationDocumentsDirectory();
        baseDir = Directory('${docs.path}/LibreShare');
      } catch (_) {
        final tempDir = Directory.systemTemp.createTempSync('libreshare_docs_');
        baseDir = Directory('${tempDir.path}/LibreShare');
      }
    }

    final targetDir = categorySubfolder != null
        ? Directory('${baseDir.path}/$categorySubfolder')
        : baseDir;
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    return targetDir;
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

  Future<String> _resolveUniqueFilename(Directory dir, String sanitizedName) async {
    final file = File('${dir.path}/$sanitizedName');
    if (!await file.exists()) {
      return sanitizedName;
    }

    final dotIdx = sanitizedName.lastIndexOf('.');
    String nameBase;
    String extension;

    if (dotIdx > 0) {
      nameBase = sanitizedName.substring(0, dotIdx);
      extension = sanitizedName.substring(dotIdx);
    } else {
      nameBase = sanitizedName;
      extension = '';
    }

    int counter = 1;
    while (true) {
      final candidateName = '$nameBase ($counter)$extension';
      final candidateFile = File('${dir.path}/$candidateName');
      if (!await candidateFile.exists()) {
        return candidateName;
      }
      counter++;
    }
  }

  Future<SharedFile> saveStream({
    required String filename,
    required Stream<List<int>> stream,
    String? mimeType,
    int? maxBytes,
  }) async {
    final limit = maxBytes ?? maxUploadBytes;
    final safeName = sanitizeFilename(filename);
    final category = getCategoryForFilename(safeName);
    final storageDir = await getStorageDirectory(category);
    final fileId = SharedFile.generateId();
    final partFilePath = '${storageDir.path}/$fileId.part';

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

      final resolvedName = await _resolveUniqueFilename(storageDir, safeName);
      final finalFilePath = '${storageDir.path}/$resolvedName';

      final finalFile = await partFile.rename(finalFilePath);
      final detectedMime = mimeType ?? lookupMimeType(finalFile.path) ?? 'application/octet-stream';

      final sharedFile = SharedFile(
        id: fileId,
        name: resolvedName,
        size: size,
        type: detectedMime,
        filePath: finalFile.path,
        ownedByApp: true,
      );

      addSharedFile(sharedFile);
      _receivedFiles.removeWhere((f) => f.id == sharedFile.id);
      _receivedFiles.add(sharedFile);

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
      _receivedFiles.removeWhere((f) => f.id == id);
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
    _receivedFiles.clear();
  }
}
