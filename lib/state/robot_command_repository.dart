// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - state/robot_command_repository.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Everything between "the app wants to send this command" and "the server
// answered": the revision (If-Match) of each robot, the retry of a stop, the
// `table` command played as jogs on a server that does not know it, the count
// of jogs still on the wire, the debounce of a command that is sent once the
// control stops moving, and the time each answer took. It holds no widget and
// no ChangeNotifier, so it is tested without the view model. (The same
// responsibilities as RobotCommandRepository of HYDRA-UMC-ANDROID-CONTROL.)
// =============================================================================

import 'dart:async';

import '../models/contract_v2.dart';
import '../models/robot_command_contract.dart';
import '../network/hydra_api_client.dart';

/// How one write reaches the server (the REST client in the app, a fake in the tests).
typedef CommandPoster = Future<Map<String, dynamic>> Function(
  dynamic robotId,
  Map<String, dynamic> payload, {
  required bool urgent,
  String? ifMatch,
});

/// What the repository measured of one command: how many were sent, how many failed and how long the answers took.
class CommandStats {
  const CommandStats({this.sent = 0, this.failed = 0, this.lastMs = 0, this.maxMs = 0, this.totalMs = 0});

  final int sent;
  final int failed;
  final int lastMs;
  final int maxMs;
  final int totalMs;

  int get averageMs => sent - failed > 0 ? totalMs ~/ (sent - failed) : 0;

  CommandStats afterAnswer(int tookMs) => CommandStats(
        sent: sent + 1,
        failed: failed,
        lastMs: tookMs,
        maxMs: tookMs > maxMs ? tookMs : maxMs,
        totalMs: totalMs + tookMs,
      );

  CommandStats afterFailure() => CommandStats(sent: sent + 1, failed: failed + 1, lastMs: lastMs, maxMs: maxMs, totalMs: totalMs);
}

class RobotCommandRepository {
  RobotCommandRepository({
    ConditionalMode Function()? conditionalMode,
    int Function()? nowMs,
    this.retryPause = const Duration(milliseconds: 250),
    this.urgentRetries = 2,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch) {
    revisions = RevisionTracker(conditionalMode);
  }

  final int Function() _nowMs;
  /// The pause before a stop is sent again.
  final Duration retryPause;

  /// How many times a stop is sent again when nobody answers.
  final int urgentRetries;

  /// The last revision seen of each robot.
  late final RevisionTracker revisions;

  /// Whether the server was last seen to understand the `table` command (true until it says otherwise).
  bool tableCommandSupported = true;

  final Map<dynamic, int> _jogsInFlight = {};
  final Map<String, Timer> _pending = {};
  final Map<String, CommandStats> _stats = {};

  /// Counts a jog that is going out; call [jogEnded] when it is answered, whatever the answer.
  void jogStarted(dynamic robotId) => _jogsInFlight[robotId] = (_jogsInFlight[robotId] ?? 0) + 1;

  void jogEnded(dynamic robotId) {
    final left = (_jogsInFlight[robotId] ?? 1) - 1;
    if (left <= 0) {
      _jogsInFlight.remove(robotId);
    } else {
      _jogsInFlight[robotId] = left;
    }
  }

  /// True while a jog of [robotId] is still on the wire.
  bool hasJogInFlight(dynamic robotId) => (_jogsInFlight[robotId] ?? 0) > 0;

  /// Runs [block] after [delay], unless a newer call with the same [key] arrives first. A debounced command is keyed
  /// by its own name: a pending speed change is replaced only by another speed change, never by a jog or a tap.
  /// With a zero [delay] the block runs at once (and still replaces what was waiting under the same key).
  Future<void> debounce(String key, Duration delay, Future<void> Function() block) async {
    _pending.remove(key)?.cancel();
    if (delay > Duration.zero) {
      _pending[key] = Timer(delay, () {
        _pending.remove(key);
        unawaited(block());
      });
    } else {
      await block();
    }
  }

  /// Drops what waits under [key].
  void cancelPending(String key) => _pending.remove(key)?.cancel();

  /// Drops every command that waits for its debounce (when the session ends or the app closes).
  void cancelAllPending() {
    for (final timer in _pending.values) {
      timer.cancel();
    }
    _pending.clear();
  }

  /// Forgets the state of the session: the jogs counted and the commands that wait.
  void reset() {
    cancelAllPending();
    _jogsInFlight.clear();
  }

  /// The numbers measured for [command], or null when none was sent.
  CommandStats? statsOf(String command) => _stats[command];

  /// The numbers of every command sent so far.
  Map<String, CommandStats> allStats() => Map.unmodifiable(_stats);

  /// Sends [payload] (`{"command": ..., "params": ...}`) to [robotId] with the revision this app last saw of it as
  /// If-Match. A `table` move goes out as the jogs that did the same on a server that has no such command. The failure
  /// of the server is rethrown for the caller to report.
  Future<Map<String, dynamic>> send(dynamic robotId, String command, Map<String, dynamic> payload, CommandPoster poster) async {
    final started = _nowMs();
    try {
      final answer = await _postConditionally(robotId, command, payload, poster);
      _stats[command] = (_stats[command] ?? const CommandStats()).afterAnswer(_nowMs() - started);
      return answer;
    } catch (_) {
      _stats[command] = (_stats[command] ?? const CommandStats()).afterFailure();
      rethrow;
    }
  }

  /// A stop is worth retrying: it is posted with short timeouts, and a network failure (no answer at all) is tried
  /// again up to the retries in about a second. An answer from the server, of any kind, is final.
  Future<Map<String, dynamic>> postWithRetry(
    CommandPoster poster,
    dynamic robotId,
    Map<String, dynamic> payload, {
    required bool urgent,
    String? ifMatch,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        return await poster(robotId, payload, urgent: urgent, ifMatch: ifMatch);
      } on HydraApiException {
        rethrow; // the server answered: not a delivery problem
      } catch (_) {
        if (!urgent || attempt >= urgentRetries) rethrow;
      }
      attempt++;
      await Future<void>.delayed(retryPause);
    }
  }

