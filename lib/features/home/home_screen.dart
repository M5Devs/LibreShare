import '../../core/utils/permission_helper.dart';
import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/network/hotspot_manager.dart';
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
  bool _isHotspotActive = false;
  String? _hotspotSsid;
  String? _hotspotPassword;
  String? _serverBaseUrl;
  Timer? _approvalPollTimer;
  Timer? _uiRefreshTimer;
  StreamSubscription<UploadProgress?>? _progressSubscription;
  UploadProgress? _activeProgress;
  final Set<String> _promptedRequests = {};
  final TextEditingController _textController = TextEditingController();
  StreamSubscription<String>? _textSubscription;
  String _receivedText = '';

  @override
  void initState() {
    super.initState();
    _storageService = widget.storageServiceOverride ?? FileStorageService();
    _server = widget.serverOverride ?? EmbeddedServer(storageService: _storageService);

    _uiRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });


    _textSubscription = _storageService.textStream.listen((text) {
      if (mounted) {
        setState(() {
          _receivedText = text;
        });
      }
    });
    _receivedText = _storageService.latestSharedText;

    _progressSubscription = _storageService.progressStream.listen((progress) {
      if (mounted) {
        setState(() {
          _activeProgress = progress;
        });
      }
    });
  }

  @override
  void dispose() {

    _textSubscription?.cancel();
    _textController.dispose();

    _progressSubscription?.cancel();
    _uiRefreshTimer?.cancel();
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

  Future<void> _toggleHotspotMode(bool enable) async {
    if (_isServerStarting) return;

    if (enable) {
      final granted = await PermissionHelper.requestHotspotPermissions(context);
      if (!granted) {
        return;
      }
    }

    setState(() {
      _isServerStarting = true;
    });

    try {
      if (enable) {
        final hotspotInfo = await HotspotManager.startHotspot();
        if (hotspotInfo != null) {
          _hotspotSsid = hotspotInfo['ssid'];
          _hotspotPassword = hotspotInfo['password'];
          _isHotspotActive = true;
        }

        if (!_server.isRunning) {
          await _server.start();
        }
        final ip = hotspotInfo?['ip'] ?? await NetworkHelper.getLocalIpAddress();
        final port = _server.actualPort ?? NetworkHelper.defaultPort;
        setState(() {
          _serverBaseUrl = NetworkHelper.formatServerUrl(ip, port);
        });
        _startApprovalPolling();
      } else {
        await HotspotManager.stopHotspot();
        _stopApprovalPolling();
        if (_server.isRunning) {
          await _server.stop();
        }
        setState(() {
          _isHotspotActive = false;
          _hotspotSsid = null;
          _hotspotPassword = null;
          _serverBaseUrl = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hotspot action failed: $e')),
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

  Future<void> _toggleServer() async {
    if (_isServerStarting) return;

    if (_server.isRunning) {
      _stopApprovalPolling();
      await _server.stop();
      if (_isHotspotActive) {
        await HotspotManager.stopHotspot();
      }
      setState(() {
        _serverBaseUrl = null;
        _isHotspotActive = false;
        _hotspotSsid = null;
        _hotspotPassword = null;
      });
    } else {
      setState(() {
        _isServerStarting = true;
      });

      try {
        await _server.start();
        final ip = await NetworkHelper.getLocalIpAddress();
        final port = _server.actualPort ?? NetworkHelper.defaultPort;
        setState(() {
          _serverBaseUrl = NetworkHelper.formatServerUrl(ip, port);
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
    final granted = await PermissionHelper.requestStoragePermissions(context);
    if (!granted) return;

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

  Widget _getCategoryIcon(String category) {
    switch (category) {
      case 'Videos':
        return const Icon(Icons.video_library, color: Colors.purpleAccent);
      case 'Images':
        return const Icon(Icons.image, color: Colors.blueAccent);
      case 'Apps':
        return const Icon(Icons.android, color: Colors.greenAccent);
      case 'Audio':
        return const Icon(Icons.audiotrack, color: Colors.orangeAccent);
      default:
        return const Icon(Icons.insert_drive_file, color: Colors.amberAccent);
    }
  }

  String _getDisplayFolderPath(String filePath) {
    final idx = filePath.indexOf('Download/LibreShare/');
    if (idx != -1) {
      return filePath.substring(idx);
    }
    final libreIdx = filePath.indexOf('LibreShare/');
    if (libreIdx != -1) {
      return 'Download/${filePath.substring(libreIdx)}';
    }
    return filePath;
  }

  @override
  Widget build(BuildContext context) {
    final sharedFiles = _storageService.sharedFiles;
    final receivedFiles = _storageService.receivedFiles;
    final pairingUrl = _fullPairingUrl;

    final activeModeText = _isHotspotActive ? 'Offline Hotspot Mode' : 'LAN / Wi-Fi Mode';

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
            // Mode Indicator Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A3D),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  Icon(
                    _isHotspotActive ? Icons.wifi_tethering : Icons.wifi,
                    color: const Color(0xFF8A2BE2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Active Mode: $activeModeText',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isHotspotActive
                              ? 'Broadcasting Wi-Fi network directly from this device'
                              : 'Connect devices to the same local Wi-Fi router (e.g. 192.168.x.x:5000)',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Offline Hotspot Mode Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              color: const Color(0xFF1E1E2E),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.wifi_tethering, color: Color(0xFF8A2BE2)),
                                SizedBox(width: 8),
                                Text(
                                  'Offline Hotspot Mode',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Uses native hotspot when no Wi-Fi router is available',
                              style: TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                          ],
                        ),
                        Switch(
                          value: _isHotspotActive,
                          onChanged: _isServerStarting ? null : (val) => _toggleHotspotMode(val),
                          activeTrackColor: const Color(0xFF8A2BE2),
                        ),
                      ],
                    ),
                    if (_isHotspotActive && _hotspotSsid != null) ...[
                      const Divider(color: Colors.white10),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('SSID:', style: TextStyle(color: Colors.white70)),
                          SelectableText(
                            _hotspotSsid!,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      if (_hotspotPassword != null && _hotspotPassword!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Password:', style: TextStyle(color: Colors.white70)),
                            SelectableText(
                              _hotspotPassword!,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Server Status Card (LAN / Wi-Fi Sharing Server)
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
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _server.isRunning ? 'Server Active' : 'Server Stopped',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  _isHotspotActive ? 'Hotspot Mode Active' : 'LAN / Wi-Fi Mode Active',
                                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                                ),
                              ],
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


            // Bidirectional Text & Clipboard Sharing Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              color: const Color(0xFF1E1E2E),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.text_fields, color: Color(0xFF8A2BE2)),
                        SizedBox(width: 8),
                        Text(
                          'Share Text / Link',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _textController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Enter text or URL to send...',
                              hintStyle: const TextStyle(color: Colors.white38),
                              filled: true,
                              fillColor: const Color(0xFF2A2A3D),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () {
                            final text = _textController.text.trim();
                            if (text.isNotEmpty) {
                              _storageService.setLatestSharedText(text);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Text broadcast to connected clients')),
                              );
                            }
                          },
                          icon: const Icon(Icons.send, size: 18),
                          label: const Text('Send'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8A2BE2),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_receivedText.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2A3D),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF8A2BE2).withAlpha(100)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Latest Shared Text / Link:',
                              style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            SelectableText(
                              _receivedText,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: _receivedText));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Text copied to clipboard!')),
                                  );
                                },
                                icon: const Icon(Icons.copy, size: 16),
                                label: const Text('Copy'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF8A2BE2),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
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

            const SizedBox(height: 24),

            // Received Files Section
            if (_activeProgress != null && !_activeProgress!.isCompleted) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A3D),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF8A2BE2), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Receiving: ${_activeProgress!.filename} — ${_activeProgress!.percent.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: _activeProgress!.percent / 100.0,
                      backgroundColor: Colors.white10,
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8A2BE2)),
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
            ],

            const Text(
              'Received Files',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),

            if (receivedFiles.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2E).withAlpha(128),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.download_done, size: 48, color: Colors.white38),
                    SizedBox(height: 12),
                    Text(
                      'No files received yet',
                      style: TextStyle(color: Colors.white54, fontSize: 16),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Files sent to this device will appear here.',
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
                itemCount: receivedFiles.length,
                itemBuilder: (context, index) {
                  final file = receivedFiles[index];
                  final category = _storageService.getCategoryForFilename(file.name);
                  final folderPath = _getDisplayFolderPath(file.filePath);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: const Color(0xFF2A2A3D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.white10,
                        child: _getCategoryIcon(category),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              file.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8A2BE2).withAlpha(100),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              category,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatFileSize(file.size),
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            folderPath,
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
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
