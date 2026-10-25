import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'package:mime/mime.dart';
import '../utils/transfer_metrics.dart';
import 'shared_file.dart';

class MaxBytesExceededException implements Exception {
  final String message;
  MaxBytesExceededException(this.message);
  @override
  String toString() => message;
}

class OffsetMismatchException implements Exception {
  final int currentOffset;
  OffsetMismatchException(this.currentOffset);
}

class UploadProgress {
  final String filename;
  final String category;
  final int currentBytes;
  final int totalBytes;
  final double percent;
  final bool isCompleted;
  final double bytesPerSecond;
  final String speedString;
  final String etaString;
  final Duration elapsedDuration;

  // Session summary metrics
  final int sessionTotalFiles;
  final int sessionCompletedFiles;
  final double sessionPercent;
  final int sessionTotalBytes;
  final int sessionTransferredBytes;
  final double sessionBytesPerSecond;
  final String sessionSpeedString;
  final String sessionEtaString;

  UploadProgress({
    required this.filename,
    this.category = 'Documents',
    required this.currentBytes,
    required this.totalBytes,
    required this.percent,
    this.isCompleted = false,
    this.bytesPerSecond = 0.0,
    String? speedString,
    String? etaString,
    Duration? elapsedDuration,
    this.sessionTotalFiles = 1,
    this.sessionCompletedFiles = 0,
    this.sessionPercent = 0.0,
    this.sessionTotalBytes = 0,
    this.sessionTransferredBytes = 0,
    this.sessionBytesPerSecond = 0.0,
    String? sessionSpeedString,
    String? sessionEtaString,
  })  : speedString = speedString ?? TransferMetrics.formatSpeed(bytesPerSecond),
        etaString = etaString ??
            TransferMetrics.formatEta(
                TransferMetrics.calculateEta(totalBytes - currentBytes, bytesPerSecond)),
        elapsedDuration = elapsedDuration ?? Duration.zero,
        sessionSpeedString = sessionSpeedString ?? TransferMetrics.formatSpeed(sessionBytesPerSecond),
        sessionEtaString = sessionEtaString ??
            TransferMetrics.formatEta(TransferMetrics.calculateEta(
                sessionTotalBytes - sessionTransferredBytes, sessionBytesPerSecond));
}

class ActiveUploadSession {
  final String uploadId;
  final String originalFilename;
  final String sanitizedFilename;
  final int totalBytes;
  final String category;
  final String partFilePath;
  int currentBytes;
  DateTime lastChunkTime;
  int lastChunkBytes;
  double smoothedSpeed;
  bool isCompleted;

  ActiveUploadSession({
    required this.uploadId,
    required this.originalFilename,
    required this.sanitizedFilename,
    required this.totalBytes,
    required this.category,
    required this.partFilePath,
    this.currentBytes = 0,
    DateTime? lastChunkTime,
    this.lastChunkBytes = 0,
    this.smoothedSpeed = 0.0,
    this.isCompleted = false,
  }) : lastChunkTime = lastChunkTime ?? DateTime.now();
}

class FileStorageService {
  final Directory? storageDirectoryOverride;
  final int maxUploadBytes;
  final List<SharedFile> _sharedFiles = [];
  final List<SharedFile> _receivedFiles = [];
  final Set<String> _reservedFilenames = {};
  final Map<String, ActiveUploadSession> _activeUploads = {};
  final List<ActiveUploadSession> _completedSessionsHistory = [];
  DateTime? _sessionStartTime;

  final StreamController<UploadProgress?> _progressController =
      StreamController<UploadProgress?>.broadcast();

  String _latestSharedText = '';
  final StreamController<String> _textStreamController =
      StreamController<String>.broadcast();

  final Random _random = Random.secure();

  String get latestSharedText => _latestSharedText;
  Stream<String> get textStream => _textStreamController.stream;

  void setLatestSharedText(String text) {
    _latestSharedText = text;
    _textStreamController.add(text);
  }

