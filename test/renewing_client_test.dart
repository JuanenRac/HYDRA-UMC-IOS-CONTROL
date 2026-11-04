// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/renewing_client_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The interceptor over http.Client: one renewal and one repeat for an expired
// session, nothing for any other answer, and no bearer token means no repeat.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hydra_umc_control/network/renewing_client.dart';

void main() {
  http.Response expired() => http.Response('{"code":"TOKEN_EXPIRED"}', 403);

  test('an expired token is renewed once and the request repeated with the new one', () async {
    final seen = <String?>[];
    final inner = MockClient((req) async {
      seen.add(req.headers['Authorization']);
      return req.headers['Authorization'] == 'Bearer new' ? http.Response('{"ok":true}', 200) : expired();
    });
    var renewals = 0;
    final client = RenewingClient(inner, () => () async { renewals++; return 'new'; });
    final resp = await client.post(Uri.parse('http://x/api/a'),
        headers: {'Authorization': 'Bearer old'}, body: '{"n":1}');
    expect(resp.statusCode, 200);
    expect(resp.body, '{"ok":true}');
    expect(seen, ['Bearer old', 'Bearer new']);
    expect(renewals, 1);
  });

  test('a 401 is renewed too', () async {
    var calls = 0;
    final inner = MockClient((req) async => ++calls == 1 ? http.Response('', 401) : http.Response('fine', 200));
    final client = RenewingClient(inner, () => () async => 't2');
    expect((await client.get(Uri.parse('http://x/'), headers: {'Authorization': 'Bearer t1'})).body, 'fine');
  });

  test('a plain 403 (role) is not renewed and its body reaches the caller', () async {
    var renewals = 0;
    final inner = MockClient((req) async => http.Response('{"code":"admin-required"}', 403));
    final client = RenewingClient(inner, () => () async { renewals++; return 'new'; });
    final resp = await client.get(Uri.parse('http://x/'), headers: {'Authorization': 'Bearer t'});
    expect(resp.statusCode, 403);
    expect(resp.body, '{"code":"admin-required"}');
    expect(renewals, 0);
  });

  test('a failed renewal returns the original answer', () async {
    final inner = MockClient((req) async => expired());
    final client = RenewingClient(inner, () => () async => null);
    final resp = await client.get(Uri.parse('http://x/'), headers: {'Authorization': 'Bearer t'});
    expect(resp.statusCode, 403);
    expect(resp.body, '{"code":"TOKEN_EXPIRED"}');
  });

  test('a request without a bearer token (login, refresh) is never repeated', () async {
    var calls = 0;
    var renewals = 0;
    final inner = MockClient((req) async { calls++; return http.Response('', 401); });
    final client = RenewingClient(inner, () => () async { renewals++; return 'x'; });
    expect((await client.post(Uri.parse('http://x/login'), body: '{}')).statusCode, 401);
    expect(calls, 1);
    expect(renewals, 0);
  });

  test('without a renewer the client is transparent', () async {
    var calls = 0;
    final inner = MockClient((req) async { calls++; return expired(); });
    final client = RenewingClient(inner, () => null);
    expect((await client.get(Uri.parse('http://x/'), headers: {'Authorization': 'Bearer t'})).statusCode, 403);
    expect(calls, 1);
  });

  test('a renewal that throws returns the original answer', () async {
    final inner = MockClient((req) async => expired());
    final client = RenewingClient(inner, () => () async => throw StateError('boom'));
    expect((await client.get(Uri.parse('http://x/'), headers: {'Authorization': 'Bearer t'})).statusCode, 403);
  });
}
