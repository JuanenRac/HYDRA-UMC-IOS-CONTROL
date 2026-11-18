// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - network/totp_api.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The calls of the second sign-in factor (SERVER routes /api/totp/status|begin|confirm|disable|recovery-codes) and the sign-in that carries the code.
// They are written by hand on the client of the app because the screens need two things the shared exception of the SDK does not keep: the
// `totpRequired` flag of a refused sign-in and the `Retry-After` of a 429. The key and the codes of the answers are handed to the caller and
// never written anywhere here. The same calls as the Android app (network/TotpEndpoint.kt).
// =============================================================================

import 'dart:convert';

import 'package:hydra_umc_app_common/hydra_umc_app_common.dart' show HttpResponseData;

import '../util/totp_rules.dart';
import 'hydra_api_client.dart';

/// What the second-factor screen needs from the server (the client of the app, a fake in the tests). Every call throws [TotpException] on a refusal.
abstract class TotpEndpoint {
  /// GET /api/totp/status
  Future<TotpStatus> status();

  /// POST /api/totp/begin: a new key, not in force until a code made from it is confirmed.
  Future<TotpEnrolment> begin(String password);

  /// POST /api/totp/confirm: turns the second factor on and returns the one-time recovery codes.
  Future<List<String>> confirm(String code);

  /// POST /api/totp/disable
  Future<void> disable(String password, String code);

  /// POST /api/totp/recovery-codes: replaces the recovery codes and returns the new ones.
  Future<List<String>> newRecoveryCodes(String password, String code);
}

/// What the sign-in last said about the second factor of the account (the form shows the field of the code once it is not [none]).
enum SecondFactorStep { none, needed, wrong, wait }

/// The sign-in said that the account has a second factor (or refused the code that was sent, or asks to wait).
class SecondFactorRequired implements Exception {
  /// True when a code was sent and refused; false when none was sent.
  final bool wrongCode;

  /// Seconds to wait before trying again (a 429), or null.
  final int? waitSeconds;
  const SecondFactorRequired({required this.wrongCode, this.waitSeconds});

  @override
  String toString() => 'SecondFactorRequired(wrongCode: $wrongCode, waitSeconds: $waitSeconds)';
}

Map<String, dynamic> _object(String body) {
  if (body.trim().isEmpty) return const {};
  try {
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : const {};
  } on FormatException {
    return const {};
  }
}

/// The failure a refused answer stands for, read from its status, its body and its `Retry-After`.
TotpFailure totpFailureOf(HttpResponseData resp, {bool needsCodeIfPasswordRefused = false}) {
  final body = _object(resp.body);
  return TotpRules.failureOf(
    resp.statusCode,
    totpRequired: body['totpRequired'] == true,
    retryAfterSeconds: int.tryParse((resp.header('retry-after') ?? '').trim()),
    needsCodeIfPasswordRefused: needsCodeIfPasswordRefused,
    serverMessage: body['error'] is String ? body['error'] as String : null,
  );
}

extension SecondFactorLogin on HydraApiClient {
  /// Signs in. [totp] is the code of the second factor (an app code or a recovery code), sent only when there is one. An account with a second
  /// factor that gets no code, a wrong one or a wait is [SecondFactorRequired]; any other refusal is the [HydraApiException] it always was.
  Future<Map<String, dynamic>> loginWithCode(String username, String password, {String? totp}) async {
    await resolveScheme();
    final code = totp == null ? '' : TotpRules.normalizeCode(totp);
    final resp = await post('/api/login', const Duration(seconds: 15), {
      'username': username,
      'password': password,
      if (code.isNotEmpty) 'totp': code,
    });
    if (resp.statusCode == 401 || resp.statusCode == 429) {
      final body = _object(resp.body);
      if (body['totpRequired'] == true) {
        throw SecondFactorRequired(
          wrongCode: code.isNotEmpty && resp.statusCode == 401,
          waitSeconds: resp.statusCode == 429
              ? (int.tryParse((resp.header('retry-after') ?? '').trim()) ?? TotpRules.defaultWaitSeconds)
              : null,
        );
      }
    }
    return expectJson(resp);
  }
}

/// The five calls of the second factor on the client of the app.
class ClientTotpEndpoint implements TotpEndpoint {
  final HydraApiClient client;
  const ClientTotpEndpoint(this.client);

  static const Duration _timeout = Duration(seconds: 10);

  Future<Map<String, dynamic>> _send(Future<HttpResponseData> Function() request, {bool needsCodeIfPasswordRefused = false}) async {
    final HttpResponseData resp;
    try {
      await client.resolveScheme();
      resp = await request();
    } on Exception {
      throw const TotpException(TotpFailure(TotpFailureKind.network));
    }
    if (resp.statusCode < 200 || resp.statusCode > 299) {
      throw TotpException(totpFailureOf(resp, needsCodeIfPasswordRefused: needsCodeIfPasswordRefused));
    }
    return _object(resp.body);
  }

  TotpException _shape() => const TotpException(TotpFailure(TotpFailureKind.network));

  List<String> _codes(Map<String, dynamic> body) {
    final raw = body['recoveryCodes'];
    if (raw is! List || raw.any((c) => c is! String)) throw _shape();
    final codes = TotpRules.checkedRecoveryCodes(raw.cast<String>());
    if (codes == null) throw _shape();
    return codes;
  }

  @override
  Future<TotpStatus> status() async {
    final body = await _send(() => client.get('/api/totp/status', _timeout));
    final enabled = body['enabled'];
    final left = body['recoveryLeft'];
    if (enabled is! bool) throw _shape();
    return TotpStatus(enabled, left is num && left >= 0 ? left.toInt() : 0);
  }

  @override
  Future<TotpEnrolment> begin(String password) async {
    final body = await _send(() => client.post('/api/totp/begin', _timeout, {'password': password}));
    final secret = body['secret'];
    final uri = body['uri'];
    if (secret is! String || uri is! String) throw _shape();
    return TotpRules.checkedEnrolment(secret, uri) ?? (throw _shape());
  }

  @override
  Future<List<String>> confirm(String code) async =>
      _codes(await _send(() => client.post('/api/totp/confirm', _timeout, {'code': code})));

  @override
  Future<void> disable(String password, String code) async {
    await _send(
      () => client.post('/api/totp/disable', _timeout, {'password': password, 'code': code}),
      needsCodeIfPasswordRefused: true,
    );
  }

  @override
  Future<List<String>> newRecoveryCodes(String password, String code) async => _codes(await _send(
        () => client.post('/api/totp/recovery-codes', _timeout, {'password': password, 'code': code}),
        needsCodeIfPasswordRefused: true,
      ));
}
