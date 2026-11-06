// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/renewing_client_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The renewal of an expired session through the real client and the package:http
// adapter: one renewal and one repeat for an expired session, nothing for any
// other answer, and no bearer token means no repeat. (The rules themselves are
// replayed from the shared vectors in the SDK package.)
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hydra_umc_control/network/hydra_api_client.dart';

void main() {
  http.Response expired() => http.Response('{"code":"TOKEN_EXPIRED"}', 403);

  HydraApiClient clientOver(MockClient inner, {String? token = 't'}) =>
      HydraApiClient('127.0.0.1', 3000, client: inner)..authToken = token;

  test('an expired token is renewed once and the request repeated with the new one', () async {
    final seen = <String?>[];
    final inner = MockClient((req) async {
      seen.add(req.headers['Authorization']);
      return req.headers['Authorization'] == 'Bearer new' ? http.Response('{"ok":true}', 200) : expired();
    });
    var renewals = 0;
    final client = clientOver(inner, token: 'old')..tokenRenewer = () async { renewals++; return 'new'; };
    final answer = await client.getSystemMetrics();
    expect(answer['ok'], true);
    expect(seen, ['Bearer old', 'Bearer new']);
    expect(renewals, 1);
  });

  test('a 401 is renewed too', () async {
    var calls = 0;
    final inner = MockClient((req) async => ++calls == 1 ? http.Response('', 401) : http.Response('{"fine":1}', 200));
    final client = clientOver(inner, token: 't1')..tokenRenewer = () async => 't2';
    expect((await client.getSystemMetrics())['fine'], 1);
  });

  test('a plain 403 (role) is not renewed and reaches the caller as an error', () async {
    var renewals = 0;
    final inner = MockClient((req) async => http.Response('{"code":"admin-required"}', 403));
    final client = clientOver(inner)..tokenRenewer = () async { renewals++; return 'new'; };
    await expectLater(client.getSystemMetrics(), throwsA(isA<HydraApiException>().having((e) => e.isAdminRequired, 'admin', true)));
    expect(renewals, 0);
  });

  test('a failed renewal returns the original answer', () async {
    final inner = MockClient((req) async => expired());
    final client = clientOver(inner)..tokenRenewer = () async => null;
    await expectLater(client.getSystemMetrics(), throwsA(isA<HydraApiException>().having((e) => e.isSessionProblem, 'session', true)));
  });

  test('a request without a bearer token (login, refresh) is never repeated', () async {
    var calls = 0;
    var renewals = 0;
    final inner = MockClient((req) async { calls++; return http.Response('', 401); });
    final client = clientOver(inner, token: null)..tokenRenewer = () async { renewals++; return 'x'; };
    await expectLater(client.refresh('rt'), throwsA(isA<HydraApiException>()));
    expect(calls, 1);
    expect(renewals, 0);
  });

  test('without a renewer the client is transparent', () async {
    var calls = 0;
    final inner = MockClient((req) async { calls++; return expired(); });
    final client = clientOver(inner);
    await expectLater(client.getSystemMetrics(), throwsA(isA<HydraApiException>()));
    expect(calls, 1);
  });

  test('a renewal that throws returns the original answer', () async {
    final inner = MockClient((req) async => expired());
    final client = clientOver(inner)..tokenRenewer = () async => throw StateError('boom');
    await expectLater(client.getSystemMetrics(), throwsA(isA<HydraApiException>()));
  });
}
