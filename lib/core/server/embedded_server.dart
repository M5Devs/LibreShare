import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:mime/mime.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'file_storage_service.dart';
import 'shared_file.dart';

class EmbeddedServer {
  final int port;
  final String? htmlContentOverride;
  final FileStorageService storageService;
  HttpServer? _server;

  EmbeddedServer({
    this.port = 8080,
    this.htmlContentOverride,
    FileStorageService? storageService,
  }) : storageService = storageService ?? FileStorageService();

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

    router.get('/api/files', (Request request) {
      final filesJson = storageService.sharedFiles.map((f) => f.toJson()).toList();
      return Response.ok(
        jsonEncode(filesJson),
        headers: {'content-type': 'application/json'},
      );
    });

    router.get('/api/download/<fileId>', (Request request, String fileId) async {
      final sharedFile = storageService.getFileById(fileId);
      if (sharedFile == null) {
        return Response.notFound(jsonEncode({'error': 'File not found'}));
      }

      final file = File(sharedFile.filePath);
      if (!await file.exists()) {
        return Response.notFound(jsonEncode({'error': 'File not found on disk'}));
      }

      final stat = await file.stat();
      final mimeType = sharedFile.type.isNotEmpty
          ? sharedFile.type
          : lookupMimeType(sharedFile.filePath) ?? 'application/octet-stream';

      final safeFileName = sharedFile.name.replaceAll('"', '\\"');

      return Response.ok(
        file.openRead(),
        headers: {
          'content-type': mimeType,
          'content-length': stat.size.toString(),
          'content-disposition': 'attachment; filename="$safeFileName"',
        },
      );
    });

    router.post('/api/upload', (Request request) async {
      final contentTypeHeader = request.headers['content-type'];
      if (contentTypeHeader == null) {
        return Response.badRequest(body: jsonEncode({'error': 'Missing Content-Type header'}));
      }

      final mediaType = ContentType.parse(contentTypeHeader);

      if (mediaType.primaryType == 'multipart' && mediaType.subType == 'form-data') {
        final boundary = mediaType.parameters['boundary'];
        if (boundary == null) {
          return Response.badRequest(body: jsonEncode({'error': 'Missing boundary in multipart request'}));
        }

        final transformer = MimeMultipartTransformer(boundary);
        final parts = transformer.bind(request.read());

        List<SharedFile> savedFiles = [];

        await for (final part in parts) {
          final contentDispositionHeader = part.headers['content-disposition'];
          if (contentDispositionHeader != null) {
            final headerParams = HeaderValue.parse(contentDispositionHeader).parameters;
            final filename = headerParams['filename'];
            if (filename != null && filename.isNotEmpty) {
              final partContentType = part.headers['content-type'];
              final savedFile = await storageService.saveStream(
                filename: filename,
                stream: part,
                mimeType: partContentType,
              );
              savedFiles.add(savedFile);
            }
          }
        }

        return Response.ok(
          jsonEncode({
            'message': 'Upload successful',
            'files': savedFiles.map((f) => f.toJson()).toList(),
          }),
          headers: {'content-type': 'application/json'},
        );
      } else {
        // Raw stream upload (e.g., Content-Type: application/octet-stream with filename in header/query or default)
        final filenameHeader = request.headers['x-file-name'] ??
            request.url.queryParameters['filename'] ??
            'upload_${DateTime.now().millisecondsSinceEpoch}.bin';

        final savedFile = await storageService.saveStream(
          filename: filenameHeader,
          stream: request.read(),
          mimeType: mediaType.mimeType,
        );

        return Response.ok(
          jsonEncode({
            'message': 'Upload successful',
            'files': [savedFile.toJson()],
          }),
          headers: {'content-type': 'application/json'},
        );
      }
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
