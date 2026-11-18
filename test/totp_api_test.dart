// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/totp_api_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The sign-in of an account with the second factor and the five calls of the screen, against a real local dart:io HttpServer: what the request
// carries, what the form is told, and the answers read defensively.
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_umc_control/network/hydra_api_client.dart';
import 'package:hydra_umc_control/network/totp_api.dart';
import 'package:hydra_umc_control/util/totp_rules.dart';

class _Seen {
  final String route;
  final String auth;
  final Map<String, dynamic> body;
  _Seen(this.route, this.auth, this.body);
}

class _Server {
  final HttpServer http;
  final List<_Seen> seen = [];
  // route -> (status, body, headers)
  final Map<String, (int, String, Map<String, String>)> answers = {};

  _Server(this.http) {
    http.listen((request) async {
      final text = await utf8.decoder.bind(request).join();
      final route = '${request.method} ${request.uri.path}';
      Map<String, dynamic> body = {};
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {}
      seen.add(_Seen(route, request.headers.value('authorization') ?? '', body));
      request.response.headers.contentType = ContentType.json;
      final answer = answers[route];
      if (answer == null) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response.statusCode = answer.$1;
        answer.$3.forEach(request.response.headers.set);
        request.response.write(answer.$2);
      }
      await request.response.close();
    });
  }

  static Future<_Server> start() async => _Server(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
  int get port => http.port;
  Future<void> close() => http.close(force: true);
}

void main() {
  late _Server server;
  late HydraApiClient client;

  setUp(() async {
    server = await _Server.start();
    client = HydraApiClient('127.0.0.1', server.port);
    client.authToken = 'tok';
  });

  tearDown(() async {
    client.close();
    await server.close();
  });

  test('the sign-in carries the code only when there is one', () async {
    server.answers['POST /api/login'] = (200, '{"success":true,"token":"t"}', {});
    await client.loginWithCode('ana', 'pw');
    await client.loginWithCode('ana', 'pw', totp: ' 123 456 ');
    final logins = server.seen.where((s) => s.route == 'POST /api/login').toList();
    expect(logins[0].body.containsKey('totp'), isFalse);
    expect(logins[1].body['totp'], '123456');
  });

  test('an account with the second factor asks for the code first', () async {
    server.answers['POST /api/login'] = (401, '{"error":"A second-factor code is required","totpRequired":true}', {});
    await expectLater(
      client.loginWithCode('ana', 'pw'),
      throwsA(isA<SecondFactorRequired>().having((e) => e.wrongCode, 'wrongCode', isFalse).having((e) => e.waitSeconds, 'waitSeconds', isNull)),
    );
    await expectLater(
      client.loginWithCode('ana', 'pw', totp: '000000'),
      throwsA(isA<SecondFactorRequired>().having((e) => e.wrongCode, 'wrongCode', isTrue)),
    );
  });

  test('a wait names the seconds of the server', () async {
    server.answers['POST /api/login'] = (429, '{"error":"Too many","totpRequired":true}', {'Retry-After': '21'});
    await expectLater(
      client.loginWithCode('ana', 'pw', totp: '000000'),
      throwsA(isA<SecondFactorRequired>().having((e) => e.waitSeconds, 'waitSeconds', 21)),
    );
  });

  test('a wrong password is the refusal it always was, not a request for the code', () async {
    server.answers['POST /api/login'] = (401, '{"error":"Invalid credentials"}', {});
    await expectLater(client.loginWithCode('ana', 'bad'), throwsA(isA<HydraApiException>()));
  });

  test('the five calls go to their routes with their bodies', () async {
    server.answers['GET /api/totp/status'] = (200, '{"enabled":true,"recoveryLeft":4}', {});
    server.answers['POST /api/totp/begin'] =
        (200, '{"success":true,"secret":"JBSWY3DPEHPK3PXP","uri":"otpauth://totp/HYDRA:ana?secret=JBSWY3DPEHPK3PXP"}', {});
    server.answers['POST /api/totp/confirm'] = (200, '{"success":true,"recoveryCodes":["0a1b2-c3d4e"]}', {});
    server.answers['POST /api/totp/disable'] = (200, '{"success":true}', {});
    server.answers['POST /api/totp/recovery-codes'] = (200, '{"success":true,"recoveryCodes":["99999-88888"]}', {});
    final api = ClientTotpEndpoint(client);

    expect((await api.status()).recoveryLeft, 4);
    expect((await api.begin('pw')).secret, 'JBSWY3DPEHPK3PXP');
    expect(await api.confirm('123456'), ['0a1b2-c3d4e']);
    await api.disable('pw', '123456');
    expect(await api.newRecoveryCodes('pw', '123456'), ['99999-88888']);

    final calls = server.seen.where((s) => s.route.contains('/api/totp/')).toList();
    expect(calls.map((s) => s.route), [
      'GET /api/totp/status',
      'POST /api/totp/begin',
      'POST /api/totp/confirm',
      'POST /api/totp/disable',
      'POST /api/totp/recovery-codes',
    ]);
    expect(calls.every((s) => s.auth == 'Bearer tok'), isTrue);
    expect(calls[1].body['password'], 'pw');
    expect(calls[4].body['password'], 'pw');
    expect(calls[4].body['code'], '123456');
  });

  test('a refusal is told by its status, its body and its wait', () async {
    final api = ClientTotpEndpoint(client);
    server.answers['GET /api/totp/status'] = (404, '{}', {});
    await expectLater(api.status(), throwsA(isA<TotpException>().having((e) => e.failure, 'failure', const TotpFailure(TotpFailureKind.unsupported))));

    server.answers['POST /api/totp/disable'] = (429, '{"error":"Too many wrong codes"}', {'Retry-After': '17'});
    await expectLater(api.disable('pw', '000000'), throwsA(isA<TotpException>().having((e) => e.failure, 'failure', const TotpFailure(TotpFailureKind.wait, 17))));

    server.answers['POST /api/totp/disable'] = (401, '{"error":"A current code or an unused recovery code is required"}', {});
    await expectLater(api.disable('pw', '000000'), throwsA(isA<TotpException>().having((e) => e.failure, 'failure', const TotpFailure(TotpFailureKind.code))));
  });

  test('an answer without the shape of the contract is a failure, not a crash', () async {
    final api = ClientTotpEndpoint(client);
    server.answers['POST /api/totp/confirm'] = (200, '{"success":true}', {});
    await expectLater(api.confirm('123456'), throwsA(isA<TotpException>().having((e) => e.failure.kind, 'kind', TotpFailureKind.network)));
    server.answers['POST /api/totp/begin'] = (200, '{"success":true,"secret":"short","uri":"otpauth://totp/x"}', {});
    await expectLater(api.begin('pw'), throwsA(isA<TotpException>()));
  });

  test('a server that cannot be reached is the network', () async {
    final api = ClientTotpEndpoint(client);
    await server.close();
    await expectLater(api.status(), throwsA(isA<TotpException>().having((e) => e.failure.kind, 'kind', TotpFailureKind.network)));
  });
}
