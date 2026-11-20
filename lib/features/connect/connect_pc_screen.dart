import 'package:flutter/material.dart';

import '../../state/share_controller.dart';
import '../../state/share_scope.dart';
import '../../theme/app_theme.dart';
import '../common/ui_kit.dart';
import 'connect_widgets.dart';

/// Full-screen "share with a computer" flow.
///
/// Replaces the old info sheet: the user has to carry an address and a PIN to
/// another device, so the steps stay on screen while they do it.
class ConnectPcScreen extends StatelessWidget {
  const ConnectPcScreen({super.key, this.controllerOverride});

  /// Injected by tests; defaults to the ambient controller.
  final ShareController? controllerOverride;

  @override
  Widget build(BuildContext context) {
    final controller = controllerOverride ?? ShareScope.of(context);
    final url = controller.serverUrl;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Connect to PC',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          const _LaptopPhoneHero(),
          const SizedBox(height: 20),
          if (url == null)
            const _NotStartedNotice()
          else ...[
            const StepHeader(
              number: 1,
              title: 'Join the same Wi-Fi',
              subtitle: 'Both devices must be on one network — or join this phone’s hotspot.',
            ),
            CopyField(
              label: 'Network',
              value: controller.hotspotSsid ?? 'Same Wi-Fi as this phone',
              icon: Icons.wifi_rounded,
            ),
            if (controller.hotspotPassword != null)
              CopyField(
                label: 'Hotspot password',
                value: controller.hotspotPassword!,
                icon: Icons.key_rounded,
                monospace: true,
              ),
            const SizedBox(height: 16),
            const StepHeader(
              number: 2,
              title: 'Open this address in a browser',
              subtitle: 'Type it into Chrome, Safari or Edge on the computer.',
            ),
            CopyField(
              label: 'Address',
              value: _pcUrl(url),
              icon: Icons.link_rounded,
              monospace: true,
            ),
            const SizedBox(height: 16),
            const StepHeader(
              number: 3,
              title: 'Enter the 6-digit PIN',
              subtitle: 'The browser asks for this code before the transfer starts.',
            ),
            CopyField(
              label: 'PIN',
              value: controller.pin,
              icon: Icons.pin_rounded,
              monospace: true,
            ),
            const SizedBox(height: 22),
            _ScanInsteadCard(pairingUrl: controller.pairingUrl),
          ],
        ],
      ),
    );
  }

  /// The web UI serves the PC portal at `/pc`; fall back to the bare origin.
  static String _pcUrl(String base) {
    final trimmed = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    return '$trimmed/pc';
  }
}

/// Flat illustration: a laptop next to a phone, drawn with widgets so it stays
/// crisp at any density and needs no asset.
class _LaptopPhoneHero extends StatelessWidget {
  const _LaptopPhoneHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.18),
            AppColors.accent.withValues(alpha: 0.12),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _DeviceFrame(
            width: 108,
            height: 68,
            icon: Icons.laptop_mac_rounded,
            iconSize: 34,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_rounded, color: AppColors.accent, size: 22),
                const SizedBox(height: 4),
                Text(
                  'LAN',
                  style: TextStyle(
                    color: AppColors.accent.withValues(alpha: 0.9),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          _DeviceFrame(
            width: 40,
            height: 68,
            icon: Icons.smartphone_rounded,
            iconSize: 24,
            radius: 10,
          ),
        ],
      ),
    );
  }
}

class _DeviceFrame extends StatelessWidget {
  const _DeviceFrame({
    required this.width,
    required this.height,
    required this.icon,
    required this.iconSize,
    this.radius = 8,
  });

  final double width;
  final double height;
  final IconData icon;
  final double iconSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.textMuted.withValues(alpha: 0.5), width: 1.6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(icon, size: iconSize, color: AppColors.textPrimary),
    );
  }
}

class _NotStartedNotice extends StatelessWidget {
  const _NotStartedNotice();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      borderColor: AppColors.warning.withValues(alpha: 0.5),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.warning),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Start Receive first — the app needs a running server before a '
              'computer can connect.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanInsteadCard extends StatelessWidget {
  const _ScanInsteadCard({required this.pairingUrl});

  final String? pairingUrl;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.qr_code_2_rounded, color: AppColors.accent),
              const SizedBox(width: 8),
              const Text(
                'Scan instead',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Point a phone camera at the QR code on the Receive screen to join '
            'without typing anything.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          Text(
            pairingUrl ?? 'Start Receive to generate a pairing link.',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
