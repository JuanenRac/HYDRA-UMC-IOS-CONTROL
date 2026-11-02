// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - util/link_health.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Port of HYDRA-UMC-ANDROID-CONTROL's util/LinkHealth.kt: keeps the last round-trip times measured towards the server
// and says how good the link is. It holds no network and no clock besides the one it is given, so it is tested on the
// Dart VM. The limits come from docs/robot_command_contract.json through the generated RobotCommandContract.
//
// The level follows the SLOWEST of the recent samples, not the average: one answer that took half a second is what a
// held jog would have felt, and an average would hide it.
// =============================================================================

import '../models/robot_command_contract.dart';

enum LinkLevel { unknown, good, poor, bad, lost }

class LinkLimits {
  final int window;
  final int goodRttMs;
  final int poorRttMs;
  final int blockRttMs;
  final int lostAfterMs;

  const LinkLimits({
    this.window = RobotCommandContract.linkSampleWindow,
    this.goodRttMs = RobotCommandContract.linkGoodRttMs,
    this.poorRttMs = RobotCommandContract.linkPoorRttMs,
    this.blockRttMs = RobotCommandContract.linkBlockRttMs,
    this.lostAfterMs = RobotCommandContract.linkLostAfterMs,
  }) : assert(window >= 1 && goodRttMs >= 1 && goodRttMs <= poorRttMs && poorRttMs <= blockRttMs && lostAfterMs > 0);
}

class LinkHealth {
  LinkHealth({this.limits = const LinkLimits(), DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final LinkLimits limits;
  final DateTime Function() _clock;
  final List<int> _samples = [];
  DateTime? _lastAnswerAt;
  int _failures = 0;

  /// A probe (or any answered request) took [rttMs].
  void record(int rttMs) {
    _samples.add(rttMs < 0 ? 0 : rttMs);
    while (_samples.length > limits.window) {
      _samples.removeAt(0);
    }
    _lastAnswerAt = _clock();
    _failures = 0;
  }

  /// A probe got no answer.
  void recordFailure() => _failures++;

  /// Forgets everything (a new connection).
  void reset() {
    _samples.clear();
    _lastAnswerAt = null;
    _failures = 0;
  }

  /// The slowest of the recent samples, or null before the first one.
  int? get worstMs => _samples.isEmpty ? null : _samples.reduce((a, b) => a > b ? a : b);

  /// The last sample, or null before the first one.
  int? get lastMs => _samples.isEmpty ? null : _samples.last;

  LinkLevel get level {
    if (_failures >= 2) return LinkLevel.lost;
    if (_samples.isEmpty) return _failures > 0 ? LinkLevel.lost : LinkLevel.unknown;
    if (_clock().difference(_lastAnswerAt!).inMilliseconds > limits.lostAfterMs) return LinkLevel.lost;
    final worst = worstMs!;
    if (worst < limits.goodRttMs) return LinkLevel.good;
    if (worst < limits.poorRttMs) return LinkLevel.poor;
    return LinkLevel.bad;
  }

  /// True when the continuous jog must not start (or must stop): the slowest recent answer reached the blocking time,
  /// or the server has not answered for too long. An unknown link (nothing measured yet) does not block by itself.
  bool get blocksJog {
    if (level == LinkLevel.lost) return true;
    return (worstMs ?? 0) >= limits.blockRttMs;
  }
}
