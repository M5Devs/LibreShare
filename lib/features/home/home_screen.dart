import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/network/network_helper.dart';
import '../../core/server/embedded_server.dart';
import '../../core/server/file_storage_service.dart';
import '../../core/server/shared_file.dart';

class HomeScreen extends StatefulWidget {
  final EmbeddedServer? serverOverride;
  final FileStorageService? storageServiceOverride;

  const HomeScreen({
    super.key,
    this.serverOverride,
    this.storageServiceOverride,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final FileStorageService _storageService;
  late final EmbeddedServer _server;
  bool _isServerStarting = false;
  String? _serverUrl;

  @override
  void initState() {
    super.initState();
    _storageService = widget.storageServiceOverride ?? FileStorageService();
    _server = widget.serverOverride ?? EmbeddedServer(storageService: _storageService);
  }

  @override
  void dispose() {
    if (widget.serverOverride == null && _server.isRunning) {
      _server.stop();
    }
    super.dispose();
  }

  Future<void> _toggleServer() async {
    if (_isServerStarting) return;

    if (_server.isRunning) {
      await _server.stop();
      setState(() {
        _serverUrl = null;
      });
    } else {
      setState(() {
        _isServerStarting = true;
      });

      try {
        await _server.start();
        final ip = await NetworkHelper.getLocalIpAddress() ?? '127.0.0.1';
        final port = _server.actualPort ?? 8080;
        setState(() {
          _serverUrl = 'http://$ip:$port';
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to start server: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isServerStarting = false;
          });
        }
      }
    }
  }

  Future<void> _pickFiles() async {
    try {
      final List<PlatformFile> pickedFiles = await FilePicker.pickFiles();
      if (pickedFiles.isNotEmpty) {
        setState(() {
          for (final pickedFile in pickedFiles) {
            final path = pickedFile.path;
            if (path != null && path.isNotEmpty) {
              final fileObj = File(path);
              final size = fileObj.existsSync() ? fileObj.lengthSync() : 0;
              final fileId = '${DateTime.now().millisecondsSinceEpoch}_${pickedFile.name.hashCode.abs()}';

              final sharedFile = SharedFile.fromPath(
                id: fileId,
                filePath: path,
                customName: pickedFile.name,
                customSize: size,
              );
              _storageService.addSharedFile(sharedFile);
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking files: $e')),
        );
      }
    }
  }

  void _removeFile(String fileId) {
    setState(() {
      _storageService.removeSharedFile(fileId);
    });
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final sharedFiles = _storageService.sharedFiles;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'LibreShare',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Server Status Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              color: const Color(0xFF1E1E2E),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _server.isRunning ? Colors.greenAccent : Colors.redAccent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _server.isRunning ? 'Server Active' : 'Server Stopped',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        Switch(
                          value: _server.isRunning,
                          onChanged: _isServerStarting ? null : (_) => _toggleServer(),
                          activeTrackColor: const Color(0xFF8A2BE2),
                        ),
                      ],
                    ),
                    if (_isServerStarting) ...[
                      const SizedBox(height: 16),
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ],
                    if (_server.isRunning && _serverUrl != null) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.link, color: Color(0xFF8A2BE2)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SelectableText(
                                _serverUrl!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, color: Colors.white70),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _serverUrl!));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('URL copied to clipboard')),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: QrImageView(
                          data: _serverUrl!,
                          version: QrVersions.auto,
                          size: 180.0,
                          backgroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Scan QR code on receiver device',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Share Files Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Shared Files',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _pickFiles,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Files'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8A2BE2),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (sharedFiles.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2E).withAlpha(128),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.folder_open, size: 48, color: Colors.white38),
                    SizedBox(height: 12),
                    Text(
                      'No files shared yet',
                      style: TextStyle(color: Colors.white54, fontSize: 16),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Tap "Add Files" to share files with connected devices.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: sharedFiles.length,
                itemBuilder: (context, index) {
                  final file = sharedFiles[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: const Color(0xFF2A2A3D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFF8A2BE2),
                        child: Icon(Icons.insert_drive_file, color: Colors.white),
                      ),
                      title: Text(
                        file.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${_formatFileSize(file.size)} • ${file.type}',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () => _removeFile(file.id),
                        tooltip: 'Unshare File',
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
