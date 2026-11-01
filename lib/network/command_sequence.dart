// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - network/command_sequence.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The number this phone puts on its motion commands (`seq`). The server refuses
// a jog whose number is not above the highest one it has seen from the same
// account and controller, and a stop raises that mark, so a jog sent before a
// stop can never move the robot after it. The number grows by at least one with
// every command and follows the clock, so a restarted app starts above
// everything an earlier run sent.
// =============================================================================

import '../models/robot_command_contract.dart';

class CommandSequence {
  CommandSequence._();

  /// The commands the server orders by number: the motion commands and the stop that must overtake them.
  static const Set<String> _numbered = {...RobotCommandContract.numbered, 'joints'};

  static int _last = 0;

  static bool isNumbered(Object? command) => command is String && _numbered.contains(command);

  /// The next number: above the previous one and not below the clock.
  static int next({int Function()? clock}) {
    final now = clock != null ? clock() : DateTime.now().millisecondsSinceEpoch;
    _last = _last + 1 > now ? _last + 1 : now;
    return _last;
  }

  /// Starts over (tests only).
  static void reset() => _last = 0;

  /// [payload] with the next `seq` when it is a numbered command; any other command goes out as it is.
  static Map<String, dynamic> numbered(Map<String, dynamic> payload) =>
      isNumbered(payload['command']) ? {...payload, 'seq': next()} : payload;
}
