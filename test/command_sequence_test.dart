// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/command_sequence_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The number on the wire: motion commands carry a rising `seq`, other commands
// none, and a 409 stale-sequence is its own refusal (not a reservation). Real
// local dart:io HttpServer, no mocked client.
// =============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:hydra_umc_control/l10n/app_localizations.dart';
import 'package:hydra_umc_control/network/command_sequence.dart';
import 'package:hydra_umc_control/network/hydra_api_client.dart';
import 'package:hydra_umc_control/state/hydra_error.dart';

void main() {
  late HttpServer server;
  late HydraApiClient client;
  final bodies = <Map<String, dynamic>>[];
  int status = 200;
  Map<String, dynamic> answer = {};

  setUp(() async {
    CommandSequence.reset();
    bodies.clear();
    status = 200;
    answer = {};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final raw = await utf8.decoder.bind(request).join();
      bodies.add(jsonDecode(raw) as Map<String, dynamic>);
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(answer));
      await request.response.close();
    });
    client = HydraApiClient('127.0.0.1', server.port)..authToken = 'tok';
  });

  tearDown(() async {
    client.close();
    await server.close(force: true);
  });

  test('the number grows by at least one and never falls below the clock', () {
    final first = CommandSequence.next(clock: () => 1000);
    final second = CommandSequence.next(clock: () => 1000);
    final third = CommandSequence.next(clock: () => 5000);
    expect(first, 1000);
    expect(second, 1001);
    expect(third, 5000);
    expect(CommandSequence.isNumbered('jog'), isTrue);
    expect(CommandSequence.isNumbered('table'), isTrue);
    expect(CommandSequence.isNumbered('joints'), isTrue);
    expect(CommandSequence.isNumbered('stop'), isTrue);
    expect(CommandSequence.isNumbered('home'), isFalse);
    expect(CommandSequence.isNumbered(null), isFalse);
  });

  test('a jog then a stop carry rising numbers and a home carries none', () async {
    await client.postRobotCommand(1, {'command': 'jog'});
    await client.postRobotCommand(1, {'command': 'stop'});
    await client.postRobotCommand(1, {'command': 'home'});
    expect(bodies[1]['seq'] as int, greaterThan(bodies[0]['seq'] as int));
    expect(bodies[2].containsKey('seq'), isFalse);
  });

  test('a 409 stale-sequence is not taken for a reservation', () async {
    status = 409;
    answer = {'error': 'stale', 'code': 'stale-sequence', 'lastSeq': 9};
    try {
      await client.postRobotCommand(1, {'command': 'jog'});
      fail('expected a HydraApiException');
    } on HydraApiException catch (e) {
      expect(e.isStaleSequence, isTrue);
      expect(e.statusCode, 409);
    }
  });

  test('the refusal has its own wording in every language and names the command', () async {
    for (final code in ['en', 'es', 'de', 'fr', 'it', 'ja', 'zh', 'pt']) {
      final l10n = await AppLocalizations.delegate.load(Locale(code));
      final text = const HydraError(HydraErrorKind.staleSequence, {'command': 'jog'}).localize(l10n);
      expect(text, contains('jog'), reason: code);
    }
  });
}
