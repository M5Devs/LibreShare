import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:mime/mime.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'file_storage_service.dart';
import 'session_manager.dart';
import 'shared_file.dart';

class EmbeddedServer {
  final int port;
  final String? htmlContentOverride;
  final FileStorageService storageService;
  final SessionManager sessionManager;
  HttpServer? _server;

  String? _cachedHtmlContent;
  String? _cachedManifestContent;

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
    if (_cachedHtmlContent != null) {
      return _cachedHtmlContent!;
    }
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
    _cachedHtmlContent = content;
    return content;
  }

  Future<String> _getManifestContent() async {
    if (_cachedManifestContent != null) {
      return _cachedManifestContent!;
    }
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
    _cachedManifestContent = manifestContent;
    return manifestContent;
  }

  String _rfc5987Encode(String input) {
    return Uri.encodeComponent(input)
        .replaceAll("'", "%27")
        .replaceAll("(", "%28")
        .replaceAll(")", "%29")
        .replaceAll("*", "%2A");
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

  String _getClientIp(Request request) {
    final forwarded = request.headers['x-forwarded-for'];
    if (forwarded != null && forwarded.isNotEmpty) {
      return forwarded.split(',').first.trim();
    }
    final connectionInfo = request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    if (connectionInfo != null) {
      return connectionInfo.remoteAddress.address;
    }
    return 'Unknown IP';
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

        final pinResult = sessionManager.validatePin(pin);

        if (pinResult.isLocked) {
          return Response(
            429,
            body: jsonEncode({
              'error': 'Too many failed attempts. Locked for ${pinResult.retryAfterSeconds} seconds.',
              'retryAfter': pinResult.retryAfterSeconds,
            }),
            headers: {
              'content-type': 'application/json',
              'retry-after': pinResult.retryAfterSeconds.toString(),
            },
          );
        }

        if (pinResult.isValid) {
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

    router.post('/api/auth/request-approval', (Request request) async {
      final clientIp = _getClientIp(request);
      String deviceLabel = 'Unknown Device';

      try {
        if (request.contentLength != null && request.contentLength! > 0) {
          final bodyText = await request.readAsString();
          if (bodyText.isNotEmpty) {
            final json = jsonDecode(bodyText) as Map<String, dynamic>;
            deviceLabel = json['deviceLabel']?.toString() ??
                request.headers['user-agent'] ??
                'Unknown Device';
          }
        } else {
          deviceLabel = request.headers['user-agent'] ?? 'Unknown Device';
        }
      } catch (_) {
        deviceLabel = request.headers['user-agent'] ?? 'Unknown Device';
      }

      final requestId = sessionManager.createApprovalRequest(
        clientIp: clientIp,
        deviceLabel: deviceLabel,
      );

      if (requestId == null) {
        return Response(
          429,
          body: jsonEncode({'error': 'Too many pending approval requests. Please wait or try again later.'}),
          headers: {'content-type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode({'requestId': requestId}),
        headers: {'content-type': 'application/json'},
      );
    });

    router.get('/api/auth/poll-approval', (Request request) {
      final requestId = request.url.queryParameters['requestId'] ?? '';
      final status = sessionManager.pollApprovalStatus(requestId);

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
      final manifestContent = await _getManifestContent();
      if (manifestContent.isNotEmpty) {
        return Response.ok(
          manifestContent,
          headers: {'content-type': 'application/manifest+json; charset=utf-8'},
        );
      }
      return Response.notFound('manifest.json not found');
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
      if (sharedFiles.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'No files available to download'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final tempDir = Directory.systemTemp;
      final tempZipFile = File('${tempDir.path}/LibreShare_Files_${DateTime.now().microsecondsSinceEpoch}.zip');

      final encoder = ZipFileEncoder();
      encoder.create(tempZipFile.path, level: ZipFileEncoder.store);

      final addedNames = <String>{};

      for (final sharedFile in sharedFiles) {
        final file = File(sharedFile.filePath);
        if (await file.exists()) {
          String entryName = sharedFile.name;
          int counter = 1;

          final dotIdx = entryName.lastIndexOf('.');
          String base = dotIdx > 0 ? entryName.substring(0, dotIdx) : entryName;
          String ext = dotIdx > 0 ? entryName.substring(dotIdx) : '';

          while (addedNames.contains(entryName)) {
            entryName = '$base ($counter)$ext';
            counter++;
          }
          addedNames.add(entryName);

          await encoder.addFile(file, entryName);
        }
      }

      await encoder.close();

      final stat = await tempZipFile.stat();

      Stream<List<int>> streamWithCleanup() async* {
        try {
          yield* tempZipFile.openRead();
        } finally {
          try {
            if (await tempZipFile.exists()) {
              await tempZipFile.delete();
            }
          } catch (_) {}
        }
      }

      return Response.ok(
        streamWithCleanup(),
        headers: {
          'content-type': 'application/zip',
          'content-length': stat.size.toString(),
          'content-disposition': 'attachment; filename="LibreShare_Files.zip"',
          'x-content-type-options': 'nosniff',
        },
      );
    });

    router.get('/api/download/<id>', (Request request, String id) async {
      final sharedFile = storageService.getFileById(id);
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
      final encodedName = _rfc5987Encode(sharedFile.name);
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

    router.post('/api/upload/init', (Request request) async {
      try {
        final bodyText = await request.readAsString();
        final json = jsonDecode(bodyText) as Map<String, dynamic>;
        final filename = json['name']?.toString() ?? 'upload_${DateTime.now().millisecondsSinceEpoch}.bin';
        final totalBytes = int.tryParse(json['size']?.toString() ?? '0') ?? 0;

        final uploadId = await storageService.initUpload(
          filename: filename,
          totalBytes: totalBytes,
        );

        return Response.ok(
          jsonEncode({'uploadId': uploadId}),
          headers: {'content-type': 'application/json'},
        );
      } on MaxBytesExceededException catch (e) {
        return Response(
          400,
          body: jsonEncode({'error': e.message}),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid init upload request'}),
          headers: {'content-type': 'application/json'},
        );
      }
    });

    router.get('/api/upload/status', (Request request) async {
      final uploadIdOrFilename = request.url.queryParameters['uploadId'] ??
          request.url.queryParameters['filename'] ??
          request.headers['x-upload-id'] ??
          '';

      var target = uploadIdOrFilename;
      try {
        target = Uri.decodeComponent(uploadIdOrFilename);
      } catch (_) {}

      final offset = await storageService.getUploadOffset(uploadIdOrFilename: target);
      return Response.ok(
        jsonEncode({'offset': offset}),
        headers: {'content-type': 'application/json'},
      );
    });

    router.post('/api/upload/chunk', (Request request) async {
      final uploadId = request.headers['x-upload-id'] ??
          request.headers['x-file-name'] ??
          request.url.queryParameters['uploadId'] ??
          request.url.queryParameters['filename'] ??
          '';

      var targetId = uploadId;
      try {
        targetId = Uri.decodeComponent(uploadId);
      } catch (_) {}

      final chunkOffset = int.tryParse(request.headers['x-chunk-offset'] ?? '0') ?? 0;
      final totalBytes = int.tryParse(request.headers['x-total-bytes'] ?? '0') ?? 0;

      if (targetId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing X-Upload-Id or X-File-Name header'}),
          headers: {'content-type': 'application/json'},
        );
      }

      try {
        final result = await storageService.appendChunk(
          uploadId: targetId,
          stream: request.read(),
          totalBytes: totalBytes,
          chunkOffset: chunkOffset,
        );
        return Response.ok(
          jsonEncode(result),
          headers: {'content-type': 'application/json'},
        );
      } on OffsetMismatchException catch (e) {
        return Response(
          409,
          body: jsonEncode({'offset': e.currentOffset}),
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
          body: jsonEncode({'error': 'Internal server error'}),
          headers: {'content-type': 'application/json'},
        );
      }
    });

    router.post('/api/upload/cancel', (Request request) async {
      final uploadId = request.headers['x-upload-id'] ??
          request.headers['x-file-name'] ??
          request.url.queryParameters['uploadId'] ??
          request.url.queryParameters['filename'] ??
          '';

      var targetId = uploadId;
      try {
        targetId = Uri.decodeComponent(uploadId);
      } catch (_) {}

      await storageService.cancelUpload(uploadId: targetId);
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
            body: jsonEncode({'error': 'Internal server error'}),
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
            body: jsonEncode({'error': 'Internal server error'}),
            headers: {'content-type': 'application/json'},
          );
        }
      }
    });

    Middleware authMiddleware() {
      return (Handler innerHandler) {
        return (Request request) async {
          final path = request.url.path;

          if (path == '' || path == '/' || path == 'manifest.json') {
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
