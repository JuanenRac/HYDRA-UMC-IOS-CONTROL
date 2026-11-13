// =============================================================================
// HYDRA-UMC iOS (Flutter) - test/hydra_state_views_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The thin views over the state the server sends, as this app uses them through the shared package: what an answer
// that says nothing reads as, the module flags, the manufacturer of each model, the playback markers the setters write,
// the controllers and the active one. The Android app tests the same views; where the two differ the test says so.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_umc_control/models/hydra_state.dart';

RobotView _robot([Map<String, dynamic>? raw]) => RobotView(raw ?? <String, dynamic>{});

void main() {
  test('an empty robot reads as offline, enabled and generic', () {
    final r = _robot();
    expect(r.online, isFalse);
    expect(r.isEnabled, isTrue);
    expect(r.manufacturer, 'Generic');
    expect(r.name, 'Robot null');
    expect(r.model, 'Generic (6-DOF)');
    expect(r.role, 'Idle');
    expect(r.tool, 'None');
    for (final flag in [r.hasXYTable, r.hasPnP, r.hasCNC, r.hasLaser, r.hasHeatedBed, r.hasVacuumTable, r.hasCamera, r.hasAtc, r.hasRack]) {
      expect(flag, isFalse);
    }
    expect(r.speed, 100.0);
    expect(r.acceleration, 100.0);
    expect(r.combinedWith, isEmpty);
    expect(r.jogStep, isNull);
    expect(r.controllerBoard, isNull);
    expect(r.urtcHead, isNull);
    expect(r.urtcExpansion, isNull);
  });

  test('the manufacturer follows the model', () {
    const expected = {
      'Parol6': 'Source Robotics',
      'Faze4': 'Source Robotics',
      'AR3': 'Annin Robotics',
      'AR4': 'Annin Robotics',
      'UR5e': 'Universal Robots',
      'xArm 6': 'UFACTORY',
      'Lite 6': 'UFACTORY',
      'Gen3': 'Kinova',
      'Gen2': 'Kinova',
      'ViperX 300': 'Trossen Robotics',
      'WidowX': 'Trossen Robotics',
      'e.DO': 'Comau',
      'Z1': 'Unitree',
      'PiPER': 'AgileX',
      'Something else': 'Generic',
    };
    expected.forEach((model, maker) {
      expect(_robot({'model': model}).manufacturer, maker, reason: model);
    });
  });

  test('a module counts only when its own flag is on', () {
    final on = _robot({
      'juanenPnP': {'enabled': true},
      'juanenCNC': {'enabled': true},
      'juanenLaser': {'enabled': true},
      'heatedBed': {'enabled': true},
      'vacuumTable': {'enabled': true},
      'rackSystem': {'enabled': true},
      'atc': <String, dynamic>{},
    });
    expect([on.hasPnP, on.hasCNC, on.hasLaser, on.hasHeatedBed, on.hasVacuumTable, on.hasRack, on.hasAtc], everyElement(isTrue));
    final off = _robot({'juanenPnP': {'enabled': false}, 'juanenCNC': <String, dynamic>{}, 'heatedBed': 'yes'});
    expect([off.hasPnP, off.hasCNC, off.hasHeatedBed], everyElement(isFalse));
    expect(_robot({'lumenPnP': {'enabled': true}}).hasPnP, isTrue);
  });

  test('the camera counts when vision is on or the paired camera is connected', () {
    expect(_robot({'visionEnabled': true}).hasCamera, isTrue);
    expect(_robot({'camera': {'connected': true}}).hasCamera, isTrue);
    expect(_robot({'camera': {'connected': false}}).hasCamera, isFalse);
    expect(_robot({'cameraView': {'x': 1}}).hasCamera, isFalse);
  });

  test(
    'PENDING (the shared package, not this app): visionEnabled false wins over a stale connected camera, as on Android',
    () {
      expect(_robot({'visionEnabled': false, 'camera': {'connected': true}}).hasCamera, isFalse);
    },
    skip: 'The shared package ORs the two fields; the Android app lets visionEnabled decide when the server sends it. '
        'Fixing it means a change in the SDK package and a new pin.',
  );

  test('the setters write into the raw map and the readers give the numbers back', () {
    final r = _robot();
    r.setOnline(true);
    r.setTool('Gripper');
    r.setValve(1, true);
    r.setPump(0, true);
    r.setJoint('j3', 45.0);
    r.setPosAxis('x', 12.5);
    r.setXyTableAxis('x', 3.0);
    r.setEnabled(false);
    expect(r.online, isTrue);
    expect(r.tool, 'Gripper');
    expect(r.valves[1], isTrue);
    expect(r.pumps[0], isTrue);
    expect(r.joint('j3'), 45.0);
    expect(r.joint('j9'), 0.0);
    expect(r.posAxis('x'), 12.5);
    expect(r.posAxis('y'), 0.0);
    expect(r.xyTablePos['x'], 3.0);
    expect(r.isEnabled, isFalse);
  });

  test('a whole number from the server reads as a double and a word reads as zero', () {
    final r = _robot({'joints': {'j1': 0, 'j2': 'x'}, 'pos': {'x': 5}});
    expect(r.joint('j1'), 0.0);
    expect(r.joint('j2'), 0.0);
    expect(r.posAxis('x'), 5.0);
  });

  test('the jog step of the server is read only when it is a positive finite number', () {
    expect(_robot({'jogStep': 2.5}).jogStep, 2.5);
    expect(_robot({'jogStep': 0}).jogStep, isNull);
    expect(_robot({'jogStep': -1}).jogStep, isNull);
    expect(_robot({'jogStep': double.nan}).jogStep, isNull);
    expect(_robot({'jogStep': 'big'}).jogStep, isNull);
  });

  test('the jog step offered is the nearest one, and the fallback when the server has none', () {
    const steps = [0.1, 1.0, 5.0, 10.0];
    expect(_robot({'jogStep': 4.0}).jogStepOr(1.0, steps), 5.0);
    expect(_robot({'jogStep': 0.4}).jogStepOr(1.0, steps), 0.1);
    expect(_robot().jogStepOr(1.0, steps), 1.0);
    expect(_robot({'jogStep': 4.0}).jogStepOr(7.0, const []), 7.0);
  });

  test('starting playback clears the pause and the finished markers', () {
    final r = _robot({'playbackState': {'isPaused': true, 'paused': true, 'isFinished': true, 'finished': true}});
    r.setPlaying(true);
    expect(r.isPlaying, isTrue);
    expect(r.isPaused, isFalse);
    expect(r.playbackState['isFinished'], isFalse);
    expect(r.playbackState['activeStep'], 0);
    expect(r.playbackState['requestStop'], isFalse);
  });

  test('stopping playback asks the browser to stop too', () {
    final r = _robot();
    r.setPlaying(true);
    r.setPaused(true);
    expect(r.isPaused, isTrue);
    expect(r.playbackState['requestPause'], isTrue);
    r.stop();
    expect(r.isPlaying, isFalse);
    expect(r.isPaused, isFalse);
    expect(r.playbackState['requestStop'], isTrue);
    expect(r.playbackState['activeStep'], -1);
    r.setPlaying(false);
    expect(r.playbackState['isFinished'], isFalse);
    expect(r.playbackState['activeStep'], -1);
  });

  test('the toggle pauses and resumes without leaving playback', () {
    final r = _robot();
    r.togglePaused();
    expect(r.isPaused, isTrue);
    expect(r.isPlaying, isTrue);
    r.togglePaused();
    expect(r.isPaused, isFalse);
    expect(r.isPlaying, isTrue);
  });

  test('speed and acceleration are kept in the playback state', () {
    final r = _robot();
    r.setSpeed(40.0);
    r.setAcceleration(25.0);
    expect(r.speed, 40.0);
    expect(r.acceleration, 25.0);
    expect(_robot({'playbackState': {'speed': 'fast'}}).speed, 100.0);
  });

  test('the robots combined with this one are the numbers of the list', () {
    expect(_robot({'combinedWith': [2, 3.0, 'x']}).combinedWith, [2, 3]);
    expect(_robot({'combinedWith': 'x'}).combinedWith, isEmpty);
  });

  test('the text of a robot names its identity', () {
    expect(_robot({'id': 4, 'name': 'Arm', 'online': true}).toString(), 'RobotView(id=4, name=Arm, online=true)');
  });

  test('a controller lists its robots, skips what is not an object and finds one by id', () {
    final c = ControllerView({
      'id': 'c1',
      'robots': [{'id': 1}, {'id': 2}, 'x'],
      'cameras': [{'id': 'cam'}, 5],
    });
    expect(c.id, 'c1');
    expect(c.name, 'c1');
    expect(c.ip, '');
    expect(c.robots.length, 2);
    expect(c.robotById(2)?.id, 2);
    expect(c.robotById(9), isNull);
    expect(c.cameras.length, 1);
    expect(ControllerView(<String, dynamic>{}).robots, isEmpty);
    expect(ControllerView(<String, dynamic>{}).cameras, isEmpty);
  });

  test('the state finds the active controller, or the first one, and its robots', () {
    final state = HydraState({
      'activeControllerId': 'b',
      'controllers': [
        {'id': 'a', 'robots': [{'id': 1}]},
        {'id': 'b', 'robots': [{'id': 2}, {'id': 3}]},
      ],
    });
    expect(state.activeController?.id, 'b');
    expect(state.robotById(3)?.id, 3);
    expect(state.robotById(1), isNull);
    expect(state.toJson(), same(state.raw));

    final unknown = HydraState({
      'activeControllerId': 'zzz',
      'controllers': [{'id': 'a', 'robots': [{'id': 1}]}],
    });
    expect(unknown.activeController?.id, 'a');
    expect(unknown.robotById(1)?.id, 1);
  });

  test('the empty state has no controllers and no active one', () {
    final state = HydraState();
    expect(state.controllers, isEmpty);
    expect(state.activeController, isNull);
    expect(state.robotById(1), isNull);
    expect(state.activeControllerId, '');
  });
}
