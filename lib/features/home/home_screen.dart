import 'package:flutter/material.dart';

import '../../app_routes.dart';
import '../../state/share_controller.dart';
import '../../state/share_scope.dart';
import '../../theme/app_theme.dart';
import '../common/ui_kit.dart';

/// Home hub: the logo bar plus the three hero actions.
///
/// The screen owns exactly one behaviour beyond navigation — watching the
/// controller for a newly linked device and handing off to the transfer room.
/// Text and link sharing live in the room's chat bar, not here.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ShareController? _controller;
  int _seenEpoch = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = ShareScope.of(context);
    if (_controller == controller) return;

    _controller?.removeListener(_onControllerChanged);
    _controller = controller;
    _seenEpoch = controller.connectionEpoch;
    controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    if (controller.connectionEpoch == _seenEpoch) return;

    _seenEpoch = controller.connectionEpoch;
    if (!controller.peerConnected) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppRoutes.openSession(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ShareScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'LibreShare ⚡',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.2),
        ),
        actions: [
          const _OverflowMenu(),
          const SizedBox(width: 6),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(38),
          child: _StatusStrip(controller: controller),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
            child: const _HeroRow(),
          ),
        ),
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.controller});

  final ShareController controller;

  @override
  Widget build(BuildContext context) {
    final hotspot = controller.mode == NetworkMode.hotspot;
    final running = controller.isRunning;
    final label = running ? (hotspot ? 'Hotspot Mode' : 'LAN Mode') : 'Idle';
    final color = running
        ? (hotspot ? AppColors.accent : AppColors.success)
        : AppColors.textMuted;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      child: Row(
        children: [
          StatusPill(
            label: label,
            icon: hotspot ? Icons.wifi_tethering_rounded : Icons.wifi_rounded,
            color: color,
          ),
          const SizedBox(width: 8),
          // Deliberately not gated on `running`: joining a peer by QR links the
          // device without this phone ever starting its own server.
          if (controller.peerConnected)
            const StatusPill(
              label: 'Device linked',
              icon: Icons.link_rounded,
              color: AppColors.primary,
            ),
          if (controller.isConnecting) ...[
            const SizedBox(width: 8),
            const StatusPill(
              label: 'Connecting…',
              icon: Icons.sync_rounded,
              color: AppColors.warning,
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroRow extends StatelessWidget {
  const _HeroRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HeroActionButton(
          emoji: '🚀',
          label: 'Send',
          caption: 'Pick files',
          color: AppColors.primary,
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.picker),
        ),
        HeroActionButton(
          emoji: '📥',
          label: 'Receive',
          caption: 'Radar mode',
          color: AppColors.accent,
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.receive),
        ),
        HeroActionButton(
          emoji: '📁',
          label: 'Files',
          caption: 'Storage',
          color: AppColors.success,
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.files),
        ),
      ],
    );
  }
}

class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.add_circle_outline_rounded),
      tooltip: 'More',
      color: AppColors.surfaceHigh,
      onSelected: (value) {
        switch (value) {
          case 'pc':
            Navigator.of(context).pushNamed(AppRoutes.connectPc);
            break;
          case 'web':
            Navigator.of(context).pushNamed(AppRoutes.connectKaios);
            break;
          case 'bluetooth':
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Bluetooth invite: sharing the LibreShare APK'),
              ),
            );
            break;
          case 'settings':
            Navigator.of(context).pushNamed(AppRoutes.files);
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'pc', child: Text('💻  Connect to PC / Tablet')),
        PopupMenuItem(value: 'web', child: Text('🌐  Web & KaiOS Share')),
        PopupMenuItem(value: 'bluetooth', child: Text('📡  Invite via Bluetooth')),
        PopupMenuItem(value: 'settings', child: Text('⚙️  Settings')),
      ],
    );
  }
}
