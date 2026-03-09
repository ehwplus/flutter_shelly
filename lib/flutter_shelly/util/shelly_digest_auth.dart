import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

class ShellyDigestAuthChallenge {
  const ShellyDigestAuthChallenge({required this.realm, required this.nonce});

  final String realm;
  final String nonce;
}

class ShellyDigestAuth {
  static Map<String, dynamic> build({
    required String username,
    required String password,
    required ShellyDigestAuthChallenge challenge,
    String? cnonce,
    Random? random,
  }) {
    final resolvedCnonce = cnonce ?? _randomHex(16, random: random);
    final ha1 = _sha256('$username:${challenge.realm}:$password');
    final response = _sha256('$resolvedCnonce:${challenge.nonce}:$ha1');

    return {
      'realm': challenge.realm,
      'username': username,
      'nonce': challenge.nonce,
      'cnonce': resolvedCnonce,
      'response': response,
      'algorithm': 'SHA-256',
    };
  }

  static ShellyDigestAuthChallenge? tryParse(dynamic errorPayload) {
    final map = _asMap(errorPayload);
    final data = _asMap(map['data']);

    final nonce = _firstNonEmpty([
      data['nonce']?.toString(),
      map['nonce']?.toString(),
      _extractByRegex(
        map['message']?.toString(),
        RegExp(r'nonce\s*[:=]\s*"?([A-Za-z0-9]+)"?'),
      ),
      _extractByRegex(
        map['message']?.toString(),
        RegExp(r'nonce\s+([A-Za-z0-9]+)'),
      ),
    ]);

    if (nonce == null) {
      return null;
    }

    final realm =
        _firstNonEmpty([
          data['realm']?.toString(),
          map['realm']?.toString(),
          _extractByRegex(
            map['message']?.toString(),
            RegExp(r'realm\s*[:=]\s*"?([A-Za-z0-9_-]+)"?'),
          ),
        ]) ??
        'shelly';

    return ShellyDigestAuthChallenge(realm: realm, nonce: nonce);
  }

  static String _sha256(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  static String _randomHex(int length, {Random? random}) {
    final resolvedRandom = random ?? Random.secure();
    const chars = '0123456789abcdef';
    final buffer = StringBuffer();
    for (var index = 0; index < length; index += 1) {
      buffer.write(chars[resolvedRandom.nextInt(chars.length)]);
    }
    return buffer.toString();
  }

  static String? _extractByRegex(String? value, RegExp regex) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final match = regex.firstMatch(value);
    return match?.group(1);
  }

  static String? _firstNonEmpty(List<String?> candidates) {
    for (final candidate in candidates) {
      if (candidate != null && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    return null;
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const {};
  }
}
