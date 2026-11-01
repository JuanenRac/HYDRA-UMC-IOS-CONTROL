// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/parol6_kinematics_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Expected values come from the original solver of the studio run against the
// same inputs (an oracle outside this code), not from this port itself.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:hydra_umc_control/kinematics/parol6_kinematics.dart';

void main() {
  void expectJoints(List<double> expected, List<double> actual) {
    for (var i = 0; i < expected.length; i++) {
      expect(actual[i], closeTo(expected[i], 1e-3), reason: 'j${i + 1}');
    }
  }

  test('matches the oracle for a straight-ahead reach', () {
    expectJoints([0.0, 0.072990, -0.072819, 0.0, 0.0, 0.0], parol6CartesianToJoints(200, 0, 0, 0, 0, 0));
  });

  test('matches the oracle for a diagonal reach with wrist roll', () {
    expectJoints([33.690068, -4.185567, -2.582369, 0.0, 0.0, 90.0], parol6CartesianToJoints(150, 100, 20, 0, 0, 90));
  });

  test('matches the oracle for a side reach with wrist pitch and yaw', () {
    expectJoints([90.0, -1.573483, 17.459544, 10.0, -10.0, 0.0], parol6CartesianToJoints(0, 200, -50, 10, -10, 0));
  });

  test('matches the oracle at the j1 limit', () {
    expectJoints([97.4, 8.232120, -47.529770, 0.0, 0.0, 0.0], parol6CartesianToJoints(-150, 50, 100, 0, 0, 0));
  });

  test('matches the oracle for a full 6-axis target', () {
    expectJoints([-23.962489, -2.408749, 11.952691, 5.0, 5.0, 5.0], parol6CartesianToJoints(180, -80, -30, 5, 5, 5));
  });

  test('a reachable target is returned unchanged', () {
    expectJoints([0.0, 0.072990, -0.072819, 0.0, 0.0, 0.0], parol6CartesianToJointsOrNull(200, 0, 0, 0, 0, 0)!);
  });

  test('a target far beyond the arm reach is refused', () {
    expect(parol6CartesianToJointsOrNull(5000, 0, 0, 0, 0, 0), isNull);
  });

  test('a target that needs a clamped base angle is refused', () {
    expect(parol6CartesianToJointsOrNull(-150, 50, 100, 0, 0, 0), isNull);
  });
}
