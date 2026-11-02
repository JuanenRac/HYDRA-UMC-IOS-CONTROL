// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - util/pairing_link.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Port of HYDRA-UMC-ANDROID-CONTROL's util/PairingLink.kt: what the admin page of the server puts in its QR code: where
// the server is, the fingerprint of its TLS certificate (so the first connection is pinned instead of trusted blindly)
// and a name to show.
//
//     hydra-umc://pair?host=192.168.0.180&port=3000&fp=<64 hex digits>&name=Workshop
//
// This file only reads and checks the text; it connects to nothing and keeps nothing. The camera of the phone can open
// such a link with this app, or the person pastes it; either way the app shows what it read and asks before it keeps
// anything. The limits come from docs/robot_command_contract.json (generated RobotCommandContract).
// =============================================================================

import '../models/robot_command_contract.dart';
import '../network/tls_settings.dart';

/// What a link offers. [fingerprint] is the canonical (lowercase, no separators) SHA-256 of the certificate, or null for
/// a server without TLS.
class PairingOffer {
  final String host;
  final int port;
  final String? fingerprint;
  final String name;
  const PairingOffer(this.host, this.port, this.fingerprint, this.name);

  bool get usesPinning => fingerprint != null;
}

enum PairingProblem {
  empty,
  tooLong,
  notAPairingLink,
  missingHost,
  badHost,
  badPort,
  badFingerprint,
  badName,
  repeatedField,
  badEncoding,
}

/// The result of reading a link: an offer or the reason it was refused.
class PairingResult {
  final PairingOffer? offer;
  final PairingProblem? problem;
  const PairingResult.ok(PairingOffer this.offer) : problem = null;
  const PairingResult.refused(PairingProblem this.problem) : offer = null;

  bool get isOk => offer != null;
}

class PairingLink {
  PairingLink._();

  static const String _prefix = '${RobotCommandContract.pairingScheme}://${RobotCommandContract.pairingHost}';
  static final RegExp _hostName = RegExp(r'^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$');
  static final RegExp _ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');
  static final RegExp _ipv6 = RegExp(r'^[0-9A-Fa-f:]{2,45}$');
  static const Set<String> _known = {'host', 'port', 'fp', 'name'};

  /// True when [text] looks like a pairing link (it may still be refused by [parse]).
  static bool looksLikePairing(String? text) => text != null && text.trim().toLowerCase().startsWith('$_prefix?');

  static PairingResult parse(String? input) {
    final text = (input ?? '').trim();
    if (text.isEmpty) return const PairingResult.refused(PairingProblem.empty);
    if (text.length > RobotCommandContract.pairingMaxPayloadChars) return const PairingResult.refused(PairingProblem.tooLong);
    if (!looksLikePairing(text)) return const PairingResult.refused(PairingProblem.notAPairingLink);
    var query = text.substring(_prefix.length + 1);
    final hash = query.indexOf('#');
    if (hash >= 0) query = query.substring(0, hash);
    final fields = <String, String>{};
    for (final pair in query.split('&')) {
      if (pair.isEmpty) continue;
      final eq = pair.indexOf('=');
      final key = (eq < 0 ? pair : pair.substring(0, eq)).toLowerCase();
      final raw = eq < 0 ? '' : pair.substring(eq + 1);
      final String value;
      try {
        value = Uri.decodeQueryComponent(raw);
      } catch (_) {
        return const PairingResult.refused(PairingProblem.badEncoding);
      }
      // Only the four known fields count; a repeated one is refused so a link cannot say two things.
      if (_known.contains(key)) {
        if (fields.containsKey(key)) return const PairingResult.refused(PairingProblem.repeatedField);
        fields[key] = value;
      }
    }
    var host = (fields['host'] ?? '').trim();
    if (host.startsWith('[')) host = host.substring(1);
    if (host.endsWith(']')) host = host.substring(0, host.length - 1);
    if (host.isEmpty) return const PairingResult.refused(PairingProblem.missingHost);
    if (!_validHost(host)) return const PairingResult.refused(PairingProblem.badHost);
    final portText = (fields['port'] ?? '').trim();
    final port = RegExp(r'^\d{1,5}$').hasMatch(portText) ? int.tryParse(portText) : null;
    if (port == null || port < RobotCommandContract.pairingPortMin || port > RobotCommandContract.pairingPortMax) {
      return const PairingResult.refused(PairingProblem.badPort);
    }
    final fpText = (fields['fp'] ?? '').trim();
    String? fingerprint;
    if (fpText.isNotEmpty) {
      fingerprint = TlsFingerprint.normalize(fpText);
      if (fingerprint == null) return const PairingResult.refused(PairingProblem.badFingerprint);
    }
    final name = (fields['name'] ?? '').trim();
    if (name.runes.length > RobotCommandContract.pairingNameMax || name.runes.any(_isControl)) {
      return const PairingResult.refused(PairingProblem.badName);
    }
    return PairingResult.ok(PairingOffer(host, port, fingerprint, name.isEmpty ? host : name));
  }

  static bool _isControl(int rune) => rune < 0x20 || (rune >= 0x7f && rune <= 0x9f);

  static bool _validHost(String host) {
    final v4 = _ipv4.firstMatch(host);
    if (v4 != null) return [for (var i = 1; i <= 4; i++) int.parse(v4.group(i)!)].every((n) => n >= 0 && n <= 255);
    if (host.contains(':')) return _ipv6.hasMatch(host);
    return _hostName.hasMatch(host);
  }
}
