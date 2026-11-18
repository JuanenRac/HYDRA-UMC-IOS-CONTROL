// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - state/totp_flow.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The second factor of the signed-in account as a small state machine, away from the screen so it is tested without a device with a fake
// endpoint: read the status, turn it on (password, then the key, then the first code, then the one-time recovery codes), turn it off (password and
// a code) and make new recovery codes (password and a code). The same steps and states as the Android app (viewmodel/TotpFlow.kt).
//
// The key and the codes live here only while the person is looking at them: they are dropped when the step ends, are never written to a log or a
// store, and toString leaves them out.
// =============================================================================

import 'package:flutter/foundation.dart';

import '../network/totp_api.dart';
import '../util/totp_rules.dart';

/// The steps of the second-factor screen of the signed-in account.
enum TotpStep { loading, unsupported, off, enrolling, recovery, on }

/// What the screen says after a step went well (the screen turns each into its translated text).
enum TotpNotice { turnedOn, turnedOff, newCodes }

class TotpFlow extends ChangeNotifier {
  /// [endpoint] is read at every call because the client changes with the session.
  TotpFlow(this._endpoint);

  final TotpEndpoint? Function() _endpoint;

  TotpStep step = TotpStep.loading;
  int recoveryLeft = 0;
  String secret = '';
  String uri = '';
  List<String> recoveryCodes = const [];
  bool busy = false;
  TotpFailure? failure;
  TotpNotice? notice;
  bool _disposed = false;

  /// The warning to offer new recovery codes: the account has the second factor and few codes left.
  bool get recoveryLow => step == TotpStep.on && TotpRules.recoveryLow(recoveryLeft);

  /// True while a key or a list of codes is held, so the screen can hide it when the app leaves the foreground.
  bool get showsSecret => step == TotpStep.enrolling || step == TotpStep.recovery;

  void _reset({TotpStep step = TotpStep.loading, int recoveryLeft = 0, TotpNotice? notice}) {
    this.step = step;
    this.recoveryLeft = recoveryLeft;
    secret = '';
    uri = '';
    recoveryCodes = const [];
    this.notice = notice;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Reads the status; the screen calls it when it opens.
  Future<void> load() async {
    _reset();
    failure = null;
    await _run((api) async {
      final status = await api.status();
      _reset(step: status.enabled ? TotpStep.on : TotpStep.off, recoveryLeft: status.recoveryLeft < 0 ? 0 : status.recoveryLeft);
    });
  }

  /// First step of turning it on: the password asks the server for a new key.
  Future<void> begin(String password) async {
    if (password.isEmpty) return;
    await _run((api) async {
      final enrolment = await api.begin(password);
      step = TotpStep.enrolling;
      secret = enrolment.secret;
      uri = enrolment.uri;
    });
  }

  /// The person gives up before confirming: the key is dropped (the server keeps nothing in force until a code is confirmed).
  void cancelEnrolment() {
    _reset(step: TotpStep.off, recoveryLeft: recoveryLeft);
    _changed();
  }

  /// Second step: the first code made from the key turns the second factor on and brings the recovery codes.
  Future<void> confirm(String code) async {
    final clean = TotpRules.normalizeCode(code);
    if (clean.isEmpty) return;
    await _run((api) async {
      final codes = await api.confirm(clean);
      _reset(step: TotpStep.recovery, recoveryLeft: codes.length);
      recoveryCodes = codes;
    });
  }

  /// The person says the recovery codes are saved: they are dropped for good, the screen goes back to the status.
  void acknowledgeRecovery() {
    final again = step == TotpStep.recovery && notice == TotpNotice.newCodes;
    _reset(step: TotpStep.on, recoveryLeft: recoveryLeft, notice: again ? TotpNotice.newCodes : TotpNotice.turnedOn);
    _changed();
  }

  /// Turns the second factor off with the password and a current or recovery code.
  Future<void> disable(String password, String code) async {
    final clean = TotpRules.normalizeCode(code);
    if (password.isEmpty || clean.isEmpty) return;
    await _run((api) async {
      await api.disable(password, clean);
      _reset(step: TotpStep.off, notice: TotpNotice.turnedOff);
    });
  }

  /// Makes a new set of recovery codes (the old ones stop working); the codes are shown once, like the first set.
  Future<void> newRecoveryCodes(String password, String code) async {
    final clean = TotpRules.normalizeCode(code);
    if (password.isEmpty || clean.isEmpty) return;
    await _run((api) async {
      final codes = await api.newRecoveryCodes(password, clean);
      _reset(step: TotpStep.recovery, recoveryLeft: codes.length, notice: TotpNotice.newCodes);
      recoveryCodes = codes;
    });
  }

  /// Drops everything held (the screen closed, the session ended).
  void clear() {
    _reset();
    failure = null;
    busy = false;
    _changed();
  }

  /// Hides the last notice or refusal once the screen has shown it.
  void dismissMessages() {
    failure = null;
    notice = null;
    _changed();
  }

  Future<void> _run(Future<void> Function(TotpEndpoint api) call) async {
    final api = _endpoint();
    if (api == null) {
      failure = const TotpFailure(TotpFailureKind.network);
      _changed();
      return;
    }
    if (busy) return;
    busy = true;
    failure = null;
    notice = null;
    _changed();
    try {
      await call(api);
    } on TotpException catch (e) {
      failure = e.failure;
      if (e.failure.kind == TotpFailureKind.unsupported) step = TotpStep.unsupported;
    } on Exception {
      failure = const TotpFailure(TotpFailureKind.network);
    }
    busy = false;
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  String toString() => 'TotpFlow(step: $step, recoveryLeft: $recoveryLeft, busy: $busy, failure: $failure, notice: $notice)';
}
