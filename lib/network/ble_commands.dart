// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - network/ble_commands.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// BLE commands and their acknowledgements. A command is the body of
// POST /api/robot/{id}/command with the robot id, an `id` the answer carries
// back and the access token of the account; the peripheral hands it to the same
// route a Wi-Fi client uses, so it gets no privilege of its own.
// =============================================================================

import 'dart:convert';
import 'dart:typed_data';

class BleCommandRequest {
  final dynamic robotId;
  final String command;
  final Map<String, dynamic> params;
  final String? controllerId;
  final String token;
  const BleCommandRequest({
    required this.robotId,
    required this.command,
    this.params = const {},
    this.controllerId,
    required this.token,
  });
}

/// The acknowledgement of the peripheral. [ok] only when the route of the server answered with a 2xx status.
class BleAck {
  /// The id of the command; null when the peripheral could not read it (a damaged message).
  final String? id;
  final bool ok;

  /// The HTTP status of the route; 0 when the command never reached it.
  final int status;

  /// A stable word: `ok`, `claimed`, `forbidden`, `rate-limited`, `commands-disabled`, `unreachable`...
  final String code;
  final String? error;
  const BleAck({required this.id, required this.ok, required this.status, required this.code, this.error});
}

/// What became of a command sent over Bluetooth. Only [BleAcknowledged] says anything about the robot.
sealed class BleCommandOutcome {
  const BleCommandOutcome();
}

/// The peripheral answered; look at [BleAck.ok].
class BleAcknowledged extends BleCommandOutcome {
  final BleAck ack;
  const BleAcknowledged(this.ack);
}

/// Nothing answered in time or the link dropped: the command must be treated as NOT delivered.
class BleNoAnswer extends BleCommandOutcome {
  const BleNoAnswer();
}

/// The link was not ready, or the device offers no ACK characteristic: nothing was sent.
class BleNotAvailable extends BleCommandOutcome {
  const BleNotAvailable();
}

/// The command did not fit in one message (64 KiB): nothing was sent.
class BleTooLarge extends BleCommandOutcome {
  const BleTooLarge();
}

class BleCommands {
  BleCommands._();

  /// Longest `id` the peripheral accepts.
  static const int maxIdChars = 64;

  /// How long a command waits for its acknowledgement before it counts as not delivered.
  static const Duration defaultAckTimeout = Duration(seconds: 4);

  /// The message the peripheral reads: UTF-8 JSON.
  static Uint8List encode(String id, BleCommandRequest request) {
    final body = <String, dynamic>{
      'id': id,
      'robotId': request.robotId,
      'command': request.command,
      'params': request.params,
      'token': request.token,
      if (request.controllerId != null && request.controllerId!.isNotEmpty) 'controllerId': request.controllerId,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(body)));
  }

  /// The acknowledgement in a message of the ACK characteristic; null when it is not one (never throws).
  static BleAck? parseAck(List<int> bytes) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      return null;
    }
    if (json is! Map<String, dynamic>) return null;
    if (json['ok'] is! bool) return null;
    final id = json['id'];
    final status = json['status'];
    final code = json['code'];
    final error = json['error'];
    return BleAck(
      id: id is String ? id : null,
      ok: json['ok'] as bool,
      status: status is num ? status.toInt() : 0,
      code: code is String ? code : '',
      error: error is String && error.isNotEmpty ? error : null,
    );
  }
}