  /// Runs one write with the revision this app last saw of the robot as If-Match (never for STOP, and only when the
  /// mode and the tracker allow it), keeps the revision of the answer for the next write, and on a 412 keeps the one
  /// the server says the robot is at now. The failure is rethrown for the caller to report.
  Future<Map<String, dynamic>> withRevision(
    dynamic robotId,
    String command,
    Future<Map<String, dynamic>> Function(String? ifMatch) call,
  ) async {
    final ticket = revisions.begin(robotId, command);
    try {
      final answer = await call(ticket.ifMatch);
      revisions.finish(robotId, ticket.seq, revisionOf(answer));
      return answer;
    } catch (e) {
      revisions.finish(robotId, ticket.seq, null);
      if (e is HydraApiException && e.isRevisionMismatch) revisions.learn(robotId, e.revision);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _postConditionally(
    dynamic robotId,
    String command,
    Map<String, dynamic> payload,
    CommandPoster poster,
  ) async {
    final params = payload['params'];
    final tableParamsMap = params is Map<String, dynamic> ? params : null;
    if (command == RobotCommandContract.table && !tableCommandSupported && tableParamsMap != null) {
      return _postTableAsJogs(robotId, tableParamsMap, poster);
    }
    try {
      return await withRevision(
        robotId,
        command,
        (ifMatch) => postWithRetry(poster, robotId, payload, urgent: command == RobotCommandContract.stop, ifMatch: ifMatch),
      );
    } on HydraApiException catch (e) {
      if (command == RobotCommandContract.table && tableParamsMap != null && isUnknownCommandAnswer(e.statusCode, e.code, e.serverMessage)) {
        tableCommandSupported = false;
        return _postTableAsJogs(robotId, tableParamsMap, poster);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _postTableAsJogs(dynamic robotId, Map<String, dynamic> params, CommandPoster poster) async {
    Map<String, dynamic> last = {'success': true};
    for (final jog in tableAsJogs(params)) {
      last = await postWithRetry(poster, robotId, {'command': RobotCommandContract.jog, 'params': jog}, urgent: false);
    }
    return last;
  }

  /// The text of the warnings of an answer the server accepted but applied nothing of, or null when there are none.
  static String? warningsOf(Map<String, dynamic> answer) {
    final warnings = answer['warnings'];
    if (warnings is! List || warnings.isEmpty) return null;
    return warnings.map((w) => w is Map && w['message'] is String ? w['message'] as String : '$w').join('; ');
  }
}
