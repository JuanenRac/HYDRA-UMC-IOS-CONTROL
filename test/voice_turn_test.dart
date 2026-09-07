// =============================================================================
// HYDRA-UMC-IOS-CONTROL - test/voice_turn_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
//
// HydraApiClient.postVoiceTurn() - real coverage against a real local
// dart:io HttpServer, not a mocked http.Client - same "real local server"
// convention as test/hydra_websocket_reconnect_test.dart. Confirms the real
// request shape (POST /api/voice/turn, X-Hydra-Client: ios, real JSON body)
// and that a real reply round-trips through AssistantReply.fromJson().
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:hydra_umc_control/network/hydra_api_client.dart';

void main() {
  late HttpServer server;
  late HydraApiClient client;
  Map<String, dynamic>? lastBody;
  String? lastClientHeader;

  setUp(() async {
    lastBody = null;
    lastClientHeader = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = HydraApiClient('127.0.0.1', server.port);
  });

  tearDown(() async {
    client.close();
    await server.close(force: true);
  });

  Future<void> serveOnce(int statusCode, Map<String, dynamic> body) async {
    final request = await server.first;
    lastClientHeader = request.headers.value('x-hydra-client');
    final raw = await utf8.decoder.bind(request).join();
    lastBody = raw.isEmpty ? null : jsonDecode(raw) as Map<String, dynamic>;
    request.response.statusCode = statusCode;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  test('sends the real POST with the real voice_turn wire shape and client identity', () async {
    final future = client.postVoiceTurn('status for robot 1', 'en-US');
    await serveOnce(200, {
      'type': 'assistant_reply',
      'requestId': 'ignored',
      'text': 'Robot 1 is idle.',
      'level': 'INFO',
      'speak': true,
      'requiresConfirmation': false,
    });
    final reply = await future;

    expect(reply.text, 'Robot 1 is idle.');
    expect(reply.level, 'INFO');
    expect(reply.speak, isTrue);
    expect(reply.requiresConfirmation, isFalse);
    expect(lastBody?['type'], 'voice_turn');
    expect(lastBody?['transcript'], 'status for robot 1');
    expect(lastBody?['locale'], 'en-US');
    expect(lastBody?['requestId'], isA<String>());
    expect(lastClientHeader, 'ios');
  });

  test('a requiresConfirmation reply round-trips correctly', () async {
    final future = client.postVoiceTurn('stop all robots', 'en-US');
    await serveOnce(200, {
      'type': 'assistant_reply',
      'requestId': 'ignored',
      'text': 'Confirm stopping all robots?',
      'level': 'ATTENTION',
      'speak': true,
      'requiresConfirmation': true,
    });
    final reply = await future;

    expect(reply.requiresConfirmation, isTrue);
    expect(reply.level, 'ATTENTION');
  });

  test('a server error surfaces as a real HydraApiException, never a silent success', () async {
    final future = client.postVoiceTurn('status for robot 1', 'en-US');
    // Attached before the awaited gap below - a Future that rejects with no
    // listener yet registers as an unhandled zone error in the test runner,
    // independent of whether expectLater would have matched it once it got
    // there.
    final expectation = expectLater(future, throwsA(isA<HydraApiException>()));
    await serveOnce(502, {'error': 'HYDRA-UMC-VOICE-UI rejected the voice turn'});
    await expectation;
  });
}
