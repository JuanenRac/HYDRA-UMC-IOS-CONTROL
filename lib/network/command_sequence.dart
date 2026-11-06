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
//
// The counter itself is in the shared package of the SDK (clients/dart_app_common);
// this class keeps the one counter of the process the app shares between clients.
// =============================================================================

import 'package:hydra_umc_app_common/hydra_umc_app_common.dart' as common;

import '../models/robot_command_contract.dart';

class CommandSequence {
  CommandSequence._();

  /// The commands the server orders by number: the motion commands and the stop that must overtake them.
  static const Set<String> _numbered = {...RobotCommandContract.numbered, 'joints'};

  static int Function()? _clock;

  /// The counter every client of the app uses, so a number is never reused between servers.
  static final common.CommandSequence shared =
      common.CommandSequence(numbered: _numbered, clock: () => _clock != null ? _clock!() : DateTime.now().millisecondsSinceEpoch);

  static bool isNumbered(Object? command) => shared.isNumbered(command);

  /// The next number: above the previous one and not below the clock.
  static int next({int Function()? clock}) {
    _clock = clock;
    try {
      return shared.next();
    } finally {
      _clock = null;
    }
  }

  /// Starts over (tests only).
  static void reset() => shared.reset();

  /// [payload] with the next `seq` when it is a numbered command; any other command goes out as it is.
  static Map<String, dynamic> numbered(Map<String, dynamic> payload) => shared.numbered(payload);
}
