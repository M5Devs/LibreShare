import 'package:archive/archive.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:mime/mime.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'file_storage_service.dart';
import 'session_manager.dart';
import 'shared_file.dart';

class EmbeddedServer {
  final int port;
  final String? htmlContentOverride;
  final FileStorageService storageService;
  final SessionManager sessionManager;
  HttpServer? _server;

  EmbeddedServer({
    this.port = 5000,
    this.htmlContentOverride,
    FileStorageService? storageService,
    SessionManager? sessionManager,
  })  : storageService = storageService ?? FileStorageService(),
        sessionManager = sessionManager ?? SessionManager();

  bool get isRunning => _server != null;
  int? get actualPort => _server?.port;

  Future<String> _getHtmlContent() async {
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
    return content;
  }

  String? _getSessionCookie(Request request) {
    final cookieHeader = request.headers['cookie'];
    if (cookieHeader == null) return null;
    final cookies = cookieHeader.split(';');
    for (var cookie in cookies) {
      final parts = cookie.trim().split('=');
      if (parts.length >= 2 && parts[0] == 'ls_session') {
        return parts.sublist(1).join('=');
      }
    }
    return null;
  }

  Future<HttpServer> start() async {
    final router = Router();

    router.get('/', (Request request) async {
      final token = request.url.queryParameters['t'];
      if (token != null && sessionManager.validateToken(token)) {
        final session = sessionManager.createSession();
        return Response.seeOther(
          '/',
          headers: {
            'set-cookie': 'ls_session=$session; Path=/; HttpOnly; SameSite=Strict',
          },
        );
      }

      final content = await _getHtmlContent();
      return Response.ok(
        content,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    });

    router.post('/api/auth/pin', (Request request) async {
      try {
        final bodyText = await request.readAsString();
        final json = jsonDecode(bodyText) as Map<String, dynamic>;
        final pin = json['pin']?.toString() ?? '';

        if (sessionManager.validatePin(pin)) {
          final session = sessionManager.createSession();
          return Response.ok(
            jsonEncode({'message': 'Authenticated'}),
            headers: {
              'content-type': 'application/json',
              'set-cookie': 'ls_session=$session; Path=/; HttpOnly; SameSite=Strict',
            },
          );
        } else {
          return Response(
            403,
            body: jsonEncode({'error': 'Invalid PIN'}),
            headers: {'content-type': 'application/json'},
          );
        }
      } catch (e) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid request body'}),
          headers: {'content-type': 'application/json'},
        );
      }
    });

    router.post('/api/auth/request-approval', (Request request) {
      final requestId = sessionManager.createApprovalRequest();
      return Response.ok(
        jsonEncode({'requestId': requestId}),
        headers: {'content-type': 'application/json'},
      );
    });

