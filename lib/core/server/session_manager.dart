import 'dart:math';

class SessionManager {
  late final String pairingToken;
  late final String pin;

  final Map<String, String> _approvalRequests = {};
  final Set<String> _validSessions = {};

  final Random _random = Random.secure();

  SessionManager({String? pairingTokenOverride, String? pinOverride}) {
    pairingToken = pairingTokenOverride ?? _generateRandomHex(16);
    pin = pinOverride ?? (_random.nextInt(9000) + 1000).toString();
  }

  String _generateRandomHex(int bytesCount) {
    final values = List<int>.generate(bytesCount, (_) => _random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  bool validateToken(String token) {
    if (token.isEmpty) return false;
    return token == pairingToken;
  }

  bool validatePin(String inputPin) {
    if (inputPin.isEmpty) return false;
    return inputPin == pin;
  }

  String createApprovalRequest() {
    final requestId = _generateRandomHex(16);
    _approvalRequests[requestId] = 'pending';
    return requestId;
  }

  void approveRequest(String requestId) {
    if (_approvalRequests.containsKey(requestId)) {
      _approvalRequests[requestId] = 'approved';
    }
  }

  void rejectRequest(String requestId) {
    if (_approvalRequests.containsKey(requestId)) {
      _approvalRequests[requestId] = 'rejected';
    }
  }

  String getApprovalStatus(String requestId) {
    return _approvalRequests[requestId] ?? 'rejected';
  }

  bool isApproved(String requestId) {
    return _approvalRequests[requestId] == 'approved';
  }

  List<String> get pendingRequestIds => _approvalRequests.entries
      .where((e) => e.value == 'pending')
      .map((e) => e.key)
      .toList();

  String createSession() {
    final sessionCookie = _generateRandomHex(24); // 192 bits = 24 bytes
    _validSessions.add(sessionCookie);
    return sessionCookie;
  }

  bool isValidSession(String cookie) {
    if (cookie.isEmpty) return false;
    return _validSessions.contains(cookie);
  }
}
