// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/robot_command_repository_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The command transport without the view model, against a fake server:
// revisions, retry of a stop, the `table` fallback, debounce and timings.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_umc_control/models/contract_v2.dart';
import 'package:hydra_umc_control/models/robot_command_contract.dart';
import 'package:hydra_umc_control/network/hydra_api_client.dart';
import 'package:hydra_umc_control/state/robot_command_repository.dart';

class _Call {
  _Call(this.robotId, this.payload, this.urgent, this.ifMatch);
  final dynamic robotId;
  final Map<String, dynamic> payload;
  final bool urgent;
  final String? ifMatch;
}

class _FakeServer {
  _FakeServer(this.handler);
  final Map<String, dynamic> Function(_Call call, int n) handler;
  final List<_Call> calls = [];

  Future<Map<String, dynamic>> post(dynamic robotId, Map<String, dynamic> payload, {required bool urgent, String? ifMatch}) async {
    final call = _Call(robotId, Map<String, dynamic>.from(payload), urgent, ifMatch);
    calls.add(call);
    return handler(call, calls.length);
  }
}

Map<String, dynamic> _payload(String command, [Map<String, dynamic>? params]) => {'command': command, 'params': ?params};

RobotCommandRepository _repository({ConditionalMode mode = ConditionalMode.standard, int Function()? nowMs}) =>
    RobotCommandRepository(conditionalMode: () => mode, retryPause: const Duration(milliseconds: 1), nowMs: nowMs);