    router.get('/api/auth/poll-approval', (Request request) {
      final requestId = request.url.queryParameters['requestId'] ?? '';
      final status = sessionManager.getApprovalStatus(requestId);

      Map<String, String> headers = {'content-type': 'application/json'};

      if (status == 'approved') {
        final session = sessionManager.createSession();
        headers['set-cookie'] = 'ls_session=$session; Path=/; HttpOnly; SameSite=Strict';
      }

      return Response.ok(
        jsonEncode({'status': status}),
        headers: headers,
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

    router.get('/manifest.json', (Request request) async {
      try {
        String manifestContent = '';
        try {
          manifestContent = await rootBundle.loadString('assets/web/manifest.json');
        } catch (_) {}
        if (manifestContent.isEmpty) {
          final file = File('assets/web/manifest.json');
          if (await file.exists()) {
            manifestContent = await file.readAsString();
          }
        }
        if (manifestContent.isNotEmpty) {
          return Response.ok(
            manifestContent,
            headers: {'content-type': 'application/manifest+json; charset=utf-8'},
          );
        }
        return Response.notFound('manifest.json not found');
      } catch (e) {
        return Response.notFound('manifest.json not found');
      }
    });

    router.get('/api/text', (Request request) {
      return Response.ok(
        jsonEncode({'text': storageService.latestSharedText}),
        headers: {'content-type': 'application/json'},
      );
    });

    router.post('/api/text', (Request request) async {
      try {
        final bodyText = await request.readAsString();
        final json = jsonDecode(bodyText) as Map<String, dynamic>;
        final text = json['text']?.toString() ?? '';
        storageService.setLatestSharedText(text);
        return Response.ok(
          jsonEncode({'message': 'Text updated', 'text': text}),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid request body'}),
          headers: {'content-type': 'application/json'},
        );
      }
    });

    router.get('/api/download-all', (Request request) async {
      final sharedFiles = storageService.sharedFiles;
      final archive = Archive();

      for (final sharedFile in sharedFiles) {
        final file = File(sharedFile.filePath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          archive.addFile(ArchiveFile(sharedFile.name, bytes.length, bytes));
        }
      }

      final encoder = ZipEncoder();
      final zipBytes = encoder.encode(archive);

      return Response.ok(
        zipBytes,
        headers: {
          'content-type': 'application/zip',
          'content-disposition': 'attachment; filename="LibreShare_Files.zip"',
          'x-content-type-options': 'nosniff',
        },
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

      final asciiName = sharedFile.name.replaceAll(RegExp(r'[^\x20-\x7E]'), '_').replaceAll('"', '\\"');
      final encodedName = Uri.encodeComponent(sharedFile.name);
      final contentDisposition = 'attachment; filename="$asciiName"; filename*=UTF-8\'\'$encodedName';

      return Response.ok(
        file.openRead(),
        headers: {
          'content-type': mimeType,
          'content-length': stat.size.toString(),
          'content-disposition': contentDisposition,
          'x-content-type-options': 'nosniff',
        },
      );
    });


    router.get('/eruda.min.js', (Request request) async {
      try {
        String scriptContent = '';
        try {
          scriptContent = await rootBundle.loadString('assets/web/eruda.min.js');
        } catch (_) {}
        if (scriptContent.isEmpty) {
          final file = File('assets/web/eruda.min.js');
          if (await file.exists()) {
            scriptContent = await file.readAsString();
          }
        }
        if (scriptContent.isNotEmpty) {
          return Response.ok(
            scriptContent,
            headers: {'content-type': 'application/javascript; charset=utf-8'},
          );
        }
        return Response.notFound('eruda.min.js not found');
      } catch (e) {
        return Response.notFound('eruda.min.js not found');
      }
    });

    router.get('/api/upload/status', (Request request) async {
      final rawFilename = request.url.queryParameters['filename'] ??
          request.url.queryParameters['uploadId'] ??
          '';
      var filename = rawFilename;
      try {
        filename = Uri.decodeComponent(rawFilename);
      } catch (_) {}
      final offset = await storageService.getUploadOffset(filename: filename);
      return Response.ok(
        jsonEncode({'offset': offset}),
        headers: {'content-type': 'application/json'},
      );
    });

    router.post('/api/upload/chunk', (Request request) async {
      final rawFilename = request.headers['x-file-name'] ??
          request.url.queryParameters['filename'] ??
          '';
      var filename = rawFilename;
      try {
        filename = Uri.decodeComponent(rawFilename);
      } catch (_) {}

      final chunkOffset = int.tryParse(request.headers['x-chunk-offset'] ?? '0') ?? 0;
      final totalBytes = int.tryParse(request.headers['x-total-bytes'] ?? '0') ?? 0;

      if (filename.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing X-File-Name header or filename parameter'}),
          headers: {'content-type': 'application/json'},
        );
      }

      try {
        final result = await storageService.appendChunk(
          filename: filename,
          stream: request.read(),
          totalBytes: totalBytes,
          chunkOffset: chunkOffset,
        );
        return Response.ok(
          jsonEncode(result),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': 'Chunk upload failed: '}),
          headers: {'content-type': 'application/json'},
        );
      }
    });

    router.post('/api/upload/cancel', (Request request) async {
      final rawFilename = request.headers['x-file-name'] ??
          request.url.queryParameters['filename'] ??
          request.url.queryParameters['uploadId'] ??
          '';
      var filename = rawFilename;
      try {
        filename = Uri.decodeComponent(rawFilename);
      } catch (_) {}

      await storageService.cancelUpload(filename: filename);
      return Response.ok(
        jsonEncode({'status': 'cancelled'}),
        headers: {'content-type': 'application/json'},
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

        try {
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
              } else {
                await part.drain();
              }
            } else {
              await part.drain();
            }
          }
        } on MaxBytesExceededException catch (e) {
          return Response(
            413,
            body: jsonEncode({'error': e.message}),
            headers: {'content-type': 'application/json'},
          );
        } catch (e) {
          return Response.internalServerError(
            body: jsonEncode({'error': 'Upload failed: $e'}),
            headers: {'content-type': 'application/json'},
          );
        }

        return Response.ok(
          jsonEncode({
            'message': 'Upload successful',
            'files': savedFiles.map((f) => f.toJson()).toList(),
          }),
          headers: {'content-type': 'application/json'},
        );
      } else {
        final filenameHeader = request.headers['x-file-name'] ??
            request.url.queryParameters['filename'] ??
            'upload_${DateTime.now().millisecondsSinceEpoch}.bin';

        try {
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
        } on MaxBytesExceededException catch (e) {
          return Response(
            413,
            body: jsonEncode({'error': e.message}),
            headers: {'content-type': 'application/json'},
          );
        } catch (e) {
          return Response.internalServerError(
            body: jsonEncode({'error': 'Upload failed: $e'}),
            headers: {'content-type': 'application/json'},
          );
        }
      }
    });

