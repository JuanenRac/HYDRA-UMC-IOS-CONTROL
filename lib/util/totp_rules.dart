// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - util/totp_rules.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The rules of the second sign-in factor (an authenticator-app code), away from the screens and the network: how a refusal is told apart,
// how a typed code is cleaned, how the key is shown, and what an answer must look like before the screen draws it. Pure Dart, tested without
// a device. The same rules as the Android app (network/TotpRules.kt). Nothing here stores or logs a key or a code.
// =============================================================================

/// What kind of refusal a call of the second factor met.
enum TotpFailureKind { unsupported, password, code, wait, already, forbidden, http, network }

/// Why a call of the second factor did not work, in terms a screen can translate. [number] is the seconds of a wait or the HTTP status.
class TotpFailure {
  final TotpFailureKind kind;
  final int? number;
  const TotpFailure(this.kind, [this.number]);

  @override
  bool operator ==(Object other) => other is TotpFailure && other.kind == kind && other.number == number;

  @override
  int get hashCode => Object.hash(kind, number);

  @override
  String toString() => 'TotpFailure($kind, $number)';
}

/// A call of the second factor that the server refused (or that did not reach it).
class TotpException implements Exception {
  final TotpFailure failure;
  const TotpException(this.failure);

  @override
  String toString() => 'TotpException($failure)';
}

/// The status of the second factor of the signed-in account.
class TotpStatus {
  final bool enabled;
  final int recoveryLeft;
  const TotpStatus(this.enabled, this.recoveryLeft);
}

/// The key a new enrolment gives, and the address that holds it for an authenticator app.
class TotpEnrolment {
  final String secret;
  final String uri;
  const TotpEnrolment(this.secret, this.uri);
}

class TotpRules {
  const TotpRules._();

  /// From this many recovery codes left down, the screen warns and offers new ones.
  static const int recoveryLowAt = 2;

  /// The wait shown when a 429 names none.
  static const int defaultWaitSeconds = 30;

  static final RegExp _secret = RegExp(r'^[A-Z2-7]{16,128}$');
  static final RegExp _recoveryCode = RegExp(r'^[0-9a-f]{5}-[0-9a-f]{5}$');
  static final RegExp _sixDigits = RegExp(r'^[0-9]{6}$');
  static final RegExp _separators = RegExp(r'[\s-]');

  /// True when the account has so few recovery codes left that new ones should be made.
  static bool recoveryLow(int left) => left <= recoveryLowAt;

  /// A code typed with spaces or dashes out of place: the six digits of an app code are kept as six digits, a recovery code is lower-cased as typed.
  static String normalizeCode(String text) {
    final trimmed = text.trim();
    final digits = trimmed.replaceAll(_separators, '');
    return _sixDigits.hasMatch(digits) ? digits : trimmed.toLowerCase();
  }

  /// The key in groups of four letters, easier to read and type.
  static String groupedKey(String secret) {
    final groups = <String>[];
    for (var i = 0; i < secret.length; i += 4) {
      groups.add(secret.substring(i, i + 4 > secret.length ? secret.length : i + 4));
    }
    return groups.join(' ');
  }

  /// The key hidden but for its length (bullets in groups of four), for a screen that is not yet showing it.
  static String maskedKey(String secret) => groupedKey('•' * secret.length);

  /// What stands for a recovery code while the codes are hidden (the same shape, no characters).
  static const String maskedRecoveryCode = '•••••-•••••';

  /// The enrolment as the screen may draw it, or null when its key or its address is not what the server contract describes.
  static TotpEnrolment? checkedEnrolment(String secret, String uri) =>
      _secret.hasMatch(secret) && uri.startsWith('otpauth://totp/') ? TotpEnrolment(secret, uri) : null;

  /// The recovery codes as the screen may draw them, or null when the list is empty or one of them is not of the form the server makes.
  static List<String>? checkedRecoveryCodes(List<String> codes) =>
      codes.isNotEmpty && codes.every(_recoveryCode.hasMatch) ? List.unmodifiable(codes) : null;

  /// Tells a refusal of one of the second-factor calls. [totpRequired] is the flag of the sign-in answer, [retryAfterSeconds] the `Retry-After`
  /// of a 429, and [needsCodeIfPasswordRefused] says that the password was already checked before the code (turning it off, new recovery codes),
  /// so a 401 whose text names the code is the code.
  static TotpFailure failureOf(
    int? status, {
    bool totpRequired = false,
    int? retryAfterSeconds,
    bool needsCodeIfPasswordRefused = false,
    String? serverMessage,
  }) {
    if (status == null) return const TotpFailure(TotpFailureKind.network);
    switch (status) {
      case 404:
        return const TotpFailure(TotpFailureKind.unsupported);
      case 403:
        return const TotpFailure(TotpFailureKind.forbidden);
      case 429:
        return TotpFailure(
          TotpFailureKind.wait,
          retryAfterSeconds != null && retryAfterSeconds > 0 ? retryAfterSeconds : defaultWaitSeconds,
        );
      case 409:
        return const TotpFailure(TotpFailureKind.already);
      case 401:
        if (totpRequired) return const TotpFailure(TotpFailureKind.code);
        if (needsCodeIfPasswordRefused && (serverMessage ?? '').toLowerCase().contains('code')) {
          return const TotpFailure(TotpFailureKind.code);
        }
        return const TotpFailure(TotpFailureKind.password);
      case 400:
        return const TotpFailure(TotpFailureKind.code);
    }
    return TotpFailure(TotpFailureKind.http, status);
  }
}
