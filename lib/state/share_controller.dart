import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/network/hotspot_manager.dart';
import '../core/network/network_helper.dart';
import '../core/network/peer_connector.dart';
import '../core/platform/native_bridge.dart';
import '../core/server/embedded_server.dart';
import '../core/server/file_storage_service.dart';
import '../core/server/session_manager.dart';
import '../core/server/shared_file.dart';
import 'network_address.dart';

/// How the local server is being reached by peers.
enum NetworkMode { lan, hotspot }

enum ServerStatus { stopped, starting, running }

enum TransferDirection { incoming, outgoing }

enum TransferStatus { active, paused, completed, cancelled, failed, shared }

/// A single line in the in-room feed: either a text bubble or a file card.
abstract class SessionEntry {
  SessionEntry({required this.id, required this.time, required this.incoming});

  final String id;
  final DateTime time;
  final bool incoming;
}

class ChatMessage extends SessionEntry {
  ChatMessage({
    required super.id,
    required super.time,
    required super.incoming,
    required this.text,
  });

  final String text;
}

class TransferItem extends SessionEntry {
  TransferItem({
    required super.id,
    required super.time,
    required super.incoming,
    required this.fileName,
    required this.totalBytes,
    this.transferredBytes = 0,
    this.percent = 0,
    this.speedString = '',
    this.etaString = '',
    this.status = TransferStatus.active,
    this.category = 'Documents',
    this.filePath,
  });

  final String fileName;
  final int totalBytes;

  /// On-disk location once known. Incoming files only learn theirs when the
  /// upload completes, so this is resolved lazily by the room's file list.
  String? filePath;
  int transferredBytes;
  double percent;
  String speedString;
  String etaString;
  TransferStatus status;
  final String category;

  bool get isFinished =>
      status == TransferStatus.completed ||
      status == TransferStatus.cancelled ||
      status == TransferStatus.failed;
}

/// Owns the running [EmbeddedServer] plus the UI-facing session state.
///
/// The controller never changes backend behaviour: it only drives the
/// existing services and re-exposes their state as a [ChangeNotifier].
class ShareController extends ChangeNotifier {
  /// Builds a controller whose server always serves the same [storage].
  factory ShareController({
    EmbeddedServer? server,
    FileStorageService? storageService,
    Future<bool> Function(PeerEndpoint endpoint)? peerProbe,
  }) {
    final storage = storageService ?? FileStorageService();
    final resolved = server ?? EmbeddedServer(storageService: storage);
    return ShareController._(storage, resolved, peerProbe ?? PeerConnector.probe);
  }

  ShareController._(this.storage, this.server, this._peerProbe);

  final FileStorageService storage;
  final EmbeddedServer server;
  final Future<bool> Function(PeerEndpoint endpoint) _peerProbe;

  ServerStatus status = ServerStatus.stopped;
  NetworkMode mode = NetworkMode.lan;
  String? serverUrl;
  String? hotspotSsid;
  String? hotspotPassword;
  bool peerConnected = false;
  String? lastError;

  /// Address of the room this device joined by scanning a peer's QR code.
  String? connectedPeerUrl;
  bool isConnecting = false;
  String? connectError;

  /// Increments every time a peer link comes up. The home screen watches it so
  /// a fresh connection hands off to the transfer room exactly once.
  int connectionEpoch = 0;

  final List<SessionEntry> entries = [];
  final List<ApprovalRequest> pendingRequests = [];

  StreamSubscription<String>? _textSub;
  StreamSubscription<UploadProgress?>? _progressSub;
  StreamSubscription<Map<String, dynamic>>? _nativeSub;
  Timer? _approvalTimer;
  bool _disposed = false;

  bool get isRunning => status == ServerStatus.running;
  bool get isBusy => status == ServerStatus.starting;

  String get pin => server.sessionManager.pin;

  /// Pairing URL carrying the single-use pairing token.
  String? get pairingUrl {
    if (serverUrl == null) return null;
    return '$serverUrl/?t=${server.sessionManager.pairingToken}';
  }

  /// URL shown to peers who type it manually or scan the plain QR.
  String? get plainUrl => serverUrl;

  int get _counter => _entrySeq++;
  int _entrySeq = 0;

  /// Marks a peer as present. Used for weaker signals (a pending approval) that
  /// must show the "Device linked" badge without handing off to the room — the
  /// user still has to accept the request first.
  void _markPeerPresent() {
    peerConnected = true;
  }

