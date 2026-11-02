// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/work_files_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The work files (trajectories): the folder, the list, the points and when a work may be loaded into a robot.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:hydra_umc_control/models/robot_command_contract.dart';
import 'package:hydra_umc_control/util/work_files.dart';

String _joints([String extra = '']) => '{"j1":0,"j2":1,"j3":2,"j4":3,"j5":4,"j6":5$extra}';

WorkSituation _ready({
  bool connected = true,
  bool robotOnline = true,
  bool robotEnabled = true,
  bool robotPlaying = false,
  bool stopInProgress = false,
  String? role = 'operator',
  bool tableMissing = false,
  bool serverSupports = true,
}) =>
    WorkSituation(
      connected: connected,
      robotOnline: robotOnline,
      robotEnabled: robotEnabled,
      robotPlaying: robotPlaying,
      stopInProgress: stopInProgress,
      role: role,
      tableMissing: tableMissing,
      serverSupports: serverSupports,
    );

void main() {
  test('the folder is the configured one or the name of the robot without spaces', () {
    expect(WorkFiles.folderFor(null, 1, 'My Robot'), 'WORKS/MyRobot');
    final configured = {'1': 'data/jobs/arm1'};
    expect(WorkFiles.folderFor(configured, 1, 'My Robot'), 'data/jobs/arm1');
    expect(WorkFiles.folderFor(configured, 2, 'Other'), 'WORKS/Other');
  });

  test('a folder that leaves the server is refused', () {
    for (final bad in ['../etc', 'a/../b', 'a//b', r'C:\x', r'a\b', 'x/./y']) {
      expect(WorkFiles.folderFor({'1': bad}, 1, 'R'), isNull, reason: bad);
    }
    expect(WorkFiles.folderFor({'1': 'a' * (RobotCommandContract.worksFolderMax + 1)}, 1, 'R'), isNull);
    expect(WorkFiles.folderFor({'1': '/abs/path/'}, 1, 'R'), 'abs/path');
  });

  test('the index keeps only safe sorted names', () {
    const body = '["b.json", "a.json", "../x.json", "sub/c.json", "no-extension", 7, "a.json", ".hidden.json", "ok_1-2.json"]';
    expect(WorkFiles.parseIndex(body), ['a.json', 'b.json', 'ok_1-2.json']);
    expect(WorkFiles.parseIndex('{"a":1}'), isNull);
    expect(WorkFiles.parseIndex('not json'), isNull);
    expect(WorkFiles.parseIndex('[]'), isEmpty);
  });

  test('a list of points is reduced to the fields the server keeps', () {
    final loaded = WorkFiles.parsePoints('[${_joints(',"x":1.5,"junk":"drop me","y":2,"z":3')}, {"x":1,"y":2,"z":3}]');
    expect(loaded.isOk, isTrue);
    expect(loaded.points, hasLength(2));
    expect(loaded.points![0].containsKey('junk'), isFalse);
    expect(loaded.points![0]['x'], 1.5);
    expect(loaded.usesTable, isFalse);
  });

  test('table points are reported', () {
    expect(WorkFiles.parsePoints('[${_joints(',"tx":4,"ty":5')}]').usesTable, isTrue);
  });

  test('bad files are refused with their reason', () {
    LoadedWork refused(String body) {
      final loaded = WorkFiles.parsePoints(body);
      expect(loaded.isOk, isFalse);
      return loaded;
    }

    expect(refused('nope').problem, WorkProblem.notJson);
    expect(refused('{"points":[]}').problem, WorkProblem.notAList);
    expect(refused('[]').problem, WorkProblem.empty);
    expect(refused('[{"x":1,"y":2}]').problem, WorkProblem.badPoint);
    expect(refused('[${_joints()}, 5]').index, 1);
    expect(refused('[{"x":"1","y":2,"z":3}]').problem, WorkProblem.badPoint);
    expect(refused('[{"x":1,"y":2,"z":3,"motionType":"other"}]').problem, WorkProblem.badPoint);
    expect(refused('[${' ' * RobotCommandContract.worksFileMaxBytes}]').problem, WorkProblem.tooBig);
    expect(WorkFiles.parsePoints('[{"x":1,"y":2,"z":3,"motionType":"model-joints"}]').points!.single['motionType'], 'model-joints');
  });

  test('more than the maximum of points is refused', () {
    const point = '{"x":1,"y":2,"z":3}';
    final body = '[${List.filled(RobotCommandContract.worksMaxPoints + 1, point).join(',')}]';
    expect(WorkFiles.parsePoints(body).problem, WorkProblem.tooManyPoints);
  });

  test('the parameters of the command carry the points and the file name, and never a play', () {
    final points = WorkFiles.parsePoints('[{"x":1,"y":2,"z":3}]').points!;
    final params = WorkFiles.trajectoryParams(points, 'cut_1.json');
    expect(params['selectedWorkFile'], 'cut_1.json');
    expect(params['points'], hasLength(1));
    expect(params.keys.toSet(), {'points', 'selectedWorkFile'});
    expect(() => WorkFiles.trajectoryParams(points, '../cut.json'), throwsArgumentError);
  });

  test('a work is never loaded into a robot that is playing or in safe mode', () {
    expect(WorkFiles.blockOf(_ready()), WorkBlock.none);
    expect(WorkFiles.blockOf(_ready(robotPlaying: true)), WorkBlock.playing);
    expect(WorkFiles.blockOf(_ready(robotEnabled: false)), WorkBlock.safeMode);
    expect(WorkFiles.blockOf(_ready(robotOnline: false)), WorkBlock.offline);
    expect(WorkFiles.blockOf(_ready(connected: false)), WorkBlock.notConnected);
    expect(WorkFiles.blockOf(_ready(stopInProgress: true)), WorkBlock.stopPending);
    expect(WorkFiles.blockOf(_ready(role: 'viewer')), WorkBlock.role);
    expect(WorkFiles.blockOf(_ready(tableMissing: true)), WorkBlock.noTable);
    expect(WorkFiles.blockOf(_ready(serverSupports: false)), WorkBlock.notSupported);
  });
}
