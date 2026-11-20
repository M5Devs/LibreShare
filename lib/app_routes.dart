import 'package:flutter/material.dart';

import '../features/connect/connect_kaios_screen.dart';
import '../features/connect/connect_pc_screen.dart';
import '../features/files/files_screen.dart';
import '../features/home/home_screen.dart';
import '../features/picker/file_picker_screen.dart';
import '../features/radar/receive_screen.dart';
import '../features/session/transfer_session_screen.dart';

/// Central route table for the redesigned navigation architecture.
class AppRoutes {
  AppRoutes._();

  static const String home = '/';
  static const String picker = '/picker';
  static const String receive = '/receive';
  static const String session = '/session';
  static const String files = '/files';
  static const String connectPc = '/connect-pc';
  static const String connectKaios = '/connect-kaios';

  static Map<String, WidgetBuilder> map() {
    return {
      home: (_) => const HomeScreen(),
      picker: (_) => const FilePickerScreen(),
      receive: (_) => const ReceiveScreen(),
      session: (_) => const TransferSessionScreen(),
      files: (_) => const FilesScreen(),
      connectPc: (_) => const ConnectPcScreen(),
      connectKaios: (_) => const ConnectKaiosScreen(),
    };
  }

  /// Opens the transfer room, closing anything stacked on top of it first.
  ///
  /// Every path that learns about a live peer (a scan, an approved request, the
  /// controller's own link event) funnels through here so they all land on the
  /// same room. Callers guard re-entry themselves, because the future below
  /// only completes once the room is popped again.
  static Future<void> openSession(BuildContext context) async {
    // Home stays mounted underneath the room, so a chat message arriving mid
    // session still triggers a link event. Without this check the room would be
    // popped and re-pushed, throwing away scroll position and typed text.
    if (TransferSessionScreen.isOpen) return;

    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);
    if (!context.mounted) return;
    await navigator.pushNamed(session);
  }
}