  /// Marks the peer as fully linked and starts a new connection epoch.
  ///
  /// Only signals that prove an established session land here: an accepted
  /// approval, an inbound text, an upload in flight, or an accepted QR scan.
  /// The UI watches [connectionEpoch] so it hands off to the room exactly once
  /// per link, instead of on every state notification.
  void _markPeerLinked() {
    peerConnected = true;
    connectionEpoch++;
  }

  /// Joins the room advertised by a scanned QR payload.
  ///
  /// Returns true when the peer answered and the room should be opened. The
  /// payload is rejected unless it parses as a LibreShare address, so scanning
  /// an unrelated QR code cannot hijack the flow.
  Future<bool> connectToPeer(String payload) async {
    if (isConnecting) return false;

    final endpoint = PeerConnector.parse(payload);
    if (endpoint == null) {
      connectError = 'That QR code is not a LibreShare address.';
      _notify();
      return false;
    }

    isConnecting = true;
    connectError = null;
    _notify();

    try {
      final reachable = await _peerProbe(endpoint);
      if (!reachable) {
        connectError = 'Could not reach ${endpoint.baseUrl}. '
            'Make sure you are on the same Wi-Fi or hotspot.';
        return false;
      }

      connectedPeerUrl = endpoint.baseUrl;
      _markPeerLinked();
      return true;
    } catch (e) {
      connectError = 'Connection failed: $e';
      return false;
    } finally {
      isConnecting = false;
      _notify();
    }
  }

  Future<void> init() async {
    _textSub = storage.textStream.listen((text) {
      if (text.isEmpty) return;
      entries.add(ChatMessage(
        id: 'in-$_counter',
        time: DateTime.now(),
        incoming: true,
        text: text,
      ));
      _markPeerLinked();
      _notify();
    });

    _progressSub = storage.progressStream.listen((progress) {
      if (progress == null) return;
      _applyProgress(progress);
      _markPeerLinked();
      _notify();
    });

    _nativeSub = NativeBridge.events.listen((event) {
      switch (event['type']) {
        case 'hotspot_stopped':
          stop();
          break;
        case 'service_error':
          lastError = event['message']?.toString();
          _notify();
          break;
      }
    });
  }

  void _applyProgress(UploadProgress progress) {
    final existing = entries.whereType<TransferItem>().firstWhere(
          (t) => t.fileName == progress.filename && t.incoming,
          orElse: () => TransferItem(
            id: 'tr-$_counter',
            time: DateTime.now(),
            incoming: true,
            fileName: progress.filename,
            totalBytes: progress.totalBytes,
            category: progress.category,
          ),
        );

    existing
      ..transferredBytes = progress.currentBytes
      ..percent = progress.percent
      ..speedString = progress.speedString
      ..etaString = progress.etaString
      ..status = progress.isCompleted ? TransferStatus.completed : TransferStatus.active;

    // The saved path is only known once the server has finished writing, so
    // look it up from the received list rather than plumbing it through every
    // progress tick.
    if (progress.isCompleted && existing.filePath == null) {
      existing.filePath = _receivedPathFor(progress.filename);
    }

    if (!entries.contains(existing)) {
      entries.add(existing);
    }
  }

  String? _receivedPathFor(String fileName) {
    for (final file in storage.receivedFiles) {
      if (file.name == fileName) return file.filePath;
    }
    return null;
  }