void main() {
  test('the revision of an answer is sent as If-Match on the next write', () async {
    final repository = _repository();
    final server = _FakeServer((_, n) => {'success': true, 'revision': 'rev$n'});
    await repository.send(1, 'play', _payload('play'), server.post);
    await repository.send(1, 'pause', _payload('pause'), server.post);
    expect(server.calls[0].ifMatch, isNull);
    expect(server.calls[1].ifMatch, '"rev1"');
  });

  test('a stop never carries If-Match and goes out urgent', () async {
    final repository = _repository();
    final server = _FakeServer((_, _) => {'success': true, 'revision': 'r'});
    await repository.send(1, 'play', _payload('play'), server.post);
    await repository.send(1, 'stop', _payload('stop'), server.post);
    expect(server.calls[1].ifMatch, isNull);
    expect(server.calls[1].urgent, isTrue);
    expect(server.calls[0].urgent, isFalse);
  });

  test('a stop is retried when nobody answers but not after an answer of the server', () async {
    final flaky = _FakeServer((_, n) => n < 3 ? throw const SocketException('no route') : {'success': true});
    await _repository().send(1, 'stop', _payload('stop'), flaky.post);
    expect(flaky.calls.length, 3);

    final refusing = _FakeServer((_, _) => throw HydraApiException('refused', statusCode: 403));
    await expectLater(_repository().send(1, 'stop', _payload('stop'), refusing.post), throwsA(isA<HydraApiException>()));
    expect(refusing.calls.length, 1);
  });

  test('an ordinary command is not retried', () async {
    final failing = _FakeServer((_, _) => throw const SocketException('down'));
    await expectLater(_repository().send(1, 'play', _payload('play'), failing.post), throwsA(isA<SocketException>()));
    expect(failing.calls.length, 1);
  });

  test('a mismatch teaches the revision the server is at', () async {
    final repository = _repository();
    final server = _FakeServer((_, n) {
      if (n == 1) return {'success': true, 'revision': 'old'};
      if (n == 2) throw HydraApiException('changed', statusCode: 412, revision: 'new');
      return {'success': true};
    });
    await repository.send(1, 'play', _payload('play'), server.post);
    await expectLater(repository.send(1, 'pause', _payload('pause'), server.post), throwsA(isA<HydraApiException>()));
    expect(repository.revisions.known(1), 'new');
  });

  test('a table move becomes jogs on a server that does not know the command', () async {
    final repository = _repository();
    final server = _FakeServer((call, _) {
      if (call.payload['command'] == 'table') {
        throw HydraApiException('bad', statusCode: 400, serverMessage: 'unknown command: table');
      }
      return {'success': true};
    });
    final params = {'mode': 'relative', 'x': 5.0, 'y': 2.0};
    await repository.send(1, 'table', _payload('table', params), server.post);
    expect(server.calls.map((c) => c.payload['command']).toList(), ['table', 'jog', 'jog']);
    expect(repository.tableCommandSupported, isFalse);
    await repository.send(1, 'table', _payload('table', params), server.post);
    expect(server.calls.length, 5);
    expect(server.calls.skip(3).map((c) => c.payload['command']).toList(), ['jog', 'jog']);
  });

  test('the times of the answers are kept per command', () async {
    var clock = 0;
    final repository = _repository(nowMs: () => clock);
    final server = _FakeServer((_, n) {
      clock += n == 1 ? 40 : 100;
      if (n == 3) throw HydraApiException('down', statusCode: 500);
      return {'success': true};
    });
    await repository.send(1, 'jog', _payload('jog'), server.post);
    await repository.send(1, 'jog', _payload('jog'), server.post);
    await expectLater(repository.send(1, 'jog', _payload('jog'), server.post), throwsA(isA<HydraApiException>()));
    final stats = repository.statsOf('jog')!;
    expect(stats.sent, 3);
    expect(stats.failed, 1);
    expect(stats.lastMs, 100);
    expect(stats.maxMs, 100);
    expect(stats.averageMs, 70);
    expect(repository.statsOf('play'), isNull);
  });

  test('jogs on the wire are counted per robot', () {
    final repository = _repository();
    repository.jogStarted(1);
    repository.jogStarted(1);
    expect(repository.hasJogInFlight(1), isTrue);
    expect(repository.hasJogInFlight(2), isFalse);
    repository.jogEnded(1);
    expect(repository.hasJogInFlight(1), isTrue);
    repository.jogEnded(1);
    repository.jogEnded(1);
    expect(repository.hasJogInFlight(1), isFalse);
  });

  testWidgets('a debounced command is replaced only by the same command', (tester) async {
    final repository = _repository();
    final sent = <String>[];
    unawaited(repository.debounce('speed', const Duration(milliseconds: 300), () async => sent.add('speed-1')));
    await repository.debounce('jog', Duration.zero, () async => sent.add('jog'));
    unawaited(repository.debounce('speed', const Duration(milliseconds: 300), () async => sent.add('speed-2')));
    expect(sent, ['jog']);
    await tester.pump(const Duration(milliseconds: 301));
    expect(sent, ['jog', 'speed-2']);
  });

  testWidgets('cancelling drops what waits', (tester) async {
    final repository = _repository();
    final sent = <String>[];
    unawaited(repository.debounce('speed', const Duration(milliseconds: 300), () async => sent.add('speed')));
    repository.cancelAllPending();
    await tester.pump(const Duration(seconds: 1));
    expect(sent, isEmpty);
  });

  test('the warnings of an answer are joined and an empty list is nothing', () {
    expect(RobotCommandRepository.warningsOf({'success': true}), isNull);
    expect(RobotCommandRepository.warningsOf({'warnings': []}), isNull);
    expect(
      RobotCommandRepository.warningsOf({
        'warnings': [
          {'message': 'speed out of range'},
          'plain',
        ],
      }),
      'speed out of range; plain',
    );
  });

  test('the generated constants agree with the contract file', () {
    final contract = jsonDecode(File('docs/robot_command_contract.json').readAsStringSync()) as Map<String, dynamic>;
    final names = (contract['commands'] as List).map((c) => (c as Map)['name'] as String).toSet();
    expect(RobotCommandContract.all, names);
    expect(RobotCommandContract.numbered, {for (final c in contract['commands'] as List) if ((c as Map)['numbered'] == true) c['name'] as String});
    expect(RobotCommandContract.continuous, {for (final c in contract['commands'] as List) if ((c as Map)['continuous'] == true) c['name'] as String});
    final limits = contract['limits'] as Map;
    expect(RobotCommandContract.speedMin, (limits['speedMin'] as num).toDouble());
    expect(RobotCommandContract.speedMax, (limits['speedMax'] as num).toDouble());
    expect(continuousCommands, RobotCommandContract.continuous);
  });
}
