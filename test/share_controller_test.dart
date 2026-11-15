import 'package:flutter_test/flutter_test.dart';
import 'package:libreshare/core/server/embedded_server.dart';
import 'package:libreshare/core/server/file_storage_service.dart';
import 'package:libreshare/core/server/shared_file.dart';
import 'package:libreshare/state/share_controller.dart';

ShareController buildController(FileStorageService storage) {
  final server = EmbeddedServer(
    htmlContentOverride: '<html></html>',
    storageService: storage,
  );
  return ShareController(server: server, storageService: storage);
}

void main() {
  test('starts idle and not running', () {
    final controller = buildController(FileStorageService());
    expect(controller.status, ServerStatus.stopped);
    expect(controller.isRunning, isFalse);
    expect(controller.mode, NetworkMode.lan);
    expect(controller.pairingUrl, isNull);

    controller.dispose();
  });

  test('sendText appends an outgoing chat entry and updates storage', () {
    final storage = FileStorageService();
    final controller = buildController(storage);

    controller.sendText('  hello world  ');

    expect(controller.entries.length, 1);
    final message = controller.entries.single as ChatMessage;
    expect(message.text, 'hello world');
    expect(message.incoming, isFalse);
    expect(storage.latestSharedText, 'hello world');

    controller.dispose();
  });

  test('sendText ignores blank input', () {
    final controller = buildController(FileStorageService());
    controller.sendText('   ');
    expect(controller.entries, isEmpty);
    controller.dispose();
  });

  test('shareFiles registers files and adds outgoing transfer cards', () {
    final storage = FileStorageService();
    final controller = buildController(storage);

    controller.shareFiles([
      SharedFile(
        id: 'a',
        name: 'clip.mp4',
        size: 4096,
        type: 'video/mp4',
        filePath: '/tmp/clip.mp4',
      ),
      SharedFile(
        id: 'b',
        name: 'notes.pdf',
        size: 1024,
        type: 'application/pdf',
        filePath: '/tmp/notes.pdf',
      ),
    ]);

    expect(storage.sharedFiles.length, 2);
    final transfers = controller.transfers;
    expect(transfers.length, 2);
    expect(transfers.every((t) => t.incoming == false), isTrue);
    expect(transfers.every((t) => t.status == TransferStatus.shared), isTrue);
    expect(transfers.first.category, 'Videos');

    controller.dispose();
  });

  test('approve and reject remove the pending request', () {
    final storage = FileStorageService();
    final controller = buildController(storage);

    final requestId = controller.server.sessionManager
        .createApprovalRequest(clientIp: '10.0.0.2', deviceLabel: 'Tablet')!;
    controller.pendingRequests.add(controller.server.sessionManager.getApprovalRequest(requestId)!);

    controller.approve(requestId);
    expect(controller.pendingRequests, isEmpty);

    controller.dispose();
  });

  test('cancelTransfer marks an incoming transfer cancelled', () {
    final controller = buildController(FileStorageService());
    final item = TransferItem(
      id: 'x',
      time: DateTime.now(),
      incoming: true,
      fileName: 'incoming.bin',
      totalBytes: 100,
    );
    controller.entries.add(item);

    controller.cancelTransfer(item);
    expect(item.status, TransferStatus.cancelled);

    controller.dispose();
  });

  test('removeReceivedFile deletes the file from storage', () async {
    final storage = FileStorageService();
    final controller = buildController(storage);
    final file = SharedFile(
      id: 'r',
      name: 'temp.txt',
      size: 1,
      type: 'text/plain',
      filePath: '/tmp/nonexistent_libreshare_temp.txt',
      ownedByApp: true,
    );
    storage.addSharedFile(file);

    controller.removeReceivedFile('r');
    expect(storage.sharedFiles, isEmpty);

    controller.dispose();
  });
}
