import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:libreshare/core/server/embedded_server.dart';
import 'package:libreshare/core/server/file_storage_service.dart';
import 'package:libreshare/core/server/shared_file.dart';

void main() {
  late EmbeddedServer server;
  late FileStorageService storageService;
  late Directory tempDir;
  late HttpClient httpClient;

  setUp(() async {
    httpClient = HttpClient();
    tempDir = await Directory.systemTemp.createTemp('server_test_');
    storageService = FileStorageService(storageDirectoryOverride: tempDir);
    server = EmbeddedServer(
      port: 0,
      htmlContentOverride: '<html><body>Test HTML</body></html>',
      storageService: storageService,
    );
    await server.start();
  });

  tearDown(() async {
    await server.stop();
    httpClient.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('GET / returns HTML content', () async {
    final port = server.actualPort!;
    final request = await httpClient.get('127.0.0.1', port, '/');
    final response = await request.close();

    expect(response.statusCode, HttpStatus.ok);
    expect(response.headers.contentType.toString(), contains('text/html'));

    final body = await response.transform(utf8.decoder).join();
    expect(body, contains('Test HTML'));
  });

  test('GET /api/ping returns JSON status', () async {
    final port = server.actualPort!;
    final request = await httpClient.get('127.0.0.1', port, '/api/ping');
    final response = await request.close();

    expect(response.statusCode, HttpStatus.ok);
    expect(response.headers.contentType.toString(), contains('application/json'));

    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;

    expect(json['status'], equals('alive'));
    expect(json['app'], equals('LibreShare'));
  });

  test('GET /api/files returns list of shared files', () async {
    final port = server.actualPort!;

    // Initial empty list
    var request = await httpClient.get('127.0.0.1', port, '/api/files');
    var response = await request.close();
    expect(response.statusCode, HttpStatus.ok);
    var body = await response.transform(utf8.decoder).join();
    var filesJson = jsonDecode(body) as List;
    expect(filesJson, isEmpty);

    // Add a file
    final mockFilePath = '${tempDir.path}/mock.txt';
    final mockFile = File(mockFilePath);
    await mockFile.writeAsString('Mock content');

    storageService.addSharedFile(
      SharedFile(
        id: 'file-101',
        name: 'mock.txt',
        size: 12,
        type: 'text/plain',
        filePath: mockFilePath,
      ),
    );

    request = await httpClient.get('127.0.0.1', port, '/api/files');
    response = await request.close();
    expect(response.statusCode, HttpStatus.ok);
    body = await response.transform(utf8.decoder).join();
    filesJson = jsonDecode(body) as List;
    expect(filesJson.length, equals(1));
    expect(filesJson[0]['id'], equals('file-101'));
    expect(filesJson[0]['name'], equals('mock.txt'));
  });

  test('GET /api/download/<fileId> streams file', () async {
    final port = server.actualPort!;
    final mockFilePath = '${tempDir.path}/download_test.txt';
    final mockFile = File(mockFilePath);
    final fileContent = 'Streaming content test 123';
    await mockFile.writeAsString(fileContent);

    storageService.addSharedFile(
      SharedFile(
        id: 'file-202',
        name: 'download_test.txt',
        size: fileContent.length,
        type: 'text/plain',
        filePath: mockFilePath,
      ),
    );

    final request = await httpClient.get('127.0.0.1', port, '/api/download/file-202');
    final response = await request.close();

    expect(response.statusCode, HttpStatus.ok);
    expect(response.headers.value('content-type'), contains('text/plain'));
    expect(response.headers.value('content-disposition'), contains('download_test.txt'));

    final body = await response.transform(utf8.decoder).join();
    expect(body, equals(fileContent));
  });

  test('POST /api/upload accepts multipart form upload', () async {
    final port = server.actualPort!;
    final boundary = '----WebKitFormBoundary7MA4YWxkTrZu0gW';
    final fileContent = 'Multipart test file content';

    final request = await httpClient.post('127.0.0.1', port, '/api/upload');
    request.headers.set('content-type', 'multipart/form-data; boundary=$boundary');

    final payload = StringBuffer();
    payload.write('--$boundary\r\n');
    payload.write('Content-Disposition: form-data; name="file"; filename="upload_test.txt"\r\n');
    payload.write('Content-Type: text/plain\r\n\r\n');
    payload.write(fileContent);
    payload.write('\r\n--$boundary--\r\n');

    request.write(payload.toString());
    final response = await request.close();

    expect(response.statusCode, HttpStatus.ok);
    final body = await response.transform(utf8.decoder).join();
    final jsonResponse = jsonDecode(body) as Map<String, dynamic>;

    expect(jsonResponse['message'], equals('Upload successful'));
    expect(jsonResponse['files'], isNotEmpty);
    expect(jsonResponse['files'][0]['name'], equals('upload_test.txt'));

    expect(storageService.sharedFiles.length, equals(1));
    expect(storageService.sharedFiles.first.name, equals('upload_test.txt'));
  });

  test('POST /api/upload accepts raw binary upload', () async {
    final port = server.actualPort!;
    final fileContent = 'Raw binary upload content';

    final request = await httpClient.post('127.0.0.1', port, '/api/upload');
    request.headers.set('content-type', 'application/octet-stream');
    request.headers.set('x-file-name', 'raw_upload.bin');

    request.write(fileContent);
    final response = await request.close();

    expect(response.statusCode, HttpStatus.ok);
    final body = await response.transform(utf8.decoder).join();
    final jsonResponse = jsonDecode(body) as Map<String, dynamic>;

    expect(jsonResponse['message'], equals('Upload successful'));
    expect(jsonResponse['files'][0]['name'], equals('raw_upload.bin'));

    expect(storageService.sharedFiles.length, equals(1));
    expect(storageService.sharedFiles.first.name, equals('raw_upload.bin'));
  });
}
