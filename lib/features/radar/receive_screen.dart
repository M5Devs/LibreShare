import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app_routes.dart';
import '../../core/server/session_manager.dart';
import '../../core/utils/permission_helper.dart';
import '../../state/share_controller.dart';
import '../../state/share_scope.dart';
import '../../theme/app_theme.dart';
import '../common/ui_kit.dart';

/// Radar / receive screen: boots the server, shows the pairing QR + PIN and
/// hands off to the session screen once a peer connects.
class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key, this.autoStart = true});

  /// When false the screen renders without starting the server (tests).
  final bool autoStart;

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _radar;
  ShareController? _controller;
  bool _requested = false;
  String? _lastRequestId;

  @override
  void initState() {
    super.initState();
    _radar = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = ShareScope.of(context);
    if (_controller != controller) {
      _controller = controller;
      controller.addListener(_onControllerChanged);
      if (!_requested && widget.autoStart) {
        _requested = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
      }
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    _radar.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null || !mounted) return;

    final pending = controller.pendingRequests;
    if (pending.isNotEmpty && pending.first.id != _lastRequestId) {
      _lastRequestId = pending.first.id;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showApproval(pending.first));
    }
  }

  Future<void> _boot() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.isRunning) return;

    var useHotspot = false;
    try {
      useHotspot = await PermissionHelper.requestHotspotPermissions(context);
    } catch (_) {
      useHotspot = false;
    }
    await controller.start(
      networkMode: useHotspot ? NetworkMode.hotspot : NetworkMode.lan,
    );
  }

  Future<void> _showApproval(ApprovalRequest request) async {
    final controller = _controller;
    if (controller == null || !mounted) return;

    final allowed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Connection Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Device: ${request.deviceLabel}'),
            const SizedBox(height: 4),
            Text(
              'IP: ${request.clientIp}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            const Text('Allow this device to access shared files?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Deny', style: TextStyle(color: AppColors.danger)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );

    if (allowed == true) {
      controller.approve(request.id);
    } else {
      controller.reject(request.id);
    }
  }

  void _openScanner() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _ScannerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = ShareScope.of(context);
    final running = controller.isRunning;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Scan QR',
            onPressed: _openScanner,
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
          children: [
            Center(
              child: SizedBox(
                width: 240,
                height: 240,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _radar,
                      builder: (_, _) => CustomPaint(
                        size: const Size(240, 240),
                        painter: _RadarPainter(progress: _radar.value),
                      ),
                    ),
                    Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary.withValues(alpha: 0.18),
                        border: Border.all(color: AppColors.primary, width: 2),
                      ),
                      child: Icon(
                        running ? Icons.radar_rounded : Icons.power_settings_new_rounded,
                        color: AppColors.primary,
                        size: 36,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                running
                    ? (controller.peerConnected
                        ? 'A device is nearby…'
                        : 'Searching for senders…')
                    : 'Starting server…',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (controller.lastError != null)
              SurfaceCard(
                borderColor: AppColors.danger,
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.danger),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        controller.lastError!,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            _PairingCard(controller: controller),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openScanner,
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text('Scan instead'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pushNamed(AppRoutes.session),
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                    label: const Text('Open Room'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PairingCard extends StatelessWidget {
  const _PairingCard({required this.controller});

  final ShareController controller;

  @override
  Widget build(BuildContext context) {
    final qrData = controller.pairingUrl ?? controller.serverUrl ?? '';

    return SurfaceCard(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: qrData.isEmpty
                ? const SizedBox(
                    width: 168,
                    height: 168,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : QrImageView(
                    data: qrData,
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
          const SizedBox(height: 16),
          _PinDisplay(pin: controller.pin),
          const SizedBox(height: 16),
          _InfoRow(
            icon: Icons.wifi_rounded,
            label: 'Network',
            value: controller.hotspotSsid ?? 'LAN / Wi-Fi',
          ),
          if (controller.hotspotPassword != null)
            _InfoRow(
              icon: Icons.key_rounded,
              label: 'Password',
              value: controller.hotspotPassword!,
            ),
          _InfoRow(
            icon: Icons.link_rounded,
            label: 'Address',
            value: controller.serverUrl ?? '—',
            copyable: true,
          ),
        ],
      ),
    );
  }
}

class _PinDisplay extends StatelessWidget {
  const _PinDisplay({required this.pin});

  final String pin;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'PAIRING PIN',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final digit in pin.split(''))
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 34,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
                ),
                child: Text(
                  digit,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'PIN: $pin',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.accent),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (copyable)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Copy',
              icon: const Icon(Icons.copy_rounded, size: 16),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Address copied')),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (var i = 0; i < 3; i++) {
      final t = (progress + i / 3) % 1.0;
      final radius = maxRadius * t;
      final opacity = (1.0 - t).clamp(0.0, 1.0);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.primary.withValues(alpha: opacity * 0.6);
      canvas.drawCircle(center, radius, paint);
    }

    canvas.drawCircle(
      center,
      maxRadius * 0.32,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.accent.withValues(alpha: 0.35),
    );

    final sweep = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [
          AppColors.accent.withValues(alpha: 0.0),
          AppColors.accent.withValues(alpha: 0.25),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius));
    canvas.drawCircle(center, maxRadius, sweep);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _ScannerSheet extends StatefulWidget {
  const _ScannerSheet();

  @override
  State<_ScannerSheet> createState() => _ScannerSheetState();
}

class _ScannerSheetState extends State<_ScannerSheet> {
  final _addressController = TextEditingController();
  bool _checking = true;
  bool _cameraGranted = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    bool granted;
    try {
      granted = await PermissionHelper.requestCameraPermissions(context);
    } catch (_) {
      granted = false;
    }
    if (!mounted) return;
    setState(() {
      _cameraGranted = granted;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Scan Sender QR',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            alignment: Alignment.center,
            child: _checking
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.qr_code_scanner_rounded,
                        size: 54,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _cameraGranted
                            ? 'Point the camera at the sender’s QR code'
                            : 'Camera permission is needed to scan',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Or enter the sender address',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _addressController,
            keyboardType: TextInputType.url,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(hintText: 'http://192.168.43.1:5000'),
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }
}