  Future<void> start({NetworkMode networkMode = NetworkMode.lan}) async {
    if (status != ServerStatus.stopped) return;

    status = ServerStatus.starting;
    mode = networkMode;
    lastError = null;
    _notify();

    try {
      String? ip;
      if (networkMode == NetworkMode.hotspot) {
        final info = await HotspotManager.startHotspot();
        if (info != null) {
          hotspotSsid = info['ssid'];
          hotspotPassword = info['password'];
          ip = info['ip'];
        }

        // The native hotspot IP is authoritative, but a device that also has
        // cellular up can hand back a carrier address. Reject anything that is
        // not a private AP address and re-derive it from the interfaces.
        if (ip == null || !NetworkAddress.isHotspotAddress(ip)) {
          ip = await NetworkAddress.findHotspotAddress();
        }

        if (ip == null) {
          // Don't leak a running hotspot that the user cannot reach.
          try {
            await HotspotManager.stopHotspot();
          } catch (_) {}
          hotspotSsid = null;
          hotspotPassword = null;
          status = ServerStatus.stopped;
          lastError =
              'Hotspot is active but no local hotspot address was found. '
              'Turn off mobile data and try again.';
          _notify();
          return;
        }
      }

      if (!server.isRunning) {
        await server.start();
      }

      var resolvedIp = ip ?? await NetworkHelper.getLocalIpAddress();

      // In LAN mode the helper can still land on a cellular address when Wi-Fi
      // is down. Prefer a private-AP address so the QR code stays reachable.
      if (NetworkAddress.isCellularAddress(resolvedIp)) {
        final better = await NetworkAddress.findHotspotAddress();
        if (better != null) resolvedIp = better;
      }

      final port = server.actualPort ?? NetworkHelper.defaultPort;
      serverUrl = NetworkHelper.formatServerUrl(resolvedIp, port);

      status = ServerStatus.running;
      _startPolling();

      try {
        await NativeBridge.startForegroundService(text: 'LibreShare • $serverUrl');
      } catch (_) {}
    } catch (e) {
      status = ServerStatus.stopped;
      lastError = e.toString();
    }

    _notify();
  }

  Future<void> stop() async {
    _stopPolling();
    if (server.isRunning) {
      await server.stop();
    }
    if (mode == NetworkMode.hotspot) {
      try {
        await HotspotManager.stopHotspot();
      } catch (_) {}
    }
    try {
      await NativeBridge.stopForegroundService();
    } catch (_) {}

    status = ServerStatus.stopped;
    serverUrl = null;
    hotspotSsid = null;
    hotspotPassword = null;
    peerConnected = false;
    pendingRequests.clear();
    _notify();
  }

  void _startPolling() {
    _approvalTimer?.cancel();
    _approvalTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final pending = server.sessionManager.pendingRequests;
      final changed = pending.length != pendingRequests.length ||
          !pending.every((p) => pendingRequests.any((q) => q.id == p.id));
      if (changed) {
        pendingRequests
          ..clear()
          ..addAll(pending);
        if (pending.isNotEmpty) _markPeerPresent();
        _notify();
      }
    });
  }

  void _stopPolling() {
    _approvalTimer?.cancel();
    _approvalTimer = null;
  }

  void approve(String requestId) {
    server.sessionManager.approveRequest(requestId);
    pendingRequests.removeWhere((r) => r.id == requestId);
    _markPeerLinked();
    _notify();
  }

  void reject(String requestId) {
    server.sessionManager.rejectRequest(requestId);
    pendingRequests.removeWhere((r) => r.id == requestId);
    _notify();
  }

  /// Registers files to serve and adds an outgoing card for each.
  void shareFiles(List<SharedFile> files) {
    for (final file in files) {
      storage.addSharedFile(file);
      entries.add(TransferItem(
        id: 'out-$_counter',
        time: DateTime.now(),
        incoming: false,
        fileName: file.name,
        totalBytes: file.size,
        percent: 100,
        status: TransferStatus.shared,
        category: storage.getCategoryForFilename(file.name),
        filePath: file.filePath,
      ));
    }
    _notify();
  }

  void sendText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    storage.setLatestSharedText(trimmed);
    entries.add(ChatMessage(
      id: 'out-$_counter',
      time: DateTime.now(),
      incoming: false,
      text: trimmed,
    ));
    _notify();
  }

  void cancelTransfer(TransferItem item) {
    if (!item.incoming) return;
    item.status = TransferStatus.cancelled;
    _notify();
  }

  void togglePause(TransferItem item) {
    if (item.status == TransferStatus.active) {
      item.status = TransferStatus.paused;
    } else if (item.status == TransferStatus.paused) {
      item.status = TransferStatus.active;
    }
    _notify();
  }

  void removeReceivedFile(String id) {
    storage.removeSharedFile(id);
    _notify();
  }

  List<TransferItem> get transfers =>
      entries.whereType<TransferItem>().toList(growable: false);

  List<TransferItem> get activeTransfers =>
      transfers.where((t) => !t.isFinished).toList(growable: false);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPolling();
    _textSub?.cancel();
    _progressSub?.cancel();
    _nativeSub?.cancel();
    if (server.isRunning) {
      server.stop();
    }
    super.dispose();
  }
}
