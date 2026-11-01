// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - kinematics/parol6_kinematics.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Parol6-specific kinematics: a faithful port of the kinematics of the studio
// (the same 6-step transform chain of the arm description, the same
// Newton-Raphson solve of the shoulder and elbow, the same height offset) and
// the same code as the Android app, so the jog pad moves a Parol6 robot the way
// the floating joystick of the studio does instead of relying on the generic
// formula of the server, which does not follow the real chain of this arm.
//
// Plain 4x4 row-major matrices (M * v, column vectors) are used instead of a 3D
// library: the rotation order is the ROS rpy order, Rz * Ry * Rx, and a step is
// composed as A = A * B (post-multiply).
// =============================================================================

import 'dart:math' as math;

const double _deg = math.pi / 180.0;

class _JointStep {
  final List<double> pos;
  final List<double> rpy;
  final double axisSign;
  const _JointStep(this.pos, this.rpy, this.axisSign);
}

// The chain of the arm in metres and radians as authored in its description.
const List<_JointStep> _parol6Chain = [
  _JointStep([0.0, 0.0, 0.0], [0.0, 0.0, 0.0], 1.0),
  _JointStep([0.0234207210610375, 0.0, 0.1105], [-1.5707963267949, 0.0, 0.0], 1.0),
  _JointStep([0.0, -0.18, 0.0], [3.1416, 0.0, -1.5708], -1.0),
  _JointStep([0.0435, 0.0, 0.0], [1.5707963267949, 0.0, 3.14159265358979], -1.0),
  _JointStep([0.0, 0.0, -0.17635], [-1.5708, 0.0, 0.0], -1.0),
  _JointStep([0.0, 0.0, 0.0], [1.5708, 0.0, 0.0], -1.0),
];

/// The real limits of each joint in degrees.
const Map<String, (double, double)> parol6JointLimitsDeg = {
  'j1': (-97.40, 97.40),
  'j2': (-56.15, 57.30),
  'j3': (-114.59, 74.48),
  'j4': (-114.59, 114.59),
  'j5': (-120.32, 120.32),
  'j6': (-177.62, 177.62),
};

/// The model name under which the server reports this arm.
const String parol6ModelName = 'Parol6 (6-DOF)';

// The height of the tool plane above the base plane, in millimetres.
const double _zOffsetMm = 334.0;

typedef _M4 = List<List<double>>;

_M4 _identity() => List.generate(4, (r) => List.generate(4, (c) => r == c ? 1.0 : 0.0));

_M4 _mul(_M4 a, _M4 b) {
  final out = List.generate(4, (_) => List.filled(4, 0.0));
  for (var i = 0; i < 4; i++) {
    for (var j = 0; j < 4; j++) {
      var s = 0.0;
      for (var k = 0; k < 4; k++) {
        s += a[i][k] * b[k][j];
      }
      out[i][j] = s;
    }
  }
  return out;
}

_M4 _translation(double x, double y, double z) {
  final m = _identity();
  m[0][3] = x;
  m[1][3] = y;
  m[2][3] = z;
  return m;
}

_M4 _rotX(double a) {
  final m = _identity();
  final c = math.cos(a), s = math.sin(a);
  m[1][1] = c;
  m[1][2] = -s;
  m[2][1] = s;
  m[2][2] = c;
  return m;
}

_M4 _rotY(double a) {
  final m = _identity();
  final c = math.cos(a), s = math.sin(a);
  m[0][0] = c;
  m[0][2] = s;
  m[2][0] = -s;
  m[2][2] = c;
  return m;
}

_M4 _rotZ(double a) {
  final m = _identity();
  final c = math.cos(a), s = math.sin(a);
  m[0][0] = c;
  m[0][1] = -s;
  m[1][0] = s;
  m[1][1] = c;
  return m;
}

// ROS rpy = Rz(yaw) * Ry(pitch) * Rx(roll).
_M4 _eulerZYX(double x, double y, double z) => _mul(_mul(_rotZ(z), _rotY(y)), _rotX(x));

// The description is Z-up and the scene of the studio is Y-up: one fix-up rotation at the root.
final _M4 _root = _rotX(-math.pi / 2);

List<double> _fkPosition(List<double> jointsDeg) {
  var m = _root;
  for (var i = 0; i < 6; i++) {
    final step = _parol6Chain[i];
    final t = _translation(step.pos[0], step.pos[1], step.pos[2]);
    final r = _eulerZYX(step.rpy[0], step.rpy[1], step.rpy[2]);
    final jr = _rotZ(step.axisSign * jointsDeg[i] * _deg);
    m = _mul(_mul(_mul(m, t), r), jr);
  }
  return [m[0][3], m[1][3], m[2][3]];
}

// Radius (distance in the horizontal plane) and height for a given shoulder and elbow, holding the other joints at 0.
(double, double) _radiusHeight(double j2, double j3) {
  final p = _fkPosition([0.0, j2, j3, 0.0, 0.0, 0.0]);
  return (math.sqrt(p[0] * p[0] + p[2] * p[2]), p[1]);
}

