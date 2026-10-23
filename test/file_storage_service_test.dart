import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:libreshare/core/server/file_storage_service.dart';
import 'package:libreshare/core/server/shared_file.dart';

void main() {
  late FileStorageService storageService;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('file_storage_test_');
    storageService = FileStorageService(storageDirectoryOverride: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('addSharedFile and getFileById works correctly', () {
    final file = SharedFile(
      id: SharedFile.generateId(),
      name: 'hello.txt',
      size: 100,
      type: 'text/plain',
      filePath: '${tempDir.path}/hello.txt',
      ownedByApp: false,
    );

    storageService.addSharedFile(file);

    expect(storageService.sharedFiles.length, equals(1));
    expect(storageService.getFileById(file.id), equals(file));
    expect(storageService.getFileById('non-existent'), isNull);
  });

  test('saveStream writes stream data to disk and registers SharedFile', () async {
    final content = 'Hello LibreShare Stream!';
    final stream = Stream.value(utf8.encode(content));

    final savedFile = await storageService.saveStream(
      filename: 'test_stream.txt',
      stream: stream,
      mimeType: 'text/plain',
    );

    expect(savedFile.name, equals('test_stream.txt'));
    expect(savedFile.size, equals(content.length));
    expect(savedFile.ownedByApp, isTrue);
    expect(storageService.sharedFiles.length, equals(1));

    final diskFile = File(savedFile.filePath);
    expect(await diskFile.exists(), isTrue);

    final readContent = await diskFile.readAsString();
    expect(readContent, equals(content));
  });

  test('saveStream enforces maxBytes and deletes .part file on failure', () async {
    final serviceWithLimit = FileStorageService(
      storageDirectoryOverride: tempDir,
      maxUploadBytes: 10,
    );

    final stream = Stream.value(utf8.encode('This is longer than 10 bytes'));

    expect(
      () => serviceWithLimit.saveStream(
        filename: 'over_limit.txt',
        stream: stream,
      ),
      throwsA(isA<MaxBytesExceededException>()),
    );

    // Verify no .part file remains in tempDir
    final remainingFiles = tempDir.listSync();
    expect(remainingFiles, isEmpty);
  });

  test('removeSharedFile deletes physical file ONLY when ownedByApp is true', () async {
    // 1. App-owned file
    final appOwnedPath = '${tempDir.path}/app_owned.txt';
    final appOwnedFile = File(appOwnedPath);
    await appOwnedFile.writeAsString('App owned content');

    final sharedAppFile = SharedFile(
      id: SharedFile.generateId(),
      name: 'app_owned.txt',
      size: 17,
      type: 'text/plain',
      filePath: appOwnedPath,
      ownedByApp: true,
    );
    storageService.addSharedFile(sharedAppFile);

    // 2. User-picked file (not app-owned)
    final userPickedPath = '${tempDir.path}/user_picked.txt';
    final userPickedFile = File(userPickedPath);
    await userPickedFile.writeAsString('User picked content');

    final sharedUserFile = SharedFile(
      id: SharedFile.generateId(),
      name: 'user_picked.txt',
      size: 19,
      type: 'text/plain',
      filePath: userPickedPath,
      ownedByApp: false,
    );
    storageService.addSharedFile(sharedUserFile);

    // Remove user-picked file -> physical file must stay
    await storageService.removeSharedFile(sharedUserFile.id);
    expect(await userPickedFile.exists(), isTrue);

    // Remove app-owned file -> physical file must be deleted
    await storageService.removeSharedFile(sharedAppFile.id);
    expect(await appOwnedFile.exists(), isFalse);
  });

  test('sanitizeFilename removes illegal characters and limits length', () {
    final sanitized1 = storageService.sanitizeFilename('../../bad/file\x00.txt');
    expect(sanitized1, equals('____bad_file.txt'));

    final longName = '${'a' * 250}.pdf';
    final sanitized2 = storageService.sanitizeFilename(longName);
    expect(sanitized2.length, lessThanOrEqualTo(200));
    expect(sanitized2, endsWith('.pdf'));
  });

  test('saveStream handles filename collision correctly (e.g. document (1).pdf)', () async {
    final stream1 = Stream.value(utf8.encode('File 1 content'));
    final file1 = await storageService.saveStream(
      filename: 'document.pdf',
      stream: stream1,
      mimeType: 'application/pdf',
    );
    expect(file1.name, equals('document.pdf'));
    expect(file1.filePath, endsWith('/document.pdf'));

    final stream2 = Stream.value(utf8.encode('File 2 content'));
    final file2 = await storageService.saveStream(
      filename: 'document.pdf',
      stream: stream2,
      mimeType: 'application/pdf',
    );
    expect(file2.name, equals('document (1).pdf'));
    expect(file2.filePath, endsWith('/document (1).pdf'));

    final stream3 = Stream.value(utf8.encode('File 3 content'));
    final file3 = await storageService.saveStream(
      filename: 'document.pdf',
      stream: stream3,
      mimeType: 'application/pdf',
    );
    expect(file3.name, equals('document (2).pdf'));
    expect(file3.filePath, endsWith('/document (2).pdf'));
  });

  test('chunked upload status, appendChunk, progress stream, and cancellation', () async {
    final filename = 'chunk_test_video.mp4';
    expect(await storageService.getUploadOffset(filename: filename), equals(0));

    final progressEvents = <UploadProgress?>[];
    final sub = storageService.progressStream.listen((event) {
      progressEvents.add(event);
    });

    final chunk1 = utf8.encode('Chunk 1 Data. ');
    final chunk2 = utf8.encode('Chunk 2 Data.');
    final totalBytes = chunk1.length + chunk2.length;

    // First chunk
    final res1 = await storageService.appendChunk(
      filename: filename,
      stream: Stream.value(chunk1),
      totalBytes: totalBytes,
      chunkOffset: 0,
    );

    expect(res1['status'], equals('in_progress'));
    expect(res1['offset'], equals(chunk1.length));
    expect(await storageService.getUploadOffset(filename: filename), equals(chunk1.length));

    // Second chunk
    final res2 = await storageService.appendChunk(
      filename: filename,
      stream: Stream.value(chunk2),
      totalBytes: totalBytes,
      chunkOffset: chunk1.length,
    );

    expect(res2['status'], equals('completed'));
    expect(res2['file']['name'], equals(filename));
    expect(storageService.receivedFiles.length, equals(1));

    await Future.delayed(Duration.zero);
    await sub.cancel();

    expect(progressEvents.isNotEmpty, isTrue);
    expect(progressEvents.last?.isCompleted, isTrue);
  });

  test('cancelUpload deletes .part file and resets state', () async {
    final filename = 'incomplete.zip';
    final chunk = utf8.encode('Partial data');

    await storageService.appendChunk(
      filename: filename,
      stream: Stream.value(chunk),
      totalBytes: 1000,
      chunkOffset: 0,
    );

    expect(await storageService.getUploadOffset(filename: filename), equals(chunk.length));

    await storageService.cancelUpload(filename: filename);

    expect(await storageService.getUploadOffset(filename: filename), equals(0));
  });
}
