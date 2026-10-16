import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:mime/mime.dart';
import 'shared_file.dart';

class FileStorageService {
  final Directory? storageDirectoryOverride;
  final List<SharedFile> _sharedFiles = [];

  FileStorageService({this.storageDirectoryOverride});

  List<SharedFile> get sharedFiles => List.unmodifiable(_sharedFiles);

  Future<Directory> getStorageDirectory() async {
    if (storageDirectoryOverride != null) {
      if (!await storageDirectoryOverride!.exists()) {
        await storageDirectoryOverride!.create(recursive: true);
      }
      return storageDirectoryOverride!;
    }

    try {
      final dir = await getTemporaryDirectory();
      final uploadDir = Directory('${dir.path}/libreshare_uploads');
      if (!await uploadDir.exists()) {
        await uploadDir.create(recursive: true);
      }
      return uploadDir;
    } catch (_) {
      // Fallback for non-Flutter environment or test environment where path_provider channel is unmocked
      final tempDir = Directory.systemTemp.createTempSync('libreshare_test_');
      return tempDir;
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

  Future<SharedFile> saveStream({
    required String filename,
    required Stream<List<int>> stream,
    String? mimeType,
  }) async {
    final storageDir = await getStorageDirectory();
    final fileId = '${DateTime.now().millisecondsSinceEpoch}_${1000 + _sharedFiles.length}';
    final safeFileName = filename.replaceAll(RegExp(r'[/\\?%*:|"<>]'), '_');
    final filePath = '${storageDir.path}/$fileId-$safeFileName';

    final file = File(filePath);
    final IOSink sink = file.openWrite();
    int size = 0;

    await for (final chunk in stream) {
      size += chunk.length;
      sink.add(chunk);
    }
    await sink.flush();
    await sink.close();

    final detectedMime = mimeType ?? lookupMimeType(filePath) ?? 'application/octet-stream';

    final sharedFile = SharedFile(
      id: fileId,
      name: filename,
      size: size,
      type: detectedMime,
      filePath: filePath,
    );

    addSharedFile(sharedFile);
    return sharedFile;
  }

  void removeSharedFile(String id) {
    _sharedFiles.removeWhere((file) => file.id == id);
  }

  void clear() {
    _sharedFiles.clear();
  }
}
