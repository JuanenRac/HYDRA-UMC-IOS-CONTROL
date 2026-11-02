// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - util/watch_relay.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Port of HYDRA-UMC-ANDROID-CONTROL's wear/WatchBridge.kt: what the watch sends the phone to pass on to the server, the
// presence heartbeat of the operator and the second tap of the two-step confirmation of a spoken order. The phone only
// passes them on, each behind its own switch (both off by default); the server decides what a lost heartbeat means and
// still requires the session and the reservation of the robot for a confirmation. PENDING in HYDRA-UMC-SERVER: the two
// endpoints, so a server that does not have them answers 404 and the relay goes quiet.
// =============================================================================

import '../models/robot_command_contract.dart';

/// Paths of the messages the watch sends the phone besides the stop request.
class WatchRelayKeys {
  WatchRelayKeys._();
  static const String presence = 'presence';
  static const String voiceConfirm = 'voiceConfirm';
}

/// The presence of the operator, as the watch sends it every few seconds while the operator has switched it on.
class WatchPresenceHeartbeat {
  static const int protocolVersion = 1;
  static const int maxIntervalSeconds = 60;

  final int sequence;
  final int intervalSeconds;
  final bool left;

  WatchPresenceHeartbeat({required this.sequence, required this.intervalSeconds, required this.left, int version = protocolVersion}) {
    if (version != protocolVersion) throw ArgumentError('unsupported presence protocol version');
    if (sequence < 0 || intervalSeconds < 1 || intervalSeconds > maxIntervalSeconds) {
      throw ArgumentError('presence needs a sequence from 0 and an interval from 1 to $maxIntervalSeconds seconds');
    }
  }

  /// Reads the message of the watch; throws [ArgumentError] when it is not a valid heartbeat.
  factory WatchPresenceHeartbeat.fromMap(Map<dynamic, dynamic> map) {
    if (map['type'] != 'presence_heartbeat') throw ArgumentError('unexpected presence message type');
    final state = map['state'] ?? 'PRESENT';
    if (state != 'PRESENT' && state != 'LEFT') throw ArgumentError('presence state must be PRESENT or LEFT');
    final sequence = map['sequence'];
    final interval = map['intervalSeconds'];
    final version = map['protocolVersion'] ?? protocolVersion;
    if (sequence is! num || interval is! num || version is! num) throw ArgumentError('presence numbers are missing');
    return WatchPresenceHeartbeat(
      sequence: sequence.toInt(),
      intervalSeconds: interval.toInt(),
      left: state == 'LEFT',
      version: version.toInt(),
    );
  }

  /// The body for the server: the heartbeat plus how many the phone did not receive since the last one.
  Map<String, dynamic> toServerJson(int missed) => {
        'type': 'presence_heartbeat',
        'protocolVersion': protocolVersion,
        'sequence': sequence,
        'intervalSeconds': intervalSeconds,
        'state': left ? 'LEFT' : 'PRESENT',
        'missed': missed,
      };
}

/// Counts the heartbeats of the watch that never reached the phone, from the gaps in their sequence numbers.
class WatchPresenceTracker {
  int? _last;

  /// How many heartbeats were lost before this one (0 for the first, after a restart of the counter of the watch, or for a repeat).
  int onHeartbeat(WatchPresenceHeartbeat heartbeat) {
    final before = _last;
    _last = heartbeat.sequence;
    return before == null || heartbeat.sequence <= before ? 0 : heartbeat.sequence - before - 1;
  }

  void reset() => _last = null;
}

/// The second tap of the two-step confirmation of a spoken order. The watch cannot move a robot: the phone sends this to the
/// server only when it has a session, and the server requires the reservation of the robot as for any command.
class WatchVoiceConfirm {
  static final RegExp _requestId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
  static final RegExp _token = RegExp('^[A-Za-z0-9._~+/=-]{16,${RobotCommandContract.voiceConfirmTokenMax}}\$');

  final String requestId;
  final String confirms;
  final String confirmationToken;

  WatchVoiceConfirm({required this.requestId, required this.confirms, required this.confirmationToken}) {
    if (!_requestId.hasMatch(requestId) || !_requestId.hasMatch(confirms)) throw ArgumentError('invalid voice confirmation request id');
    if (!_token.hasMatch(confirmationToken)) throw ArgumentError('invalid confirmation token');
  }

  factory WatchVoiceConfirm.fromMap(Map<dynamic, dynamic> map) {
    if (map['type'] != 'voice_confirm') throw ArgumentError('unexpected voice confirmation type');
    final id = map['requestId'];
    final confirms = map['confirms'];
    final token = map['confirmationToken'];
    if (id is! String || confirms is! String || token is! String) throw ArgumentError('voice confirmation fields are missing');
    return WatchVoiceConfirm(requestId: id, confirms: confirms, confirmationToken: token);
  }

  /// True when [token] has the form the watch accepts.
  static bool isValidToken(String token) => _token.hasMatch(token);

  Map<String, dynamic> toServerJson() => {
        'type': 'voice_confirm',
        'requestId': requestId,
        'confirms': confirms,
        'confirmationToken': confirmationToken,
      };

  /// Never print the token: it is a one-use secret.
  @override
  String toString() => 'WatchVoiceConfirm(requestId=$requestId, confirms=$confirms)';
}