    Middleware authMiddleware() {
      return (Handler innerHandler) {
        return (Request request) async {
          final path = request.url.path;

          if (path == '' || path == '/' || path == 'eruda.min.js' || path == 'manifest.json') {
            return innerHandler(request);
          }

          if (path == 'api/auth/pin' ||
              path == 'api/auth/request-approval' ||
              path == 'api/auth/poll-approval') {
            return innerHandler(request);
          }

          final sessionCookie = _getSessionCookie(request);
          if (sessionCookie != null && sessionManager.isValidSession(sessionCookie)) {
            return innerHandler(request);
          }

          if (path.startsWith('api/')) {
            return Response(
              401,
              body: jsonEncode({'error': 'Unauthorized'}),
              headers: {'content-type': 'application/json'},
            );
          }

          return Response(
            401,
            body: jsonEncode({'error': 'Unauthorized'}),
            headers: {'content-type': 'application/json'},
          );
        };
      };
    }

    Middleware sanitizedLogger() {
      return (Handler innerHandler) {
        return (Request request) async {
          final startTime = DateTime.now();
          final response = await innerHandler(request);
          final duration = DateTime.now().difference(startTime);

          var requestedUri = request.requestedUri.toString();
          requestedUri = requestedUri.replaceAll(RegExp(r'([?&]t=)[^&]+'), r'\1[REDACTED]');

          stdout.writeln('${DateTime.now().toIso8601String()}  $duration ${request.method.padRight(7)} [${response.statusCode}] $requestedUri');
          return response;
        };
      };
    }

    final handler = const Pipeline()
        .addMiddleware(sanitizedLogger())
        .addMiddleware(authMiddleware())
        .addHandler(router.call);

    try {
      _server = await io.serve(handler, InternetAddress.anyIPv4, port);
    } catch (e) {
      if (port != 0) {
        // Fallback to dynamic port allocation
        _server = await io.serve(handler, InternetAddress.anyIPv4, 0);
      } else {
        rethrow;
      }
    }
        try {
      await WakelockPlus.enable();
    } catch (_) {}

    return _server!;
  }

  Future<void> stop() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    await _server?.close(force: true);
    _server = null;
  }
}
