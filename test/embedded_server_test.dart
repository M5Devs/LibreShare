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

  String createAuthSession() {
    return server.sessionManager.createSession();
  }

  test('GET / returns HTML content', () async {
    final port = server.actualPort!;
    final request = await httpClient.get('127.0.0.1', port, '/');
    final response = await request.close();

    expect(response.statusCode, HttpStatus.ok);
    expect(response.headers.contentType.toString(), contains('text/html'));

    final body = await response.transform(utf8.decoder).join();
    expect(body, contains('Test HTML'));
  });

  test('GET /?t=<token> redirects 303 and sets session cookie', () async {
    final port = server.actualPort!;
    final token = server.sessionManager.pairingToken;

    final request = await httpClient.get('127.0.0.1', port, '/?t=$token');
    request.followRedirects = false;
    final response = await request.close();

    expect(response.statusCode, HttpStatus.seeOther);
    expect(response.headers.value('location'), equals('/'));

    final setCookie = response.headers.value('set-cookie');
    expect(setCookie, contains('ls_session='));
  });

  test('PIN authentication sets cookie on valid PIN, 403 on wrong PIN', () async {
    final port = server.actualPort!;
    final validPin = server.sessionManager.pin;

    // Invalid PIN
    var request = await httpClient.post('127.0.0.1', port, '/api/auth/pin');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'pin': '0000'}));
    var response = await request.close();

    expect(response.statusCode, HttpStatus.forbidden);
    var body = await response.transform(utf8.decoder).join();
    expect(jsonDecode(body)['error'], equals('Invalid PIN'));

    // Valid PIN
    request = await httpClient.post('127.0.0.1', port, '/api/auth/pin');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'pin': validPin}));
    response = await request.close();

    expect(response.statusCode, HttpStatus.ok);
    final setCookie = response.headers.value('set-cookie');
    expect(setCookie, contains('ls_session='));
  });

  test('Approval flow (request -> poll pending -> approve -> poll approved)', () async {
    final port = server.actualPort!;

    // Request approval
    var request = await httpClient.post('127.0.0.1', port, '/api/auth/request-approval');
    var response = await request.close();
    expect(response.statusCode, HttpStatus.ok);
    var body = await response.transform(utf8.decoder).join();
    final jsonRes = jsonDecode(body) as Map<String, dynamic>;
    final requestId = jsonRes['requestId'] as String;

    expect(requestId, isNotEmpty);

    // Poll status (pending)
    request = await httpClient.get('127.0.0.1', port, '/api/auth/poll-approval?requestId=$requestId');
    response = await request.close();
    expect(response.statusCode, HttpStatus.ok);
    body = await response.transform(utf8.decoder).join();
    expect(jsonDecode(body)['status'], equals('pending'));

    // Host approves request
    server.sessionManager.approveRequest(requestId);

    // Poll status (approved & sets cookie)
    request = await httpClient.get('127.0.0.1', port, '/api/auth/poll-approval?requestId=$requestId');
    response = await request.close();
    expect(response.statusCode, HttpStatus.ok);
    body = await response.transform(utf8.decoder).join();
    expect(jsonDecode(body)['status'], equals('approved'));
    final setCookie = response.headers.value('set-cookie');
    expect(setCookie, contains('ls_session='));
  });

  test('Protected endpoint returns 401 when unauthenticated', () async {
    final port = server.actualPort!;
    final request = await httpClient.get('127.0.0.1', port, '/api/files');
    final response = await request.close();

    expect(response.statusCode, HttpStatus.unauthorized);
  });

  test('GET /api/files returns list of shared files when authenticated', () async {
    final port = server.actualPort!;
    final session = createAuthSession();

    var request = await httpClient.get('127.0.0.1', port, '/api/files');
    request.cookies.add(Cookie('ls_session', session));
    var response = await request.close();
    expect(response.statusCode, HttpStatus.ok);
    var body = await response.transform(utf8.decoder).join();
    var filesJson = jsonDecode(body) as List;
    expect(filesJson, isEmpty);

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
    request.cookies.add(Cookie('ls_session', session));
    response = await request.close();
    expect(response.statusCode, HttpStatus.ok);
    body = await response.transform(utf8.decoder).join();
    filesJson = jsonDecode(body) as List;
    expect(filesJson.length, equals(1));
    expect(filesJson[0]['id'], equals('file-101'));
  });

  test('Downloading file with Arabic name returns RFC 6266 / RFC 5987 header and nosniff', () async {
    final port = server.actualPort!;
    final session = createAuthSession();

    final arabicFileName = 'مذكرة_فيزياء.pdf';
    final mockFilePath = '${tempDir.path}/arabic.pdf';
    final mockFile = File(mockFilePath);
    final fileContent = 'Arabic pdf content 123';
    await mockFile.writeAsString(fileContent);

    final sharedFile = SharedFile(
      id: SharedFile.generateId(),
      name: arabicFileName,
      size: fileContent.length,
      type: 'application/pdf',
      filePath: mockFilePath,
    );
    storageService.addSharedFile(sharedFile);

    final request = await httpClient.get('127.0.0.1', port, '/api/download/${sharedFile.id}');
    request.cookies.add(Cookie('ls_session', session));
    final response = await request.close();

    expect(response.statusCode, HttpStatus.ok);
    expect(response.headers.value('x-content-type-options'), equals('nosniff'));

    final contentDisposition = response.headers.value('content-disposition')!;
    expect(contentDisposition, contains("filename*=UTF-8''"));
    expect(contentDisposition, contains(Uri.encodeComponent(arabicFileName)));

    final body = await response.transform(utf8.decoder).join();
    expect(body, equals(fileContent));
  });

  test('5 concurrent file uploads complete with unique 128-bit IDs', () async {
    final port = server.actualPort!;
    final session = createAuthSession();

    final uploadFutures = List.generate(5, (i) async {
      final client = HttpClient();
      final boundary = '----Boundary$i';
      final fileContent = 'Concurrent test content $i';

      final request = await client.post('127.0.0.1', port, '/api/upload');
      request.cookies.add(Cookie('ls_session', session));
      request.headers.set('content-type', 'multipart/form-data; boundary=$boundary');

      final payload = StringBuffer();
      payload.write('--$boundary\r\n');
      payload.write('Content-Disposition: form-data; name="file"; filename="concurrent_$i.txt"\r\n');
      payload.write('Content-Type: text/plain\r\n\r\n');
      payload.write(fileContent);
      payload.write('\r\n--$boundary--\r\n');

      request.write(payload.toString());
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      expect(response.statusCode, HttpStatus.ok);
      return jsonDecode(body) as Map<String, dynamic>;
    });

    final results = await Future.wait(uploadFutures);
    expect(results.length, equals(5));

    final files = storageService.sharedFiles;
    expect(files.length, equals(5));

    final ids = files.map((f) => f.id).toSet();
    expect(ids.length, equals(5)); // All 5 IDs are unique
    for (final id in ids) {
      expect(id.length, equals(32)); // 128-bit hex string = 32 chars
    }
  });

  test('Attempting path traversal with .. stays inside storage directory', () async {
    final port = server.actualPort!;
    final session = createAuthSession();

    final boundary = '----BoundaryPathTraversal';
    final request = await httpClient.post('127.0.0.1', port, '/api/upload');
    request.cookies.add(Cookie('ls_session', session));
    request.headers.set('content-type', 'multipart/form-data; boundary=$boundary');

    final payload = StringBuffer();
    payload.write('--$boundary\r\n');
    payload.write('Content-Disposition: form-data; name="file"; filename="../../../etc/passwd"\r\n');
    payload.write('Content-Type: text/plain\r\n\r\n');
    payload.write('dangerous content');
    payload.write('\r\n--$boundary--\r\n');

    request.write(payload.toString());
    final response = await request.close();

    expect(response.statusCode, HttpStatus.ok);
    expect(storageService.sharedFiles.length, equals(1));

    final savedFile = storageService.sharedFiles.first;
    expect(savedFile.filePath, contains(tempDir.path));
    expect(savedFile.filePath, isNot(contains('/etc/passwd')));
    expect(savedFile.name, equals('______etc_passwd'));
  });
}
