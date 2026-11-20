import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/network/peer_connector.dart';
import '../../core/utils/permission_helper.dart';
import '../../theme/app_theme.dart';

/// Bottom sheet that scans a peer's QR code with the real camera.
///
/// The camera preview is injected through [previewBuilder] so widget tests can
/// exercise the whole permission → detect → parse → connect flow without a
/// camera or platform channel. In production the builder is null and the
/// sheet renders a live [MobileScanner].
class QrScannerSheet extends StatefulWidget {
  const QrScannerSheet({
    super.key,
    required this.onPayload,
    this.previewBuilder,
    this.scannerController,
  });

  /// Called with the raw QR text. Returning true closes the sheet as a success.
  final Future<bool> Function(String payload) onPayload;

  /// Test seam: replaces the live camera preview.
  final Widget Function(BuildContext context, ValueChanged<String> onDetect)?
      previewBuilder;

  /// Test seam: replaces the internally created camera controller.
  final MobileScannerController? scannerController;

  @override
  State<QrScannerSheet> createState() => _QrScannerSheetState();
}

class _QrScannerSheetState extends State<QrScannerSheet> {
  MobileScannerController? _scanner;
  final _manualController = TextEditingController();
  bool _checking = true;
  bool _cameraGranted = false;
  bool _handled = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _requestCamera();
  }

  @override
  void dispose() {
    _manualController.dispose();
    _scanner?.dispose();
    super.dispose();
  }

  Future<void> _requestCamera() async {
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
      if (granted) {
        _scanner = widget.scannerController ?? MobileScannerController();
      }
    });
  }

  Future<void> _submit(String payload) async {
    if (_handled || _busy) return;
    final endpoint = PeerConnector.parse(payload);
    if (endpoint == null) {
      // Unrelated QR codes are ignored rather than failing the whole scan.
      setState(() => _error = 'That QR code is not a LibreShare address.');
      return;
    }

    _handled = true;
    setState(() {
      _busy = true;
      _error = null;
    });

    final ok = await widget.onPayload(payload);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _handled = false;
      _busy = false;
      _error = 'Could not reach ${endpoint.host}:${endpoint.port}. '
          'Check that both devices share the same network.';
    });
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) continue;
      _submit(value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        22,
        22,
        22,
        30 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
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
            const SizedBox(height: 14),
            _buildPreview(context),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppColors.danger, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Or enter the sender address',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _manualController,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'http://192.168.43.1:5000',
              ),
              onSubmitted: _submit,
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _busy
                  ? null
                  : () => _submit(_manualController.text.trim()),
              child: Text(_busy ? 'Connecting…' : 'Connect'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    final frame = ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(height: 240, child: _previewContent(context)),
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: frame,
    );
  }

  Widget _previewContent(BuildContext context) {
    if (_checking) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_cameraGranted) {
      return const _ScannerHint(
        icon: Icons.no_photography_rounded,
        message: 'Camera permission is needed to scan QR codes.\n'
            'Use the address field below instead.',
      );
    }
    if (_busy) {
      return const Center(child: CircularProgressIndicator());
    }

    final injected = widget.previewBuilder;
    if (injected != null) return injected(context, _submit);

    final scanner = _scanner;
    if (scanner == null) {
      return const _ScannerHint(
        icon: Icons.qr_code_scanner_rounded,
        message: 'Camera is not available on this device.',
      );
    }

    return MobileScanner(
      controller: scanner,
      onDetect: _onDetect,
      errorBuilder: (context, error) => _ScannerHint(
        icon: Icons.videocam_off_rounded,
        message: error.errorDetails?.message ??
            'Camera unavailable. Use the address field below.',
      ),
      overlayBuilder: (context, constraints) => const _ScanFrameOverlay(),
    );
  }
}

class _ScannerHint extends StatelessWidget {
  const _ScannerHint({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppColors.textSecondary),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanFrameOverlay extends StatelessWidget {
  const _ScanFrameOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 190,
          height: 190,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.accent, width: 2.5),
          ),
        ),
      ),
    );
  }
}
