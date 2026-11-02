// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/session_manager_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The renewal of an expired session without the view model: one renewal at a
// time, one repeat of the request, and every other answer left as it came.
// =============================================================================

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_umc_control/network/hydra_api_client.dart';
import 'package:hydra_umc_control/state/session_manager.dart';

HydraApiClient _client() => HydraApiClient('127.0.0.1', 3000);

HydraApiException _expired() => HydraApiException('expired', statusCode: 403, code: 'TOKEN_EXPIRED');

void main() {
  test('without a client the call is refused before anything is sent', () async {
    final manager = SessionManager(client: () => null, renew: () async => true);
    expect(manager.authed((c) async => 1), throwsA(isA<HydraApiException>()));
  });

  test('a good call is not renewed', () async {
    var renewals = 0;
    final manager = SessionManager(client: _client, renew: () async { renewals++; return true; });
    expect(await manager.authed((c) async => 7), 7);
    expect(renewals, 0);
  });

  test('an expired token renews once and repeats the call once', () async {
    var renewals = 0;
    var calls = 0;
    final manager = SessionManager(client: _client, renew: () async { renewals++; return true; });
    final value = await manager.authed((c) async {
      calls++;
      if (calls == 1) throw _expired();
      return 'ok';
    });
    expect(value, 'ok');
    expect(renewals, 1);
    expect(calls, 2);
  });

  test('a failed renewal hands the original error to the caller', () async {
    final manager = SessionManager(client: _client, renew: () async => false);
    var calls = 0;
    await expectLater(
      manager.authed((c) async { calls++; throw _expired(); }),
      throwsA(isA<HydraApiException>().having((e) => e.code, 'code', 'TOKEN_EXPIRED')),
    );
    expect(calls, 1);
  });

  test('a repeat that fails again is not renewed a second time', () async {
    var renewals = 0;
    final manager = SessionManager(client: _client, renew: () async { renewals++; return true; });
    var calls = 0;
    await expectLater(manager.authed((c) async { calls++; throw _expired(); }), throwsA(isA<HydraApiException>()));
    expect(calls, 2);
    expect(renewals, 1);
  });

  test('a plain permission refusal or a server error is never renewed', () async {
    var renewals = 0;
    final manager = SessionManager(client: _client, renew: () async { renewals++; return true; });
    await expectLater(
      manager.authed((c) async => throw HydraApiException('no', statusCode: 403, code: 'FORBIDDEN')),
      throwsA(isA<HydraApiException>()),
    );
    await expectLater(manager.authed((c) async => throw HydraApiException('boom', statusCode: 500)), throwsA(isA<HydraApiException>()));
    expect(renewals, 0);
  });

  test('requests that notice the expiry together share one renewal', () async {
    var renewals = 0;
    final gate = Completer<bool>();
    final manager = SessionManager(client: _client, renew: () { renewals++; return gate.future; });
    final seen = <int>[];
    Future<void> run(int id) async {
      var first = true;
      await manager.authed((c) async {
        if (first) { first = false; throw _expired(); }
        seen.add(id);
        return id;
      });
    }
    final all = Future.wait([run(1), run(2), run(3)]);
    await Future<void>.delayed(Duration.zero);
    expect(manager.renewing, isTrue);
    gate.complete(true);
    await all;
    expect(renewals, 1);
    expect(seen.toSet(), {1, 2, 3});
    expect(manager.renewing, isFalse);
  });

  test('a later expiry starts a new renewal', () async {
    var renewals = 0;
    final manager = SessionManager(client: _client, renew: () async { renewals++; return true; });
    for (var i = 0; i < 2; i++) {
      var first = true;
      await manager.authed((c) async {
        if (first) { first = false; throw _expired(); }
        return 1;
      });
    }
    expect(renewals, 2);
  });
}
