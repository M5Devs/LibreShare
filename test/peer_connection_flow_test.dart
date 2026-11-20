import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:libreshare/core/network/peer_connector.dart';
import 'package:libreshare/core/server/embedded_server.dart';
import 'package:libreshare/core/server/file_storage_service.dart';
import 'package:libreshare/state/share_controller.dart';

/// Exercises the whole "scan a peer's QR and join its room" path against a
/// real HTTP server — no stubs on either side of the socket.
void main() {
  late EmbeddedServer peer;
  late FileStorageService peerStorage;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('peer_flow_');
    peerStorage = FileStorageService(storageDirectoryOverride: tempDir);
    peer = EmbeddedServer(
      port: 0,
      htmlContentOverride: '<html><body>peer</body></html>',
      storageService: peerStorage,
    );
    await peer.start();
  });

  tearDown(() async {
    await peer.stop();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  ShareController buildController() {
    final storage = FileStorageService(storageDirectoryOverride: tempDir);
    final server = EmbeddedServer(
      port: 0,
      htmlContentOverride: '<html></html>',
      storageService: storage,
    );
    return ShareController(server: server, storageService: storage);
  }

  test('probe reports a live LibreShare peer as reachable', () async {
    const endpoint = PeerEndpoint(host: '127.0.0.1', port: 0);
    final live = PeerEndpoint(host: '127.0.0.1', port: peer.actualPort!);

    expect(await PeerConnector.probe(live), isTrue);
    expect(await PeerConnector.probe(endpoint), isFalse);
  });

  test('a real QR payload links the peer and bumps the connection epoch',
      () async {
    final controller = buildController();
    await controller.init();
    final payload = 'http://127.0.0.1:${peer.actualPort}/?t=${peer.sessionManager.pairingToken}';

    expect(controller.peerConnected, isFalse);
    expect(controller.connectionEpoch, 0);

    final connected = await controller.connectToPeer(payload);

    expect(connected, isTrue);
    expect(controller.peerConnected, isTrue);
    expect(controller.connectionEpoch, 1);
    expect(controller.connectedPeerUrl, 'http://127.0.0.1:${peer.actualPort}');
    expect(controller.connectError, isNull);
    expect(controller.isConnecting, isFalse);

    controller.dispose();
  });

  test('an unreachable peer leaves the connection state untouched', () async {
    final controller = buildController();
    await controller.init();

    final connected =
        await controller.connectToPeer('http://127.0.0.1:1/?t=abc');

    expect(connected, isFalse);
    expect(controller.peerConnected, isFalse);
    expect(controller.connectionEpoch, 0);
    expect(controller.connectedPeerUrl, isNull);
    expect(controller.connectError, contains('Could not reach'));

    controller.dispose();
  });

  test('rejects non-peer payloads without probing the network', () async {
    var probed = false;
    final storage = FileStorageService(storageDirectoryOverride: tempDir);
    final server = EmbeddedServer(
      port: 0,
      htmlContentOverride: '<html></html>',
      storageService: storage,
    );
    final controller = ShareController(
      server: server,
      storageService: storage,
      peerProbe: (_) async {
        probed = true;
        return true;
      },
    );
    await controller.init();

    final connected = await controller.connectToPeer('WIFI:S:Cafe;T:WPA;P:x;;');

    expect(connected, isFalse);
    expect(probed, isFalse);
    expect(controller.peerConnected, isFalse);
    expect(controller.connectError, contains('not a LibreShare address'));

    controller.dispose();
  });

  test('an inbound text from the peer links the session', () async {
    final controller = buildController();
    await controller.init();

    // Drive the real server-side path: the text goes through the storage
    // stream that the controller subscribes to.
    controller.storage.setLatestSharedText('hello from the other side');
    await pumpEventQueue();

    expect(controller.peerConnected, isTrue);
    expect(controller.connectionEpoch, 1);

    final messages = controller.entries.whereType<ChatMessage>().toList();
    expect(messages.single.text, 'hello from the other side');
    expect(messages.single.incoming, isTrue);

    controller.dispose();
  });

  test('a pending approval shows the peer as present but not linked', () async {
    final controller = buildController();
    await controller.init();

    final requestId = controller.server.sessionManager
        .createApprovalRequest(clientIp: '10.0.0.4', deviceLabel: 'Tablet');
    expect(requestId, isNotNull);

    // Approving is the moment the link becomes real.
    controller.approve(requestId!);

    expect(controller.peerConnected, isTrue);
    expect(controller.connectionEpoch, 1);

    controller.dispose();
  });

  test('stopping the server clears the linked state', () async {
    final controller = buildController();
    await controller.init();
    await controller.connectToPeer(
      'http://127.0.0.1:${peer.actualPort}',
    );
    expect(controller.peerConnected, isTrue);

    await controller.stop();

    expect(controller.peerConnected, isFalse);
    expect(controller.serverUrl, isNull);

    controller.dispose();
  });
}
