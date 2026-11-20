import 'dart:async';

import 'package:http/http.dart' as http;

/// A peer address decoded from a scanned QR code.
class PeerEndpoint {
  const PeerEndpoint({
    required this.host,
    required this.port,
    this.token,
    this.secure = false,
  });

  final String host;
  final int port;

  /// Single-use pairing token, when the QR carried one.
  final String? token;
  final bool secure;

  String get scheme => secure ? 'https' : 'http';

  String get baseUrl => '$scheme://$host:$port';

  /// URL that authenticates this device against the peer in one hop.
  String get pairingUrl {
    final token = this.token;
    return token == null ? baseUrl : '$baseUrl/?t=$token';
  }

  @override
  String toString() => pairingUrl;
}

/// Parses the payload embedded in a LibreShare QR code and verifies that the
/// peer is actually reachable before the UI claims a connection.
class PeerConnector {
  PeerConnector._();

  /// Schemes a LibreShare QR may use. `libreshare://host:port/?t=…` is the
  /// native form; plain http(s) is what the web room advertises.
  static const Set<String> _schemes = {'http', 'https', 'libreshare'};

  static const Duration defaultTimeout = Duration(seconds: 6);

  /// Matches a leading RFC-3986 scheme, e.g. `http:`, `mailto:`, `ftp:`.
  static final RegExp _schemePrefix = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]*):');

  /// A host as it can legitimately appear in a peer address: IPv4, IPv6 in
  /// brackets, or a DNS name. Anything else (spaces, punctuation) is ordinary
  /// QR text and must not be treated as an address.
  static final RegExp _validHost = RegExp(
    r'^(?:\[[0-9a-fA-F:.]+\]|(?:\d{1,3}\.){3}\d{1,3}|[a-zA-Z0-9](?:[a-zA-Z0-9\-_]*[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9\-_]*[a-zA-Z0-9])?)*)$',
  );

  /// Decodes [raw] into a [PeerEndpoint], or null when it is not a peer
  /// address at all (arbitrary QR content must be ignored, not connected to).
  static PeerEndpoint? parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    var candidate = trimmed;
    final schemeMatch = _schemePrefix.firstMatch(trimmed);
    if (schemeMatch != null) {
      final scheme = schemeMatch.group(1)!.toLowerCase();
      final rest = trimmed.substring(schemeMatch.end);
      // `host:port` is indistinguishable from `scheme:` by syntax alone, so a
      // purely numeric remainder is read as a port and the whole string as a
      // bare address. Anything else must name a scheme we actually speak.
      final isHostPort = RegExp(r'^\d+(/|$)').hasMatch(rest);
      if (!isHostPort) {
        if (!_schemes.contains(scheme)) return null;
        if (scheme == 'libreshare') {
          candidate = 'http:${trimmed.substring(schemeMatch.end)}';
        }
      } else {
        candidate = 'http://$trimmed';
      }
    } else {
      candidate = 'http://$trimmed';
    }

    final uri = Uri.tryParse(candidate);
    if (uri == null) return null;
    if (!_schemes.contains(uri.scheme.toLowerCase())) return null;

    final host = uri.host;
    if (host.isEmpty || !_validHost.hasMatch(host)) return null;

    // A dotted quad must be a real address; Uri accepts 999.1.1.1 verbatim.
    if (RegExp(r'^[\d.]+$').hasMatch(host) &&
        host.split('.').any((part) => int.parse(part) > 255)) {
      return null;
    }

    final secure = uri.scheme.toLowerCase() == 'https';
    final port = uri.hasPort ? uri.port : (secure ? 443 : 80);
    if (port <= 0 || port > 65535) return null;

    final token = uri.queryParameters['t'];
    return PeerEndpoint(
      host: host,
      port: port,
      token: (token == null || token.isEmpty) ? null : token,
      secure: secure,
    );
  }

  /// True when the peer answers its health endpoint.
  static Future<bool> probe(
    PeerEndpoint endpoint, {
    http.Client? client,
    Duration timeout = defaultTimeout,
  }) async {
    final owned = client == null;
    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient
          .get(Uri.parse('${endpoint.baseUrl}/api/ping'))
          .timeout(timeout);
      if (response.statusCode != 200) return false;
      return response.body.contains('LibreShare') ||
          response.body.contains('alive');
    } catch (_) {
      return false;
    } finally {
      if (owned) httpClient.close();
    }
  }
}
