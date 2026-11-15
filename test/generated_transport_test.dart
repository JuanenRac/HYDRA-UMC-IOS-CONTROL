// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/generated_transport_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The requests made through the generated server client keep what the requests
// written by hand had: the headers of the app, the bearer token and its renewal,
// the listen-only gate and the distinct errors of the server; an answer that does
// not fit the contract is an error of the client and never a crash.
// =============================================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hydra_umc_control/generated/hydra_server_client.dart';
import 'package:hydra_umc_control/network/generated_transport.dart';
import 'package:hydra_umc_control/network/hydra_api_client.dart';
import 'package:hydra_umc_control/network/listen_only_gate.dart';

void main() {
  HydraApiClient clientOver(MockClient inner, {String? token = 'tok.en'}) => HydraApiClient('127.0.0.1', 3000, client: inner)..authToken = token;

  group('the push registration over the generated client', () {
    test('POST /api/push/devices carries the body, the client tag and the bearer token', () async {
      late http.Request seen;
      final client = clientOver(MockClient((request) async {
        seen = request;
        return http.Response('{"registered":true}', 200);
      }));
      await client.postPushDevice('abc123', 'es');
      expect('${seen.method} ${seen.url.path}', 'POST /api/push/devices');
      expect(jsonDecode(seen.body), {'token': 'abc123', 'platform': 'ios', 'locale': 'es'});
      expect(seen.headers['Authorization'], 'Bearer tok.en');
      expect(seen.headers['X-Hydra-Client'], startsWith('ios'));
      expect(seen.headers['Content-Type'], contains('application/json'));
    });

    test('DELETE /api/push/devices/{token} encodes the token and sends no body', () async {
      late http.Request seen;
      final client = clientOver(MockClient((request) async {
        seen = request;
        return http.Response('{"removed":true}', 200);
      }));
      await client.deletePushDevice('a/b c');
      expect('${seen.method} ${seen.url.path}', 'DELETE /api/push/devices/a%2Fb%20c');
      expect(seen.body, isEmpty);
      expect(seen.headers['Authorization'], 'Bearer tok.en');
    });

    test('an expired session is renewed once and the request repeated with the new token', () async {
      final seen = <String?>[];
      final inner = MockClient((request) async {
        seen.add(request.headers['Authorization']);
        return request.headers['Authorization'] == 'Bearer new' ? http.Response('{"registered":true}', 200) : http.Response('{"code":"TOKEN_EXPIRED"}', 403);
      });
      var renewals = 0;
      final client = clientOver(inner, token: 'old')
        ..tokenRenewer = () async {
          renewals++;
          return 'new';
        };
      await client.postPushDevice('abc', 'en');
      expect(seen, ['Bearer old', 'Bearer new']);
      expect(renewals, 1);
    });

    test('the refused answers keep their distinct errors', () async {
      Future<HydraApiException> failWith(int status, String body) async {
        final client = clientOver(MockClient((request) async => http.Response(body, status)));
        try {
          await client.postLiveActivity('aa', '1');
        } on HydraApiException catch (e) {
          return e;
        }
        throw StateError('no error');
      }

      expect((await failWith(404, '')).isNotFound, isTrue);
      expect((await failWith(403, '{"code":"admin-required"}')).isAdminRequired, isTrue);
      expect((await failWith(429, '{}')).isRateLimited, isTrue);
      final readOnly = await failWith(423, '{"code":"server-read-only","error":"read only"}');
      expect(readOnly.isServerReadOnly, isTrue);
      expect(readOnly.serverMessage, 'read only');
    });

    test('an answer that does not fit the contract is a client error, not a crash', () async {
      for (final answer in ['{}', '[]', '', 'not json', '{"registered":"yes"}']) {
        final client = clientOver(MockClient((request) async => http.Response(answer, 200)));
        await expectLater(client.postPushDevice('abc', 'en'), throwsA(isA<HydraApiException>()), reason: 'answer "$answer"');
      }
    });

    test('the listen-only gate still stops the write before it leaves', () async {
      var sent = 0;
      final client = clientOver(MockClient((request) async {
        sent++;
        return http.Response('{"registered":true}', 200);
      }));
      ListenOnlyGate.enabled = true;
      addTearDown(() => ListenOnlyGate.enabled = false);
      await expectLater(client.postPushDevice('abc', 'en'), throwsA(isA<HydraApiException>().having((e) => e.statusCode, 'status', 423)));
      expect(sent, 0);
    });
  });

  group('what the transport does not carry yet', () {
    final transport = GeneratedTransport(clientOver(MockClient((request) async => http.Response('{}', 200))));

    test('a body that is not JSON, an answer that is not JSON and response headers are refused', () async {
      await expectLater(transport.send(HydraRequest('POST', '/api/x', const <String, String>{}, null, 'user', contentType: 'application/octet-stream')), throwsUnsupportedError);
      await expectLater(transport.send(HydraRequest('GET', '/api/x', const <String, String>{}, null, 'user', responseType: 'text')), throwsUnsupportedError);
      await expectLater(transport.send(HydraRequest('GET', '/api/x', const <String, String>{}, null, 'user', replyHeaders: const <String>['ETag'])), throwsUnsupportedError);
    });

    test('the query goes into the URL and an empty answer is null', () async {
      Uri? asked;
      final client = clientOver(MockClient((request) async {
        asked = request.url;
        return http.Response('', 200);
      }));
      final answer = await GeneratedTransport(client).send(HydraRequest('GET', '/api/x', const <String, String>{'a': 'b c', 'd': '1'}, null, 'user'));
      expect(answer, isNull);
      expect(asked!.path, '/api/x');
      expect(asked!.queryParameters, {'a': 'b c', 'd': '1'});
    });
  });
}
