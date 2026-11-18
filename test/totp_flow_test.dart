// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/totp_flow_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The second-factor screen as a state machine, with a fake server: turning it on, the codes shown once, new codes, turning it off, and every
// refusal. The same cases as the Android app (TotpFlowTest).
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_umc_control/network/totp_api.dart';
import 'package:hydra_umc_control/state/totp_flow.dart';
import 'package:hydra_umc_control/util/totp_rules.dart';

const _key = 'JBSWY3DPEHPK3PXP';
const _codes = ['0a1b2-c3d4e', '11111-22222', '33333-44444'];

class _Fake implements TotpEndpoint {
  bool enabled;
  int left;
  TotpException? refuse;
  String key;
  final List<String> calls = [];

  _Fake({this.enabled = false, this.left = 0, this.refuse, this.key = ''});

  void _maybeRefuse() {
    final r = refuse;
    if (r != null) throw r;
  }

  @override
  Future<TotpStatus> status() async {
    calls.add('status');
    _maybeRefuse();
    return TotpStatus(enabled, left);
  }

  @override
  Future<TotpEnrolment> begin(String password) async {
    calls.add('begin:$password');
    _maybeRefuse();
    final enrolment = TotpRules.checkedEnrolment(key, 'otpauth://totp/HYDRA:ana?secret=$key');
    if (enrolment == null) throw const TotpException(TotpFailure(TotpFailureKind.network));
    return enrolment;
  }

  @override
  Future<List<String>> confirm(String code) async {
    calls.add('confirm:$code');
    _maybeRefuse();
    return _codes;
  }

  @override
  Future<void> disable(String password, String code) async {
    calls.add('disable:$password:$code');
    _maybeRefuse();
  }

  @override
  Future<List<String>> newRecoveryCodes(String password, String code) async {
    calls.add('new:$password:$code');
    _maybeRefuse();
    return _codes;
  }
}

TotpException _refusal(TotpFailureKind kind, [int? number]) => TotpException(TotpFailure(kind, number));

void main() {
  test('it reads the status when it opens', () async {
    final api = _Fake(enabled: true, left: 7);
    final flow = TotpFlow(() => api);
    await flow.load();
    expect(flow.step, TotpStep.on);
    expect(flow.recoveryLeft, 7);
    expect(flow.busy, isFalse);
  });

  test('turning it on goes through the key, then the code, then the recovery codes', () async {
    final api = _Fake(key: _key);
    final flow = TotpFlow(() => api);
    await flow.load();
    expect(flow.step, TotpStep.off);

    await flow.begin('pw');
    expect(flow.step, TotpStep.enrolling);
    expect(flow.secret, _key);
    expect(flow.showsSecret, isTrue);

    await flow.confirm(' 123 456 ');
    expect(flow.step, TotpStep.recovery);
    expect(flow.recoveryCodes, _codes);
    expect(api.calls.last, 'confirm:123456');

    flow.acknowledgeRecovery();
    expect(flow.step, TotpStep.on);
    expect(flow.notice, TotpNotice.turnedOn);
    expect(flow.recoveryLeft, 3);
    expect(flow.recoveryCodes, isEmpty);
    expect(flow.secret, '');
    expect(flow.uri, '');
  });

  test('giving up before confirming drops the key', () async {
    final flow = TotpFlow(() => _Fake(key: _key));
    await flow.load();
    await flow.begin('pw');
    flow.cancelEnrolment();
    expect(flow.step, TotpStep.off);
    expect(flow.secret, '');
    expect(flow.showsSecret, isFalse);
  });

  test('a key of another form is not shown', () async {
    final flow = TotpFlow(() => _Fake(key: 'short'));
    await flow.load();
    await flow.begin('pw');
    expect(flow.step, TotpStep.off);
    expect(flow.failure, const TotpFailure(TotpFailureKind.network));
    expect(flow.secret, '');
  });

  test('few recovery codes left warns and new codes are shown once more', () async {
    final api = _Fake(enabled: true, left: 1);
    final flow = TotpFlow(() => api);
    await flow.load();
    expect(flow.recoveryLow, isTrue);

    await flow.newRecoveryCodes('pw', '654321');
    expect(flow.step, TotpStep.recovery);
    expect(flow.recoveryCodes, _codes);
    expect(api.calls.last, 'new:pw:654321');

    flow.acknowledgeRecovery();
    expect(flow.notice, TotpNotice.newCodes);
    expect(flow.recoveryLeft, 3);
    expect(flow.recoveryLow, isFalse);
    expect(flow.recoveryCodes, isEmpty);
  });

  test('turning it off needs the password and a code', () async {
    final api = _Fake(enabled: true, left: 5);
    final flow = TotpFlow(() => api);
    await flow.load();
    await flow.disable('', '123456');
    await flow.disable('pw', '  ');
    expect(api.calls, ['status']);

    await flow.disable('pw', '123 456');
    expect(api.calls.last, 'disable:pw:123456');
    expect(flow.step, TotpStep.off);
    expect(flow.notice, TotpNotice.turnedOff);
  });

  test('a refusal keeps the step and says why', () async {
    final api = _Fake(enabled: true, left: 5);
    final flow = TotpFlow(() => api);
    await flow.load();
    api.refuse = _refusal(TotpFailureKind.code);
    await flow.disable('pw', '000000');
    expect(flow.failure, const TotpFailure(TotpFailureKind.code));
    expect(flow.step, TotpStep.on);
    expect(flow.busy, isFalse);
  });

  test('an older server says so and a limit says how long', () async {
    final api = _Fake(refuse: _refusal(TotpFailureKind.unsupported));
    final flow = TotpFlow(() => api);
    await flow.load();
    expect(flow.step, TotpStep.unsupported);
    expect(flow.failure, const TotpFailure(TotpFailureKind.unsupported));

    api.refuse = _refusal(TotpFailureKind.wait, 20);
    await flow.load();
    expect(flow.failure, const TotpFailure(TotpFailureKind.wait, 20));
  });

  test('without a server nothing is called and the failure is the network', () async {
    final flow = TotpFlow(() => null);
    await flow.begin('pw');
    expect(flow.failure, const TotpFailure(TotpFailureKind.network));
    expect(flow.busy, isFalse);
    flow.dismissMessages();
    expect(flow.failure, isNull);
  });

  test('closing the screen drops the key and the codes', () async {
    final flow = TotpFlow(() => _Fake(key: _key));
    await flow.load();
    await flow.begin('pw');
    await flow.confirm('123456');
    flow.clear();
    expect(flow.step, TotpStep.loading);
    expect(flow.recoveryCodes, isEmpty);
    expect(flow.secret, '');
  });

  test('a key or code never reaches the text of the flow', () async {
    final flow = TotpFlow(() => _Fake(key: _key));
    await flow.load();
    await flow.begin('pw');
    await flow.confirm('123456');
    expect(flow.toString().contains(_key), isFalse);
    expect(flow.toString().contains('0a1b2'), isFalse);
  });
}
