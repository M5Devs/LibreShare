import 'package:flutter/material.dart';

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

  static Map<String, WidgetBuilder> map() {
    return {
      home: (_) => const HomeScreen(),
      picker: (_) => const FilePickerScreen(),
      receive: (_) => const ReceiveScreen(),
      session: (_) => const TransferSessionScreen(),
      files: (_) => const FilesScreen(),
    };
  }
}
