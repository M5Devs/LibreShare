import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:libreshare/core/server/embedded_server.dart';

void main() {
  late EmbeddedServer server;
  late HttpClient httpClient;

  setUp(() async {
    httpClient = HttpClient();
    server = EmbeddedServer(port: 0, htmlContentOverride: '<html><body>Test HTML</body></html>');
    await server.start();
  });

  tearDown(() async {
    await server.stop();
    httpClient.close();
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
}
