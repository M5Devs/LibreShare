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
          _OverflowMenu(controller: controller),
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
  const _OverflowMenu({required this.controller});

  final ShareController controller;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.add_circle_outline_rounded),
      tooltip: 'More',
      color: AppColors.surfaceHigh,
      onSelected: (value) {
        switch (value) {
          case 'pc':
            _showInfoSheet(
              context,
              title: '💻 Connect to PC / Tablet',
              lines: [
                '1. Join the same Wi-Fi as this phone.',
                '2. Open a browser and go to the address below.',
                '3. Enter the 6-digit PIN when prompted.',
                '',
                'Address:  ${controller.serverUrl ?? 'Start Receive for an address'}',
                'Port:     5000',
                'PIN:      ${controller.pin}',
              ],
            );
            break;
          case 'web':
            _showInfoSheet(
              context,
              title: '🌐 Web & KaiOS Share',
              lines: [
                'Open this link on any browser — phones, laptops or KaiOS:',
                '',
                controller.serverUrl ?? 'Start Receive to get a link',
                '',
                'No app install required.',
              ],
            );
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

  void _showInfoSheet(
    BuildContext context, {
    required String title,
    required List<String> lines,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _InfoSheet(title: title, lines: lines),
    );
  }
}

class _InfoSheet extends StatelessWidget {
  const _InfoSheet({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: SelectableText(
                line,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
