import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_routes.dart';
import '../../state/share_controller.dart';
import '../../state/share_scope.dart';
import '../../theme/app_theme.dart';
import '../common/ui_kit.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
          children: [
            _NetworkBadge(controller: controller),
            const SizedBox(height: 22),
            const _HeroRow(),
            const SizedBox(height: 24),
            _QuickShareCard(controller: controller),
            const SizedBox(height: 20),
            _ActivityCard(controller: controller),
          ],
        ),
      ),
    );
  }
}

class _NetworkBadge extends StatelessWidget {
  const _NetworkBadge({required this.controller});

  final ShareController controller;

  @override
  Widget build(BuildContext context) {
    final hotspot = controller.mode == NetworkMode.hotspot;
    final running = controller.isRunning;
    final label = running ? (hotspot ? 'Hotspot Mode' : 'LAN Mode') : 'Idle';
    final color = running
        ? (hotspot ? AppColors.accent : AppColors.success)
        : AppColors.textMuted;

    return Row(
      children: [
        StatusPill(
          label: label,
          icon: hotspot ? Icons.wifi_tethering_rounded : Icons.wifi_rounded,
          color: color,
        ),
        const SizedBox(width: 8),
        if (running && controller.peerConnected)
          const StatusPill(
            label: 'Device linked',
            icon: Icons.link_rounded,
            color: AppColors.primary,
          ),
      ],
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

class _QuickShareCard extends StatefulWidget {
  const _QuickShareCard({required this.controller});

  final ShareController controller;

  @override
  State<_QuickShareCard> createState() => _QuickShareCardState();
}

class _QuickShareCardState extends State<_QuickShareCard> {
  final _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    widget.controller.sendText(text);
    _textController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Text broadcast to connected devices')),
    );
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null) {
      _textController.text = text;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bolt_rounded, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text(
                'Quick Text / URL',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _textController,
            minLines: 1,
            maxLines: 3,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Paste a link or type a message…',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  label: const Text('Paste'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _send,
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Send'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.controller});

  final ShareController controller;

  @override
  Widget build(BuildContext context) {
    final recent = controller.transfers.reversed.take(3).toList();

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Recent Activity'),
          const SizedBox(height: 12),
          if (recent.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'No transfers yet. Tap Send or Receive to get started.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            )
          else
            for (final item in recent)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    CategoryAvatar(category: item.category, size: 38),
                    const SizedBox(width: 12),
                    Expanded(child: TruncatedName(name: item.fileName, maxLength: 24)),
                    const SizedBox(width: 8),
                    Text(
                      item.incoming ? 'Received' : 'Shared',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
        ],
      ),
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
