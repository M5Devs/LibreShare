import 'dart:convert';
import 'dart:math';

class ApprovalRequest {
  final String id;
  String status; // 'pending', 'approved', 'rejected', 'consumed'
  final DateTime createdAt;
  final String clientIp;
  final String deviceLabel;

  ApprovalRequest({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.clientIp,
    required this.deviceLabel,
  });

  bool get isExpired => DateTime.now().difference(createdAt).inSeconds > 60;
}

class Session {
  final String id;
  final DateTime createdAt;

  Session({required this.id, required this.createdAt});

  bool get isExpired =>
      DateTime.now().difference(createdAt) > const Duration(hours: 24);
}

class PinValidationResult {
  final bool isValid;
  final bool isLocked;
  final int retryAfterSeconds;

  PinValidationResult({
    required this.isValid,
    this.isLocked = false,
    this.retryAfterSeconds = 0,
  });
}

class SessionManager {
  late final String pairingToken;
  late String _pin;

  String get pin => _pin;

  final Map<String, ApprovalRequest> _approvalRequests = {};
  final Map<String, Session> _sessions = {};

  int _consecutiveFailedPinAttempts = 0;
  int _totalFailedPinAttempts = 0;
  DateTime? _lockedUntil;

  static const int maxPendingApprovals = 3;
  static const int maxActiveSessions = 100;
  static const Duration sessionMaxAge = Duration(hours: 24);

  final Random _random = Random.secure();

  SessionManager({String? pairingTokenOverride, String? pinOverride}) {
    pairingToken = pairingTokenOverride ?? _generateRandomHex(16);
    _pin = pinOverride ?? _generateRandom6DigitPin();
  }

  String _generateRandom6DigitPin() {
    return (_random.nextInt(900000) + 100000).toString();
  }

  void _regeneratePin() {
    _pin = _generateRandom6DigitPin();
    _consecutiveFailedPinAttempts = 0;
    _totalFailedPinAttempts = 0;
    _lockedUntil = null;
  }

  String _generateRandomHex(int bytesCount) {
    final values = List<int>.generate(bytesCount, (_) => _random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  bool _constantTimeEquals(String a, String b) {
    final aBytes = utf8.encode(a);
    final bBytes = utf8.encode(b);
    if (aBytes.length != bBytes.length) return false;
    int result = 0;
    for (int i = 0; i < aBytes.length; i++) {
      result |= aBytes[i] ^ bBytes[i];
    }
    return result == 0;
  }

  bool validateToken(String token) {
    if (token.isEmpty) return false;
    return _constantTimeEquals(token, pairingToken);
  }

  int get remainingLockoutSeconds {
    if (_lockedUntil == null) return 0;
    final diff = _lockedUntil!.difference(DateTime.now()).inSeconds;
    if (diff <= 0) {
      _lockedUntil = null;
      return 0;
    }
    return diff + 1; // Round up to ensure client waits full duration
  }

  PinValidationResult validatePin(String inputPin) {
    final remainingLock = remainingLockoutSeconds;
    if (remainingLock > 0) {
      return PinValidationResult(
        isValid: false,
        isLocked: true,
        retryAfterSeconds: remainingLock,
      );
    }

    if (inputPin.isNotEmpty && _constantTimeEquals(inputPin, _pin)) {
      _consecutiveFailedPinAttempts = 0;
      _totalFailedPinAttempts = 0;
      _lockedUntil = null;
      return PinValidationResult(isValid: true);
    }

    // Failed attempt
    _consecutiveFailedPinAttempts++;
    _totalFailedPinAttempts++;

    if (_totalFailedPinAttempts >= 10) {
      _regeneratePin();
      return PinValidationResult(isValid: false);
    }

    if (_consecutiveFailedPinAttempts >= 5) {
      final exponent = _consecutiveFailedPinAttempts - 5;
      final seconds = (30 * pow(2, exponent)).toInt().clamp(30, 960);
      _lockedUntil = DateTime.now().add(Duration(seconds: seconds));
      return PinValidationResult(
        isValid: false,
        isLocked: true,
        retryAfterSeconds: seconds,
      );
    }

    return PinValidationResult(isValid: false);
  }

  void _cleanExpiredApprovals() {
    _approvalRequests.removeWhere((_, req) => req.isExpired);
  }

  String? createApprovalRequest({String? clientIp, String? deviceLabel}) {
    _cleanExpiredApprovals();

    final pendingCount =
        _approvalRequests.values.where((r) => r.status == 'pending').length;
    if (pendingCount >= maxPendingApprovals) {
      return null;
    }

    final requestId = _generateRandomHex(16);
    _approvalRequests[requestId] = ApprovalRequest(
      id: requestId,
      status: 'pending',
      createdAt: DateTime.now(),
      clientIp: clientIp ?? 'Unknown IP',
      deviceLabel: deviceLabel ?? 'Unknown Device',
    );
    return requestId;
  }

  void approveRequest(String requestId) {
    _cleanExpiredApprovals();
    final req = _approvalRequests[requestId];
    if (req != null && !req.isExpired && req.status == 'pending') {
      req.status = 'approved';
    }
  }

  void rejectRequest(String requestId) {
    _cleanExpiredApprovals();
    final req = _approvalRequests[requestId];
    if (req != null) {
      req.status = 'rejected';
    }
  }

  ApprovalRequest? getApprovalRequest(String requestId) {
    _cleanExpiredApprovals();
    return _approvalRequests[requestId];
  }

  String pollApprovalStatus(String requestId) {
    _cleanExpiredApprovals();
    final req = _approvalRequests[requestId];
    if (req == null || req.isExpired) {
      return 'rejected';
    }

    final currentStatus = req.status;
    if (currentStatus == 'approved') {
      // Single-use: once approved request is polled, consume/invalidate it immediately
      _approvalRequests.remove(requestId);
      return 'approved';
    }

    return currentStatus;
  }

  String getApprovalStatus(String requestId) {
    _cleanExpiredApprovals();
    final req = _approvalRequests[requestId];
    if (req == null || req.isExpired) return 'rejected';
    return req.status;
  }

  bool isApproved(String requestId) {
    _cleanExpiredApprovals();
    final req = _approvalRequests[requestId];
    return req != null && !req.isExpired && req.status == 'approved';
  }

  List<ApprovalRequest> get pendingRequests {
    _cleanExpiredApprovals();
    return _approvalRequests.values
        .where((r) => r.status == 'pending')
        .toList();
  }

  List<String> get pendingRequestIds {
    return pendingRequests.map((r) => r.id).toList();
  }

  void _cleanExpiredSessions() {
    _sessions.removeWhere((_, session) => session.isExpired);
  }

  String createSession() {
    _cleanExpiredSessions();

    if (_sessions.length >= maxActiveSessions) {
      // Evict oldest session
      final oldestKey = _sessions.entries
          .reduce((a, b) => a.value.createdAt.isBefore(b.value.createdAt) ? a : b)
          .key;
      _sessions.remove(oldestKey);
    }

    final sessionCookie = _generateRandomHex(24);
    _sessions[sessionCookie] = Session(
      id: sessionCookie,
      createdAt: DateTime.now(),
    );
    return sessionCookie;
  }

  bool isValidSession(String cookie) {
    if (cookie.isEmpty) return false;
    _cleanExpiredSessions();
    final session = _sessions[cookie];
    if (session == null) return false;
    return !session.isExpired;
  }
}
