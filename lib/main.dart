import 'package:flutter/material.dart';

import 'app_routes.dart';
import 'state/share_controller.dart';
import 'state/share_scope.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const LibreShareApp());
}

class LibreShareApp extends StatefulWidget {
  const LibreShareApp({super.key, this.controllerOverride});

  /// Injected by tests to avoid touching real platform services.
  final ShareController? controllerOverride;

  @override
  State<LibreShareApp> createState() => _LibreShareAppState();
}

class _LibreShareAppState extends State<LibreShareApp> {
  late final ShareController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controllerOverride ?? ShareController();
    _controller.init();
  }

  @override
  void dispose() {
    if (widget.controllerOverride == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShareScope(
      controller: _controller,
      child: MaterialApp(
        title: 'LibreShare',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        initialRoute: AppRoutes.home,
        routes: AppRoutes.map(),
      ),
    );
  }
}
