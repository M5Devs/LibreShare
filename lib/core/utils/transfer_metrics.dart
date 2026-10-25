import 'dart:math';

class TransferMetrics {
  /// Formats byte counts cleanly (e.g., "0 B", "38.4 MB", "1.2 GB").
  static String formatSize(num bytes) {
    if (bytes <= 0 || bytes.isNaN || bytes.isInfinite) return '0 B';
    const k = 1024.0;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = (log(bytes) / log(k)).floor();
    if (i < 0) i = 0;
    if (i >= sizes.length) i = sizes.length - 1;

    final value = bytes / pow(k, i);
    if (i == 0) {
      return '${bytes.toInt()} B';
    }
    return '${value.toStringAsFixed(1)} ${sizes[i]}';
  }

  /// Formats speed cleanly (e.g., "0 B/s", "450.0 KB/s", "14.2 MB/s").
  static String formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond <= 0 || bytesPerSecond.isNaN || bytesPerSecond.isInfinite) {
      return '0 B/s';
    }
    return '${formatSize(bytesPerSecond)}/s';
  }

  /// Formats ETA into human-readable format (e.g., "~2s remaining", "~3m 12s remaining").
  static String formatEta(double remainingSeconds) {
    if (remainingSeconds <= 0 || remainingSeconds.isNaN || remainingSeconds.isInfinite) {
      return '~0s remaining';
    }

    final totalSeconds = remainingSeconds.round();
    if (totalSeconds <= 0) return '~0s remaining';

    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '~${hours}h ${minutes}m remaining';
    } else if (minutes > 0) {
      return '~${minutes}m ${seconds}s remaining';
    } else {
      return '~${seconds}s remaining';
    }
  }

  /// Formats elapsed duration into MM:SS format.
  static String formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds.clamp(0, 999999);
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// Middle-truncates long file names with ellipsis (e.g., "Sonic Boom...[720p].mp4").
  static String middleTruncate(String name, {int maxLength = 24}) {
    if (name.length <= maxLength || maxLength < 5) {
      return name;
    }

    final dotIdx = name.lastIndexOf('.');
    String baseName;
    String extension;

    if (dotIdx > 0 && dotIdx > name.length - 10) {
      baseName = name.substring(0, dotIdx);
      extension = name.substring(dotIdx);
    } else {
      baseName = name;
      extension = '';
    }

    final targetLength = maxLength - extension.length;
    if (targetLength <= 5) {
      // If extension is too long, truncate the string directly
      final front = (maxLength - 3) ~/ 2;
      final back = maxLength - 3 - front;
      return '${name.substring(0, front)}...${name.substring(name.length - back)}';
    }

    final frontLen = (targetLength - 3) ~/ 2;
    final backLen = targetLength - 3 - frontLen;

    final frontPart = baseName.substring(0, frontLen);
    final backPart = baseName.substring(baseName.length - backLen);

    return '$frontPart...$backPart$extension';
  }

  /// Computes Exponential Moving Average (EMA) for transfer speed.
  static double calculateEmaSpeed(
    double currentInstantSpeed,
    double previousSmoothedSpeed, {
    double alpha = 0.3,
  }) {
    if (currentInstantSpeed <= 0 || currentInstantSpeed.isNaN || currentInstantSpeed.isInfinite) {
      currentInstantSpeed = 0.0;
    }

    if (previousSmoothedSpeed <= 0 || previousSmoothedSpeed.isNaN || previousSmoothedSpeed.isInfinite) {
      return currentInstantSpeed;
    }

    return (alpha * currentInstantSpeed) + ((1.0 - alpha) * previousSmoothedSpeed);
  }

  /// Calculates remaining ETA in seconds.
  static double calculateEta(int remainingBytes, double speed) {
    if (remainingBytes <= 0 || speed <= 0 || speed.isNaN || speed.isInfinite) {
      return 0.0;
    }
    return remainingBytes / speed;
  }
}
