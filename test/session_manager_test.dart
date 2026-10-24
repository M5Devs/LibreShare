import 'package:flutter_test/flutter_test.dart';
import 'package:libreshare/core/server/session_manager.dart';

void main() {
  test('SessionManager generates 6-digit PIN', () {
    final sm = SessionManager();
    expect(sm.pin.length, equals(6));
    final pinNum = int.parse(sm.pin);
    expect(pinNum, greaterThanOrEqualTo(100000));
    expect(pinNum, lessThanOrEqualTo(999999));
  });

  test('PIN validation and rate limiting with exponential backoff', () {
    final sm = SessionManager(pinOverride: '123456');

    for (int i = 0; i < 4; i++) {
      final res = sm.validatePin('000000');
      expect(res.isValid, isFalse);
      expect(res.isLocked, isFalse);
    }

    final lockRes = sm.validatePin('000000');
    expect(lockRes.isValid, isFalse);
    expect(lockRes.isLocked, isTrue);
    expect(lockRes.retryAfterSeconds, greaterThanOrEqualTo(30));

    // Attempt while locked
    final lockedAttempt = sm.validatePin('123456');
    expect(lockedAttempt.isValid, isFalse);
    expect(lockedAttempt.isLocked, isTrue);
  });

  test('Approval protection limits, expiration, and single-use', () {
    final sm = SessionManager();

    final req1 = sm.createApprovalRequest(clientIp: '192.168.1.5', deviceLabel: 'Device 1');
    final req2 = sm.createApprovalRequest(clientIp: '192.168.1.6', deviceLabel: 'Device 2');
    final req3 = sm.createApprovalRequest(clientIp: '192.168.1.7', deviceLabel: 'Device 3');
    final req4 = sm.createApprovalRequest(clientIp: '192.168.1.8', deviceLabel: 'Device 4');

    expect(req1, isNotNull);
    expect(req2, isNotNull);
    expect(req3, isNotNull);
    expect(req4, isNull); // capped at 3 pending requests

    sm.approveRequest(req1!);
    expect(sm.getApprovalStatus(req1), equals('approved'));

    // Single-use check: poll Approval status consumes the request
    final polledStatus = sm.pollApprovalStatus(req1);
    expect(polledStatus, equals('approved'));
    expect(sm.getApprovalStatus(req1), equals('rejected')); // consumed
  });

  test('Session Max-Age and active session limits', () {
    final sm = SessionManager();
    final sessions = <String>[];
    for (int i = 0; i < 105; i++) {
      sessions.add(sm.createSession());
    }

    // Oldest sessions should be evicted beyond 100 max active sessions
    expect(sm.isValidSession(sessions[0]), isFalse);
    expect(sm.isValidSession(sessions[104]), isTrue);
  });
}