  FileStorageService({
    this.storageDirectoryOverride,
    this.maxUploadBytes = 4 * 1024 * 1024 * 1024, // 4 GiB default
  }) {
    cleanOrphanedPartFiles();
  }

  List<SharedFile> get sharedFiles => List.unmodifiable(_sharedFiles);
  List<SharedFile> get receivedFiles => List.unmodifiable(_receivedFiles);
  Stream<UploadProgress?> get progressStream => _progressController.stream;

  Future<void> cleanOrphanedPartFiles() async {
    try {
      final baseDir = await getStorageDirectory();
      final parentDir = baseDir.parent.existsSync() ? baseDir.parent : baseDir;
      final now = DateTime.now();

      await for (final entity in parentDir.list(recursive: true, followLinks: false)) {
        if (entity is File && entity.path.endsWith('.part')) {
          try {
            final stat = await entity.stat();
            if (now.difference(stat.modified).inHours >= 24) {
              await entity.delete();
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  String _generate128BitHex() {
    final values = List<int>.generate(16, (_) => _random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

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

    // Truncate base by UTF-8 byte length (<= 180 bytes) while preserving original extension
    final dotIdx = name.lastIndexOf('.');
    String nameBase;
    String ext;

    if (dotIdx > 0) {
      nameBase = name.substring(0, dotIdx);
      ext = name.substring(dotIdx);
    } else {
      nameBase = name;
      ext = '';
    }

    final extBytes = utf8.encode(ext).length;
    final maxBaseBytes = max(10, 180 - extBytes);

    while (utf8.encode(nameBase).length > maxBaseBytes && nameBase.isNotEmpty) {
      nameBase = nameBase.substring(0, nameBase.length - 1);
    }

    return nameBase + ext;
  }

  Future<String> _resolveUniqueFilename(Directory dir, String sanitizedName) async {
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

    String candidateName = sanitizedName;
    int counter = 1;

    while (true) {
      final fullPath = '${dir.path}/$candidateName';
      final file = File(fullPath);

      if (!_reservedFilenames.contains(fullPath) && !file.existsSync()) {
        _reservedFilenames.add(fullPath);
        return candidateName;
      }

      candidateName = '$nameBase ($counter)$extension';
      counter++;
    }
  }

  void _releaseReservedFilename(String fullPath) {
    _reservedFilenames.remove(fullPath);
  }

  Future<String> initUpload({
    required String filename,
    required int totalBytes,
  }) async {
    if (totalBytes <= 0 || totalBytes > maxUploadBytes) {
      throw MaxBytesExceededException(
          'Invalid file size. Size must be between 1 byte and $maxUploadBytes bytes.');
    }

    final now = DateTime.now();
    if (_activeUploads.isEmpty || _sessionStartTime == null) {
      _sessionStartTime = now;
      _completedSessionsHistory.clear();
    }

    final safeName = sanitizeFilename(filename);
    final category = getCategoryForFilename(safeName);
    final storageDir = await getStorageDirectory(category);

    final uploadId = _generate128BitHex();
    final partFilePath = '${storageDir.path}/$uploadId.part';

    final session = ActiveUploadSession(
      uploadId: uploadId,
      originalFilename: filename,
      sanitizedFilename: safeName,
      totalBytes: totalBytes,
      category: category,
      partFilePath: partFilePath,
      lastChunkTime: now,
    );

    _activeUploads[uploadId] = session;

    final partFile = File(partFilePath);
    if (!await partFile.exists()) {
      await partFile.create(recursive: true);
    }

    return uploadId;
  }

  Future<int> getUploadOffset({required String uploadIdOrFilename}) async {
    ActiveUploadSession? session = _activeUploads[uploadIdOrFilename];

    if (session != null) {
      final partFile = File(session.partFilePath);
      if (await partFile.exists()) {
        return await partFile.length();
      }
      return 0;
    }

    // Fallback for legacy filename lookup
    final safeName = sanitizeFilename(uploadIdOrFilename);
    final category = getCategoryForFilename(safeName);
    final storageDir = await getStorageDirectory(category);
    final partFile = File('${storageDir.path}/$safeName.part');

    if (await partFile.exists()) {
      return await partFile.length();
    }
    return 0;
  }

  UploadProgress _buildUploadProgress({
    required ActiveUploadSession session,
    required int currentBytes,
    required bool isCompleted,
  }) {
    final now = DateTime.now();
    _sessionStartTime ??= now;

    final timeDelta = now.difference(session.lastChunkTime).inMilliseconds / 1000.0;
    if (timeDelta >= 0.2) {
      final bytesDelta = currentBytes - session.lastChunkBytes;
      if (bytesDelta >= 0) {
        final instantSpeed = bytesDelta / timeDelta;
        session.smoothedSpeed = TransferMetrics.calculateEmaSpeed(instantSpeed, session.smoothedSpeed);
      }
      session.lastChunkTime = now;
      session.lastChunkBytes = currentBytes;
    }

    session.currentBytes = currentBytes;
    session.isCompleted = isCompleted;

    final percent = session.totalBytes > 0
        ? (currentBytes / session.totalBytes * 100.0).clamp(0.0, 100.0)
        : 100.0;

    final etaSec = TransferMetrics.calculateEta(session.totalBytes - currentBytes, session.smoothedSpeed);
    final elapsed = now.difference(_sessionStartTime!);

    // Calculate session totals across all active + recent completed tasks
    final allSessions = [..._activeUploads.values, ..._completedSessionsHistory];
    final sessionTotalFiles = allSessions.isNotEmpty ? allSessions.length : 1;
    final sessionCompletedFiles = allSessions.where((s) => s.isCompleted).length;

    int sessionTotalBytes = 0;
    int sessionTransferredBytes = 0;
    double sessionAggregateSpeed = 0.0;

    for (final s in allSessions) {
      sessionTotalBytes += s.totalBytes;
      sessionTransferredBytes += s.currentBytes;
      if (!s.isCompleted) {
        sessionAggregateSpeed += s.smoothedSpeed;
      }
    }

    final sessionPercent = sessionTotalBytes > 0
        ? (sessionTransferredBytes / sessionTotalBytes * 100.0).clamp(0.0, 100.0)
        : 100.0;

    final sessionRemainingBytes = sessionTotalBytes - sessionTransferredBytes;
    final sessionEtaSec = TransferMetrics.calculateEta(sessionRemainingBytes, sessionAggregateSpeed);

    return UploadProgress(
      filename: session.sanitizedFilename,
      category: session.category,
      currentBytes: currentBytes,
      totalBytes: session.totalBytes,
      percent: percent,
      isCompleted: isCompleted,
      bytesPerSecond: session.smoothedSpeed,
      speedString: TransferMetrics.formatSpeed(session.smoothedSpeed),
      etaString: TransferMetrics.formatEta(etaSec),
      elapsedDuration: elapsed,
      sessionTotalFiles: sessionTotalFiles,
      sessionCompletedFiles: sessionCompletedFiles,
      sessionPercent: sessionPercent,
      sessionTotalBytes: sessionTotalBytes,
      sessionTransferredBytes: sessionTransferredBytes,
      sessionBytesPerSecond: sessionAggregateSpeed,
      sessionSpeedString: TransferMetrics.formatSpeed(sessionAggregateSpeed),
      sessionEtaString: TransferMetrics.formatEta(sessionEtaSec),
    );
  }

  Future<Map<String, dynamic>> appendChunk({
    required String uploadId,
    required Stream<List<int>> stream,
    required int totalBytes,
    required int chunkOffset,
  }) async {
    ActiveUploadSession? session = _activeUploads[uploadId];

    File partFile;
    String safeName;
    Directory storageDir;

    if (session != null) {
      partFile = File(session.partFilePath);
      safeName = session.sanitizedFilename;
      storageDir = await getStorageDirectory(session.category);
      totalBytes = session.totalBytes;
    } else {
      safeName = sanitizeFilename(uploadId);
      final category = getCategoryForFilename(safeName);
      storageDir = await getStorageDirectory(category);
      partFile = File('${storageDir.path}/$safeName.part');

      session = ActiveUploadSession(
        uploadId: uploadId,
        originalFilename: safeName,
        sanitizedFilename: safeName,
        totalBytes: totalBytes,
        category: category,
        partFilePath: partFile.path,
      );
      _activeUploads[uploadId] = session;
    }

    if (!await partFile.exists()) {
      await partFile.create(recursive: true);
    }

    final currentLength = await partFile.length();

    if (chunkOffset != currentLength) {
      throw OffsetMismatchException(currentLength);
    }

    final sink = partFile.openWrite(mode: FileMode.append);
    try {
      int incomingBytes = 0;
      await for (final chunk in stream) {
        incomingBytes += chunk.length;
        if (currentLength + incomingBytes > totalBytes) {
          throw MaxBytesExceededException('Uploaded data exceeds specified totalBytes');
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      rethrow;
    }

    final currentBytes = await partFile.length();

    if (currentBytes >= totalBytes) {
      final resolvedName = await _resolveUniqueFilename(storageDir, safeName);
      final finalFilePath = '${storageDir.path}/$resolvedName';

      File finalFile;
      try {
        finalFile = await partFile.rename(finalFilePath);
      } finally {
        _releaseReservedFilename(finalFilePath);
      }

      final detectedMime = lookupMimeType(finalFile.path) ?? 'application/octet-stream';

      final fileId = SharedFile.generateId();
      final sharedFile = SharedFile(
        id: fileId,
        name: resolvedName,
        size: currentBytes,
        type: detectedMime,
        filePath: finalFile.path,
        ownedByApp: true,
      );

      addSharedFile(sharedFile);
      _receivedFiles.removeWhere((f) => f.id == sharedFile.id);
      _receivedFiles.add(sharedFile);

      final progress = _buildUploadProgress(
        session: session,
        currentBytes: totalBytes,
        isCompleted: true,
      );

      _activeUploads.remove(uploadId);
      _completedSessionsHistory.add(session);

      _progressController.add(progress);

      return {
        'status': 'completed',
        'file': sharedFile.toJson(),
      };
    } else {
      final progress = _buildUploadProgress(
        session: session,
        currentBytes: currentBytes,
        isCompleted: false,
      );

      _progressController.add(progress);

      return {
        'status': 'in_progress',
        'offset': currentBytes,
      };
    }
  }

  Future<void> cancelUpload({required String uploadId}) async {
    ActiveUploadSession? session = _activeUploads.remove(uploadId);

    if (session != null) {
      final partFile = File(session.partFilePath);
      if (await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (_) {}
      }
    } else {
      final safeName = sanitizeFilename(uploadId);
      final category = getCategoryForFilename(safeName);
      final storageDir = await getStorageDirectory(category);
      final partFile = File('${storageDir.path}/$safeName.part');

      if (await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (_) {}
      }
    }
    _progressController.add(null);
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

    final session = ActiveUploadSession(
      uploadId: fileId,
      originalFilename: filename,
      sanitizedFilename: safeName,
      totalBytes: limit,
      category: category,
      partFilePath: partFilePath,
    );
    _activeUploads[fileId] = session;

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

      File finalFile;
      try {
        finalFile = await partFile.rename(finalFilePath);
      } finally {
        _releaseReservedFilename(finalFilePath);
      }

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

      final progress = _buildUploadProgress(
        session: session,
        currentBytes: size,
        isCompleted: true,
      );

      _activeUploads.remove(fileId);
      _completedSessionsHistory.add(session);

      _progressController.add(progress);

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
      _activeUploads.remove(fileId);
      _progressController.add(null);
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
    _activeUploads.clear();
    _completedSessionsHistory.clear();
    _sessionStartTime = null;
    _reservedFilenames.clear();
    _progressController.add(null);
  }
}
