import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../state/share_controller.dart';
import '../../state/share_scope.dart';
import '../../theme/app_theme.dart';
import '../common/ui_kit.dart';
import 'connect_widgets.dart';

/// Full-screen portal for KaiOS and other feature phones.
///
/// These devices cannot install an app and often cannot scan a QR code, so the
/// screen leads with the one thing that works everywhere: a short URL to type
/// into a browser.
class ConnectKaiosScreen extends StatelessWidget {
  const ConnectKaiosScreen({super.key, this.controllerOverride});

  final ShareController? controllerOverride;

  @override
  Widget build(BuildContext context) {
    final controller = controllerOverride ?? ShareScope.of(context);
    final url = controller.serverUrl;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'KaiOS & Feature Phones',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          const _FeaturePhoneHero(),
          const SizedBox(height: 18),
          if (url == null)
            const SurfaceCard(
              borderColor: AppColors.warning,
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: AppColors.warning),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Start Receive to publish an address for other phones.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            const StepHeader(
              number: 1,
              title: 'Join the same Wi-Fi or hotspot',
              subtitle: 'On the phone: Settings → Network → Wi-Fi.',
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
                secret: true,
              ),
            const SizedBox(height: 16),
            const StepHeader(
              number: 2,
              title: 'Open the browser and type this',
              subtitle: 'Short and case-free — designed for a numeric keypad.',
            ),
            CopyField(
              label: 'Address',
              value: url,
              icon: Icons.link_rounded,
              monospace: true,
            ),
            const SizedBox(height: 16),
            const StepHeader(
              number: 3,
              title: 'Enter the PIN when asked',
              subtitle: 'Proves both devices are in the same room.',
            ),
            CopyField(
              label: 'PIN',
              value: controller.pin,
              icon: Icons.pin_rounded,
              monospace: true,
            ),
          ],
          const SizedBox(height: 22),
          if (controller.pairingUrl != null) _QrCard(data: controller.pairingUrl!),
          const SizedBox(height: 14),
          const _CompatibilityCard(),
        ],
      ),
    );
  }
}

/// A stubby feature phone with a keypad, drawn with widgets.
class _FeaturePhoneHero extends StatelessWidget {
  const _FeaturePhoneHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.warning.withValues(alpha: 0.16),
            AppColors.accent.withValues(alpha: 0.12),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Center(
        child: Container(
          width: 74,
          height: 124,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.textMuted.withValues(alpha: 0.5),
              width: 1.6,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(5),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.public_rounded,
                  size: 20,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 7),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 3,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  children: List.generate(
                    12,
                    (_) => Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        children: [
          const Text(
            'Scan to open the portal',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Any phone with a camera can join by scanning this.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: QrImageView(
              data: data,
              size: 168,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Color(0xFF0F172A),
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompatibilityCard extends StatelessWidget {
  const _CompatibilityCard();

  @override
  Widget build(BuildContext context) {
    const platforms = [
      ('KaiOS 2.5+', Icons.phone_android_rounded),
      ('Nokia / JioPhone', Icons.smartphone_rounded),
      ('Any browser', Icons.public_rounded),
    ];

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Works without installing anything',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          for (final (label, icon) in platforms)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(icon, size: 15, color: AppColors.success),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
