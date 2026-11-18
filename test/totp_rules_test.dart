// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/totp_rules_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The rules of the second sign-in factor without a device: typed codes, the key as shown, what an answer must look like, and how a refusal
// is told. The same cases as the Android app (TotpRulesTest).
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_umc_control/util/totp_rules.dart';

void main() {
  test('an app code typed with spaces or dashes keeps its six digits', () {
    expect(TotpRules.normalizeCode(' 123 456 '), '123456');
    expect(TotpRules.normalizeCode('123-456'), '123456');
    expect(TotpRules.normalizeCode('123456'), '123456');
  });

  test('a recovery code is kept as typed in lower case', () {
    expect(TotpRules.normalizeCode('  A1B2C-D3E4F '), 'a1b2c-d3e4f');
    expect(TotpRules.normalizeCode('12345'), '12345');
    expect(TotpRules.normalizeCode('   '), '');
  });

  test('the key is shown in groups of four and hidden with the same length', () {
    expect(TotpRules.groupedKey('ABCDEFGHIJ'), 'ABCD EFGH IJ');
    final masked = TotpRules.maskedKey('ABCDEFGHIJKLMNOP');
    expect(masked.length, 4 * 4 + 3);
    expect(RegExp(r'[A-Za-z]').hasMatch(masked), isFalse);
  });

  test('an enrolment with a key or address of another form is refused', () {
    const key = 'JBSWY3DPEHPK3PXP';
    expect(TotpRules.checkedEnrolment(key, 'otpauth://totp/HYDRA:ana?secret=$key'), isNotNull);
    expect(TotpRules.checkedEnrolment('short', 'otpauth://totp/HYDRA:ana'), isNull);
    expect(TotpRules.checkedEnrolment(key.toLowerCase(), 'otpauth://totp/HYDRA:ana'), isNull);
    expect(TotpRules.checkedEnrolment(key, 'https://example.invalid/?secret=$key'), isNull);
  });

  test('recovery codes must be the form the server makes', () {
    expect(TotpRules.checkedRecoveryCodes(['0a1b2-c3d4e', 'ffffe-00001']), isNotNull);
    expect(TotpRules.checkedRecoveryCodes([]), isNull);
    expect(TotpRules.checkedRecoveryCodes(['0a1b2-c3d4e', 'not a code']), isNull);
    expect(TotpRules.checkedRecoveryCodes(['0A1B2-C3D4E']), isNull);
  });

  test('the warning starts at two codes left', () {
    expect(TotpRules.recoveryLow(0), isTrue);
    expect(TotpRules.recoveryLow(2), isTrue);
    expect(TotpRules.recoveryLow(3), isFalse);
  });

  test('every refusal is told apart', () {
    expect(TotpRules.failureOf(null), const TotpFailure(TotpFailureKind.network));
    expect(TotpRules.failureOf(404), const TotpFailure(TotpFailureKind.unsupported));
    expect(TotpRules.failureOf(403), const TotpFailure(TotpFailureKind.forbidden));
    expect(TotpRules.failureOf(409), const TotpFailure(TotpFailureKind.already));
    expect(TotpRules.failureOf(400), const TotpFailure(TotpFailureKind.code));
    expect(TotpRules.failureOf(401), const TotpFailure(TotpFailureKind.password));
    expect(TotpRules.failureOf(401, totpRequired: true), const TotpFailure(TotpFailureKind.code));
    expect(TotpRules.failureOf(500), const TotpFailure(TotpFailureKind.http, 500));
  });

  test('a wait names the seconds of the server or thirty', () {
    expect(TotpRules.failureOf(429, retryAfterSeconds: 45), const TotpFailure(TotpFailureKind.wait, 45));
    expect(TotpRules.failureOf(429), const TotpFailure(TotpFailureKind.wait, 30));
    expect(TotpRules.failureOf(429, retryAfterSeconds: 0), const TotpFailure(TotpFailureKind.wait, 30));
  });

  test('a wrong code when turning off is the code, not the password', () {
    const message = 'A current code or an unused recovery code is required';
    expect(
      TotpRules.failureOf(401, needsCodeIfPasswordRefused: true, serverMessage: message),
      const TotpFailure(TotpFailureKind.code),
    );
    expect(
      TotpRules.failureOf(401, needsCodeIfPasswordRefused: true, serverMessage: 'Invalid credentials'),
      const TotpFailure(TotpFailureKind.password),
    );
    expect(TotpRules.failureOf(401, serverMessage: message), const TotpFailure(TotpFailureKind.password));
  });
}