double _clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

// Newton-Raphson on the two-parameter (shoulder, elbow) -> (radius, height) system, from several seeds and clamped to
// the real limits as a last resort.
(double, double) _solveJ2J3(double targetRadius, double targetHeight) {
  const seeds = [(-30.0, 30.0), (0.0, 0.0), (30.0, -30.0), (-50.0, 60.0), (50.0, -60.0)];
  var bestJ2 = 0.0;
  var bestJ3 = 0.0;
  var bestErr = double.infinity;

  for (final (g2, g3) in seeds) {
    var j2 = g2;
    var j3 = g3;
    var lastErr = double.infinity;
    const h = 0.01;
    for (var iter = 0; iter < 80; iter++) {
      final (r, y) = _radiusHeight(j2, j3);
      final fR = r - targetRadius;
      final fY = y - targetHeight;
      final err = math.sqrt(fR * fR + fY * fY);
      if (err < 1e-7) break;
      if (err > lastErr * 1.5 && iter > 5) break;
      lastErr = err;

      final (r2, y2) = _radiusHeight(j2 + h, j3);
      final (r3, y3) = _radiusHeight(j2, j3 + h);
      final dRdj2 = (r2 - r) / h;
      final dYdj2 = (y2 - y) / h;
      final dRdj3 = (r3 - r) / h;
      final dYdj3 = (y3 - y) / h;
      final det = dRdj2 * dYdj3 - dRdj3 * dYdj2;
      if (det.abs() < 1e-9) break;

      const maxStep = 15.0;
      final dj2 = _clamp((fR * dYdj3 - fY * dRdj3) / det, -maxStep, maxStep);
      final dj3 = _clamp((fY * dRdj2 - fR * dYdj2) / det, -maxStep, maxStep);
      j2 -= dj2;
      j3 -= dj3;
    }
    final (r, y) = _radiusHeight(j2, j3);
    final err = math.sqrt((r - targetRadius) * (r - targetRadius) + (y - targetHeight) * (y - targetHeight));
    if (err < bestErr) {
      bestErr = err;
      bestJ2 = j2;
      bestJ3 = j3;
    }
    if (bestErr < 1e-6) break;
  }

  final j2Limits = parol6JointLimitsDeg['j2']!;
  final j3Limits = parol6JointLimitsDeg['j3']!;
  return (_clamp(bestJ2, j2Limits.$1, j2Limits.$2), _clamp(bestJ3, j3Limits.$1, j3Limits.$2));
}

/// The six joints, in degrees, for a Cartesian target (millimetres, then the three wrist angles in degrees) of the real chain.
List<double> parol6CartesianToJoints(double x, double y, double z, double a, double b, double c) {
  final j1 = math.atan2(y, x) * (180.0 / math.pi);
  final targetRadius = math.sqrt(x * x + y * y) / 1000.0;
  final targetHeight = (z + _zOffsetMm) / 1000.0;
  final (j2, j3) = _solveJ2J3(targetRadius, targetHeight);
  final j1Limits = parol6JointLimitsDeg['j1']!;
  final j4Limits = parol6JointLimitsDeg['j4']!;
  final j5Limits = parol6JointLimitsDeg['j5']!;
  final j6Limits = parol6JointLimitsDeg['j6']!;
  return [
    _clamp(j1, j1Limits.$1, j1Limits.$2),
    j2,
    j3,
    _clamp(a, j4Limits.$1, j4Limits.$2),
    _clamp(b, j5Limits.$1, j5Limits.$2),
    _clamp(c, j6Limits.$1, j6Limits.$2),
  ];
}

/// How far (metres) the arm may land from the requested point before the target counts as out of reach.
const double _reachToleranceM = 0.002;

/// Like [parol6CartesianToJoints], but null when the target cannot be reached: the base angle or the wrist angles fall
/// outside their limits, or the clamped shoulder and elbow end more than a couple of millimetres away from the
/// requested point. The caller refuses the jog instead of sending joints that do not match the position it shows.
List<double>? parol6CartesianToJointsOrNull(double x, double y, double z, double a, double b, double c) {
  final j1 = math.atan2(y, x) * (180.0 / math.pi);
  for (final (name, value) in [('j1', j1), ('j4', a), ('j5', b), ('j6', c)]) {
    final limits = parol6JointLimitsDeg[name]!;
    if (value < limits.$1 || value > limits.$2) return null;
  }
  final joints = parol6CartesianToJoints(x, y, z, a, b, c);
  final (r, h) = _radiusHeight(joints[1], joints[2]);
  final dr = r - math.sqrt(x * x + y * y) / 1000.0;
  final dh = h - (z + _zOffsetMm) / 1000.0;
  return math.sqrt(dr * dr + dh * dh) > _reachToleranceM ? null : joints;
}
