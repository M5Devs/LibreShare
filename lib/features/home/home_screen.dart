import 'dart:async';
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
  String? _serverBaseUrl;
  Timer? _approvalPollTimer;
  final Set<String> _promptedRequests = {};

  @override
  void initState() {
    super.initState();
    _storageService = widget.storageServiceOverride ?? FileStorageService();
    _server = widget.serverOverride ?? EmbeddedServer(storageService: _storageService);
  }

  @override
  void dispose() {
    _stopApprovalPolling();
    if (widget.serverOverride == null && _server.isRunning) {
      _server.stop();
    }
    super.dispose();
  }

  void _startApprovalPolling() {
    _approvalPollTimer?.cancel();
    _approvalPollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkPendingApprovalRequests();
    });
  }

  void _stopApprovalPolling() {
    _approvalPollTimer?.cancel();
    _approvalPollTimer = null;
  }

  void _checkPendingApprovalRequests() {
    if (!_server.isRunning) return;
    final pending = _server.sessionManager.pendingRequestIds;
    for (final requestId in pending) {
      if (!_promptedRequests.contains(requestId)) {
        _promptedRequests.add(requestId);
        _showApprovalDialog(requestId);
        break;
      }
    }
  }

  Future<void> _showApprovalDialog(String requestId) async {
    if (!mounted) return;

    final allowed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: const Text(
            'Connection Request',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'A new device wants to connect. Allow access?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Deny', style: TextStyle(color: Colors.redAccent)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8A2BE2),
                foregroundColor: Colors.white,
              ),
              child: const Text('Allow'),
            ),
          ],
        );
      },
    );

    if (allowed == true) {
      _server.sessionManager.approveRequest(requestId);
    } else {
      _server.sessionManager.rejectRequest(requestId);
    }
  }

  Future<void> _toggleServer() async {
    if (_isServerStarting) return;

    if (_server.isRunning) {
      _stopApprovalPolling();
      await _server.stop();
      setState(() {
        _serverBaseUrl = null;
      });
    } else {
      setState(() {
        _isServerStarting = true;
      });

      try {
        await _server.start();
        final ip = await NetworkHelper.getLocalIpAddress();
        final port = _server.actualPort ?? 8080;
        setState(() {
          _serverBaseUrl = 'http://$ip:$port';
        });
        _startApprovalPolling();
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

              final sharedFile = SharedFile.fromPath(
                filePath: path,
                customName: pickedFile.name,
                customSize: size,
                ownedByApp: false,
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

  String? get _fullPairingUrl {
    if (_serverBaseUrl == null) return null;
    final token = _server.sessionManager.pairingToken;
    return '$_serverBaseUrl/?t=$token';
  }

  @override
  Widget build(BuildContext context) {
    final sharedFiles = _storageService.sharedFiles;
    final pairingUrl = _fullPairingUrl;

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
                    if (_server.isRunning && pairingUrl != null) ...[
                      const SizedBox(height: 16),
                      // Prominent PIN Display
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8A2BE2).withAlpha(50),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF8A2BE2), width: 1.5),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.lock, color: Colors.white70, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'PIN: ${_server.sessionManager.pin}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
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
                                pairingUrl,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, color: Colors.white70),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: pairingUrl));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('URL copied to clipboard')),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: QrImageView(
                          data: pairingUrl,
                          version: QrVersions.auto,
                          size: 180.0,
                          backgroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Scan QR code on receiver device for instant access',
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
