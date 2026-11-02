// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - util/work_files.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Port of HYDRA-UMC-ANDROID-CONTROL's util/WorkFiles.kt: the work files a robot can play. The server keeps them in a
// folder (the robot's own entry of `worksPaths`, or `WORKS/<name of the robot without spaces>`), lists their names in
// `<folder>/index.json` and serves each file as a JSON list of points. The `trajectory` command loads one list into the
// robot. This file only checks what the server sent and builds the parameters of that command: it reads nothing and
// sends nothing, and it never starts a playback. The limits are the server's own and come from
// docs/robot_command_contract.json.
// =============================================================================

import 'dart:convert';

import '../models/robot_command_contract.dart';
import 'dead_man_jog.dart';

/// Why the app does not load a work into a robot; [none] when it may.
enum WorkBlock { none, notConnected, offline, safeMode, playing, stopPending, role, noTable, notSupported }

/// What the app knows when a work is about to be loaded.
class WorkSituation {
  final bool connected;
  final bool robotOnline;
  final bool robotEnabled;

  /// A trajectory is playing (paused or not): loading another would reset it under the robot.
  final bool robotPlaying;
  final bool stopInProgress;
  final String? role;

  /// The file has table points and the robot has no XY table.
  final bool tableMissing;
  final bool serverSupports;

  const WorkSituation({
    required this.connected,
    required this.robotOnline,
    required this.robotEnabled,
    required this.robotPlaying,
    required this.stopInProgress,
    required this.role,
    required this.tableMissing,
    required this.serverSupports,
  });
}

enum WorkProblem { tooBig, notJson, notAList, empty, tooManyPoints, badPoint }

/// The outcome of checking a file: the clean points or the reason it was refused ([index] is the bad point, or -1).
class LoadedWork {
  final List<Map<String, dynamic>>? points;
  final bool usesTable;
  final WorkProblem? problem;
  final int index;

  const LoadedWork.ok(List<Map<String, dynamic>> this.points, this.usesTable)
      : problem = null,
        index = -1;
  const LoadedWork.refused(WorkProblem this.problem, [this.index = -1])
      : points = null,
        usesTable = false;

  bool get isOk => points != null;
}

class WorkFiles {
  WorkFiles._();

  /// The numeric fields a point may carry; the server drops every other one.
  static const List<String> pointFields = ['j1', 'j2', 'j3', 'j4', 'j5', 'j6', 'x', 'y', 'z', 'a', 'b', 'c', 'tx', 'ty', 'trz'];
  static const List<String> _joints = ['j1', 'j2', 'j3', 'j4', 'j5', 'j6'];
  static const List<String> _tableFields = ['tx', 'ty', 'trz'];

  /// A file name the server accepts as `selectedWorkFile`.
  static final RegExp _fileName = RegExp('^[A-Za-z0-9][A-Za-z0-9._-]{0,${RobotCommandContract.worksFileNameMax - 1}}\\.json\$');
  static final RegExp _folder = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_ ./-]*$');

  /// The folder of [robotId]: its entry in [worksPaths] (a JSON object of folder by robot id) or `WORKS/` and its name
  /// without spaces. Null when the folder is not a plain relative path inside the server (no `..`, no leading slash, no
  /// backslash).
  static String? folderFor(Object? worksPaths, dynamic robotId, String robotName) {
    String configured = '';
    if (worksPaths is Map) {
      final value = worksPaths['$robotId'];
      if (value is String) configured = value.trim();
    }
    var folder = configured.isEmpty ? 'WORKS/${robotName.replaceAll(RegExp(r'\s+'), '')}' : configured;
    folder = folder.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    if (folder.isEmpty || folder.length > RobotCommandContract.worksFolderMax) return null;
    if (!_folder.hasMatch(folder) || folder.split('/').any((part) => part.isEmpty || part == '.' || part == '..')) return null;
    return folder;
  }

  /// The safe file names of the index (a JSON list of names); everything else in it is dropped. Null when the text is not a list.
  static List<String>? parseIndex(String body) {
    final Object? list;
    try {
      list = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (list is! List) return null;
    final names = <String>{
      for (final item in list)
        if (item is String && _fileName.hasMatch(item)) item,
    }.toList()
      ..sort();
    return names;
  }

  static bool isSafeFileName(String name) => _fileName.hasMatch(name);

  /// Checks the file the way the server will and reduces each point to the fields it keeps.
  static LoadedWork parsePoints(String body) {
    if (body.length > RobotCommandContract.worksFileMaxBytes) return const LoadedWork.refused(WorkProblem.tooBig);
    final Object? root;
    try {
      root = jsonDecode(body);
    } on FormatException {
      return const LoadedWork.refused(WorkProblem.notJson);
    }
    if (root is! List) return LoadedWork.refused(root is Map ? WorkProblem.notAList : WorkProblem.notJson);
    if (root.isEmpty) return const LoadedWork.refused(WorkProblem.empty);
    if (root.length > RobotCommandContract.worksMaxPoints) return const LoadedWork.refused(WorkProblem.tooManyPoints);
    final clean = <Map<String, dynamic>>[];
    var usesTable = false;
    for (var i = 0; i < root.length; i++) {
      final point = root[i];
      if (point is! Map) return LoadedWork.refused(WorkProblem.badPoint, i);
      final out = <String, dynamic>{};
      for (final field in pointFields) {
        if (!point.containsKey(field)) continue;
        final value = point[field];
        if (value is! num || value.isNaN || value.isInfinite) return LoadedWork.refused(WorkProblem.badPoint, i);
        out[field] = value.toDouble();
      }
      if (point.containsKey('motionType')) {
        if (point['motionType'] != 'model-joints') return LoadedWork.refused(WorkProblem.badPoint, i);
        out['motionType'] = 'model-joints';
      }
      final hasJoints = _joints.every(out.containsKey);
      final hasPose = ['x', 'y', 'z'].every(out.containsKey);
      if (!hasJoints && !hasPose) return LoadedWork.refused(WorkProblem.badPoint, i);
      if (_tableFields.any(out.containsKey)) usesTable = true;
      clean.add(out);
    }
    return LoadedWork.ok(clean, usesTable);
  }

  /// The parameters of the `trajectory` command for [points] loaded from [fileName].
  static Map<String, dynamic> trajectoryParams(List<Map<String, dynamic>> points, String fileName) {
    if (!isSafeFileName(fileName)) throw ArgumentError('unsafe work file name');
    return {'points': points, 'selectedWorkFile': fileName};
  }

  /// The first reason not to load a work, in the order a person can fix them; [WorkBlock.none] when there is none.
  static WorkBlock blockOf(WorkSituation s) {
    if (!s.connected) return WorkBlock.notConnected;
    if (!s.serverSupports) return WorkBlock.notSupported;
    if (!deadManRoleAllowed(s.role)) return WorkBlock.role;
    if (!s.robotOnline) return WorkBlock.offline;
    if (!s.robotEnabled) return WorkBlock.safeMode;
    if (s.stopInProgress) return WorkBlock.stopPending;
    if (s.robotPlaying) return WorkBlock.playing;
    if (s.tableMissing) return WorkBlock.noTable;
    return WorkBlock.none;
  }
}
