import 'package:flutter_test/flutter_test.dart';
import 'package:libreshare/core/utils/transfer_metrics.dart';

void main() {
  group('TransferMetrics Helper Tests', () {
    test('formatSize formats bytes cleanly and handles zero/negative/infinity', () {
      expect(TransferMetrics.formatSize(0), equals('0 B'));
      expect(TransferMetrics.formatSize(-100), equals('0 B'));
      expect(TransferMetrics.formatSize(double.nan), equals('0 B'));
      expect(TransferMetrics.formatSize(double.infinity), equals('0 B'));

      expect(TransferMetrics.formatSize(500), equals('500 B'));
      expect(TransferMetrics.formatSize(1024), equals('1.00 KB'));
      expect(TransferMetrics.formatSize(1500 * 1024), equals('1.46 MB'));
      expect(TransferMetrics.formatSize(2.5 * 1024 * 1024 * 1024), equals('2.50 GB'));
    });

    test('formatSpeed formats bytes per second cleanly', () {
      expect(TransferMetrics.formatSpeed(0), equals('0 B/s'));
      expect(TransferMetrics.formatSpeed(-50), equals('0 B/s'));
      expect(TransferMetrics.formatSpeed(500 * 1024), equals('500.00 KB/s'));
      expect(TransferMetrics.formatSpeed(14.2 * 1024 * 1024), equals('14.20 MB/s'));
    });

    test('formatEta formats remaining seconds into human-readable string', () {
      expect(TransferMetrics.formatEta(0), equals('~0s remaining'));
      expect(TransferMetrics.formatEta(-5), equals('~0s remaining'));
      expect(TransferMetrics.formatEta(double.nan), equals('~0s remaining'));
      expect(TransferMetrics.formatEta(12), equals('~12s remaining'));
      expect(TransferMetrics.formatEta(125), equals('~2m 5s remaining'));
      expect(TransferMetrics.formatEta(3665), equals('~1h 1m remaining'));
    });

    test('formatDuration formats Duration into MM:SS format', () {
      expect(TransferMetrics.formatDuration(Duration.zero), equals('00:00'));
      expect(TransferMetrics.formatDuration(const Duration(seconds: 5)), equals('00:05'));
      expect(TransferMetrics.formatDuration(const Duration(seconds: 85)), equals('01:25'));
      expect(TransferMetrics.formatDuration(const Duration(minutes: 12, seconds: 3)), equals('12:03'));
    });

    test('middleTruncate truncates long filenames in the middle with ellipsis', () {
      expect(TransferMetrics.middleTruncate('short.txt', maxLength: 24), equals('short.txt'));

      const longName = 'Sonic Boom Season 1 Episode 5 720p HDTV.mp4';
      final truncated = TransferMetrics.middleTruncate(longName, maxLength: 24);
      expect(truncated.contains('...'), isTrue);
      expect(truncated.endsWith('.mp4'), isTrue);
      expect(truncated.length <= 24, isTrue);
    });

    test('calculateEmaSpeed computes smooth exponential moving average', () {
      // First sample initializes to instant speed
      final s1 = TransferMetrics.calculateEmaSpeed(1000.0, 0.0);
      expect(s1, equals(1000.0));

      // Second sample with alpha 0.3: 0.3 * 2000 + 0.7 * 1000 = 600 + 700 = 1300
      final s2 = TransferMetrics.calculateEmaSpeed(2000.0, s1, alpha: 0.3);
      expect(s2, equals(1300.0));
    });

    test('calculateEta handles zero division and invalid values', () {
      expect(TransferMetrics.calculateEta(0, 100), equals(0.0));
      expect(TransferMetrics.calculateEta(100, 0), equals(0.0));
      expect(TransferMetrics.calculateEta(100, -10), equals(0.0));
      expect(TransferMetrics.calculateEta(1000, 500), equals(2.0));
    });
  });
}
