import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionHelper {
  // Test hooks / overrides
  static bool? isAndroidOverride;
  static int? androidSdkVersionOverride;
  static Future<PermissionStatus> Function(Permission permission)? requestPermissionOverride;
  static Future<PermissionStatus> Function(Permission permission)? checkPermissionOverride;
  static Future<ServiceStatus> Function(Permission permission)? checkServiceStatusOverride;
  static Future<bool> Function()? openAppSettingsOverride;

  static bool get _isAndroid => isAndroidOverride ?? Platform.isAndroid;

  static Future<int> get _androidSdkVersion async {
    if (androidSdkVersionOverride != null) return androidSdkVersionOverride!;
    if (!_isAndroid) return 0;
    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      return androidInfo.version.sdkInt;
    } catch (_) {
      return 33; // Default fallback to modern API level if info check fails
    }
  }

  static Future<PermissionStatus> _checkPermission(Permission permission) async {
    if (checkPermissionOverride != null) {
      return checkPermissionOverride!(permission);
    }
    return await permission.status;
  }

  static Future<PermissionStatus> _requestPermission(Permission permission) async {
    if (requestPermissionOverride != null) {
      return requestPermissionOverride!(permission);
    }
    return await permission.request();
  }

  static Future<ServiceStatus> _checkServiceStatus(Permission permission) async {
    if (checkServiceStatusOverride != null) {
      return checkServiceStatusOverride!(permission);
    }
    if (permission is PermissionWithService) {
      return await permission.serviceStatus;
    }
    return ServiceStatus.enabled;
  }

  static Future<bool> _openAppSettings() async {
    if (openAppSettingsOverride != null) {
      return openAppSettingsOverride!();
    }
    return await openAppSettings();
  }

  /// Request Location & Nearby Devices permissions for Hotspot creation.
  static Future<bool> requestHotspotPermissions(BuildContext context) async {
    if (!_isAndroid) return true;

    final sdkInt = await _androidSdkVersion;
    final permissionsToRequest = <Permission>[];

    if (sdkInt >= 33) {
      permissionsToRequest.add(Permission.nearbyWifiDevices);
      permissionsToRequest.add(Permission.location);
    } else {
      permissionsToRequest.add(Permission.location);
    }

    bool hasPermanentlyDenied = false;
    bool allGranted = true;

    for (final perm in permissionsToRequest) {
      var status = await _checkPermission(perm);
      if (status.isDenied) {
        status = await _requestPermission(perm);
      }

      if (status.isPermanentlyDenied) {
        hasPermanentlyDenied = true;
        allGranted = false;
      } else if (!status.isGranted) {
        allGranted = false;
      }
    }

    if (hasPermanentlyDenied) {
      if (context.mounted) {
        await _showPermanentlyDeniedDialog(
          context,
          title: 'Permission Required',
          message:
              'Location & Nearby Devices permission is required by Android to create a local offline hotspot. Please enable it in Settings.',
        );
      }
      return false;
    }

    if (!allGranted) {
      return false;
    }

    // Check Location Service (GPS toggle)
    try {
      final serviceStatus = await _checkServiceStatus(Permission.location);
      if (serviceStatus != ServiceStatus.enabled) {
        if (context.mounted) {
          await _showLocationServiceDialog(context);
        }
        return false;
      }
    } catch (_) {
      // In non-supported platforms/emulators, continue
    }

    return true;
  }

  /// Request storage permissions for saving/accessing files in Download/LibreShare/.
  static Future<bool> requestStoragePermissions(BuildContext context) async {
    if (!_isAndroid) return true;

    final sdkInt = await _androidSdkVersion;
    if (sdkInt >= 33) {
      // On Android 13+, public Downloads folder does not require runtime storage permission
      return true;
    }

    var status = await _checkPermission(Permission.storage);
    if (status.isDenied) {
      status = await _requestPermission(Permission.storage);
    }

    if (status.isGranted) {
      return true;
    } else if (status.isPermanentlyDenied) {
      if (context.mounted) {
        await _showPermanentlyDeniedDialog(
          context,
          title: 'Storage Permission Required',
          message:
              'Storage permission is required to save received files to Download/LibreShare/. Please enable it in Settings.',
        );
      }
      return false;
    }

    return false;
  }

  /// Request camera permission for QR scanning.
  static Future<bool> requestCameraPermissions(BuildContext context) async {
    var status = await _checkPermission(Permission.camera);
    if (status.isDenied) {
      status = await _requestPermission(Permission.camera);
    }

    if (status.isGranted) {
      return true;
    } else if (status.isPermanentlyDenied) {
      if (context.mounted) {
        await _showPermanentlyDeniedDialog(
          context,
          title: 'Camera Permission Required',
          message: 'Camera permission is required to scan QR codes. Please enable it in Settings.',
        );
      }
      return false;
    }

    return false;
  }

  static Future<void> _showPermanentlyDeniedDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8A2BE2),
              foregroundColor: Colors.white,
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  static Future<void> _showLocationServiceDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text(
          'Location Service Disabled',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Please turn on Location Services (GPS) in your device settings to enable Offline Hotspot Mode.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8A2BE2),
              foregroundColor: Colors.white,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
