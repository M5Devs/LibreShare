import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

class EmbeddedServer {
  final int port;
  final String? htmlContentOverride;
  HttpServer? _server;

  EmbeddedServer({
    this.port = 8080,
    this.htmlContentOverride,
  });

  bool get isRunning => _server != null;
  int? get actualPort => _server?.port;

  Future<HttpServer> start() async {
    final router = Router();

    router.get('/', (Request request) async {
      String content = htmlContentOverride ?? '';
      if (content.isEmpty) {
        try {
          content = await rootBundle.loadString('assets/web/index.html');
        } catch (_) {
          final file = File('assets/web/index.html');
          if (await file.exists()) {
            content = await file.readAsString();
          }
        }
      }
      return Response.ok(
        content,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    });

    router.get('/api/ping', (Request request) {
      final payload = jsonEncode({
        'status': 'alive',
        'app': 'LibreShare',
      });
      return Response.ok(
        payload,
        headers: {'content-type': 'application/json'},
      );
    });

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(router.call);

    _server = await io.serve(handler, InternetAddress.anyIPv4, port);
    return _server!;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
