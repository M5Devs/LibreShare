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
      id: 'test-1',
      name: 'hello.txt',
      size: 100,
      type: 'text/plain',
      filePath: '/tmp/hello.txt',
    );

    storageService.addSharedFile(file);

    expect(storageService.sharedFiles.length, equals(1));
    expect(storageService.getFileById('test-1'), equals(file));
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
    expect(storageService.sharedFiles.length, equals(1));

    final diskFile = File(savedFile.filePath);
    expect(await diskFile.exists(), isTrue);

    final readContent = await diskFile.readAsString();
    expect(readContent, equals(content));
  });

  test('removeSharedFile removes file from list', () {
    final file = SharedFile(
      id: 'test-2',
      name: 'sample.png',
      size: 200,
      type: 'image/png',
      filePath: '/tmp/sample.png',
    );

    storageService.addSharedFile(file);
    expect(storageService.sharedFiles.length, equals(1));

    storageService.removeSharedFile('test-2');
    expect(storageService.sharedFiles.length, equals(0));
  });
}
