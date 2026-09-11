// IOS-01 (P1): the session
// token used to live in plain SharedPreferences, indistinguishable from
// host/port. These tests exercise AuthPrefs against a fake
// SecureTokenBackend (no real platform channel) covering: the real
// no-regression fallback when secure storage is unavailable, and the real
// one-time migration of a pre-fix plaintext token.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hydra_umc_control/network/auth_prefs.dart';

class FakeSecureTokenBackend implements SecureTokenBackend {
  FakeSecureTokenBackend({
    this.alwaysFail = false,
    this.failDelete = false,
    this.failWriteKeys = const {},
  });

  final bool alwaysFail;
  // V07-015 (P1): a real
  // secure-storage failure is not always "everything is broken" - a
  // transient delete failure, or a write that succeeds for one key and
  // fails for the very next one, is exactly as real and needs its own
  // fake to reproduce.
  final bool failDelete;
  final Set<String> failWriteKeys;
  final Map<String, String> store = {};

  @override
  Future<void> write(String key, String value) async {
    if (alwaysFail || failWriteKeys.contains(key)) {
      throw Exception('secure storage unavailable');
    }
    store[key] = value;
  }

  @override
  Future<String?> read(String key) async {
    if (alwaysFail) throw Exception('secure storage unavailable');
    return store[key];
  }

  @override
  Future<void> delete(String key) async {
    if (alwaysFail || failDelete) throw Exception('secure storage unavailable');
    store.remove(key);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('with a real, available secure backend', () {
    test(
      'saveToken/loadToken round-trip through secure storage only',
      () async {
        final secure = FakeSecureTokenBackend();
        final authPrefs = AuthPrefs(secureBackend: secure);

        await authPrefs.saveToken('secret-token', 'alice');

        expect(await authPrefs.loadToken(), 'secret-token');
        expect(await authPrefs.loadUsername(), 'alice');
        expect(secure.store['hydra_token'], 'secret-token');

        // The real closure criterion: the token must not be readable from
        // plain SharedPreferences (nor a device backup of it) once secure
        // storage succeeded.
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('hydra_token'), isNull);
        expect(prefs.getString('hydra_username'), isNull);
      },
    );

    test('clearToken (logout) removes the secure copy and leaves no plaintext trace', () async {
      final secure = FakeSecureTokenBackend();
      final authPrefs = AuthPrefs(secureBackend: secure);
      await authPrefs.saveToken('secret-token', 'alice');

      await authPrefs.clearToken();

      expect(await authPrefs.loadToken(), isNull);
      expect(secure.store, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('hydra_token'), isNull);
    });

    test(
      'a pre-IOS-01 plaintext token is migrated in and the old copy removed',
      () async {
        SharedPreferences.setMockInitialValues({
          'flutter.hydra_token': 'legacy-token',
          'flutter.hydra_username': 'bob',
        });
        final secure = FakeSecureTokenBackend();
        final authPrefs = AuthPrefs(secureBackend: secure);

        final migrated = await authPrefs.loadToken();

        expect(migrated, 'legacy-token');
        expect(secure.store['hydra_token'], 'legacy-token');
        expect(secure.store['hydra_username'], 'bob');
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString('hydra_token'),
          isNull,
          reason: 'the old plaintext copy must be removed after migration',
        );
        expect(prefs.getString('hydra_username'), isNull);
      },
    );
  });

  group('when secure storage is genuinely unavailable (REV-012: never falls back to plaintext)', () {
    test('saveToken/loadToken stay usable via an in-memory-only session, never written to disk', () async {
      final secure = FakeSecureTokenBackend(alwaysFail: true);
      final authPrefs = AuthPrefs(secureBackend: secure);

      await authPrefs.saveToken('secret-token', 'alice');

      expect(await authPrefs.loadToken(), 'secret-token');
      expect(await authPrefs.loadUsername(), 'alice');

      // REV-012's own real closure criterion: the token must NEVER reach
      // plain SharedPreferences (nor a device backup of it) just because
      // secure storage failed - the old, pre-fix behavior this test used
      // to assert as correct.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('hydra_token'), isNull);
      expect(prefs.getString('hydra_username'), isNull);
    });

    test('a fresh AuthPrefs instance (simulating a real app restart) cannot recover an in-memory-only session', () async {
      // REV-012's own real, deliberate trade-off: a device whose secure
      // storage is genuinely broken cannot promise "survives a restart"
      // without writing the token in plaintext, which this fix refuses to
      // do automatically.
      final secure = FakeSecureTokenBackend(alwaysFail: true);
      final firstRun = AuthPrefs(secureBackend: secure);
      await firstRun.saveToken('secret-token', 'alice');
      expect(await firstRun.loadToken(), 'secret-token', reason: 'usable within the SAME run');

      final afterRestart = AuthPrefs(secureBackend: secure);
      expect(await afterRestart.loadToken(), isNull, reason: 'never silently recovered from a plaintext file after a real restart');
    });

    test('a real, already-logged-in pre-fix session survives when migration cannot complete', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.hydra_token': 'legacy-token',
      });
      final secure = FakeSecureTokenBackend(alwaysFail: true);
      final authPrefs = AuthPrefs(secureBackend: secure);

      // Reading a real, PRE-EXISTING plaintext value from before this fix
      // ever existed, not this fix writing a new one.
      expect(await authPrefs.loadToken(), 'legacy-token');
    });

    test('clearToken clears the in-memory session', () async {
      final secure = FakeSecureTokenBackend(alwaysFail: true);
      final authPrefs = AuthPrefs(secureBackend: secure);
      await authPrefs.saveToken('secret-token', 'alice');

      await authPrefs.clearToken();

      expect(await authPrefs.loadToken(), isNull);
    });
  });

  group('V07-015 (P1): logout and partial writes', () {
    test('a logout whose secure delete fails must not let a later loadToken() resurrect the old token', () async {
      final secure = FakeSecureTokenBackend(failDelete: true);
      final authPrefs = AuthPrefs(secureBackend: secure);
      await authPrefs.saveToken('secret-token', 'alice');

      await authPrefs.clearToken(); // the real secure delete fails - caught and, before this fix, only logged

      // A fresh AuthPrefs instance against the SAME real backend/store -
      // simulates loadToken() being called again after this "logout" (a
      // real app restart, or any other code path that re-reads it).
      final afterLogout = AuthPrefs(secureBackend: secure);
      expect(
        await afterLogout.loadToken(),
        isNull,
        reason: 'a real logout must be honoured even when the underlying secure-storage delete itself failed',
      );
    });

    test('a partial saveToken (token written, username write fails) must not leave an orphaned token in secure storage', () async {
      final secure = FakeSecureTokenBackend(failWriteKeys: {'hydra_username'});
      final authPrefs = AuthPrefs(secureBackend: secure);

      await authPrefs.saveToken('secret-token', 'alice');

      // saveToken() itself reports (via its own in-memory fallback) that
      // nothing was durably persisted - secure storage must not disagree
      // by silently holding the token anyway.
      expect(
        secure.store['hydra_token'],
        isNull,
        reason: 'a half-written session (token saved, username save failed) must not linger in secure storage',
      );
    });

    test('a real logout still invalidates the session even on a device whose secure storage is entirely unavailable', () async {
      final secure = FakeSecureTokenBackend(alwaysFail: true);
      final authPrefs = AuthPrefs(secureBackend: secure);
      await authPrefs.saveToken('secret-token', 'alice'); // in-memory only, per REV-012

      await authPrefs.clearToken();

      final afterLogout = AuthPrefs(secureBackend: secure);
      expect(await afterLogout.loadToken(), isNull);
    });
  });

  test(
    'saveConnection/loadConnection are unaffected (host/port are not secrets)',
    () async {
      final authPrefs = AuthPrefs(secureBackend: FakeSecureTokenBackend());

      await authPrefs.saveConnection('192.168.0.42', 8080);

      expect(await authPrefs.loadConnection(), ('192.168.0.42', 8080));
    },
  );

  test('the biometric-enabled flag is unaffected (not a secret, stays in SharedPreferences)', () async {
    final authPrefs = AuthPrefs(secureBackend: FakeSecureTokenBackend());

    expect(await authPrefs.loadBiometricEnabled(), isFalse);
    await authPrefs.saveBiometricEnabled(true);
    expect(await authPrefs.loadBiometricEnabled(), isTrue);
  });

  group('C08: refresh token storage', () {
    test('saveToken with a refreshToken round-trips it through secure storage only', () async {
      final secure = FakeSecureTokenBackend();
      final authPrefs = AuthPrefs(secureBackend: secure);

      await authPrefs.saveToken('secret-token', 'alice', refreshToken: 'secret-refresh-token');

      expect(await authPrefs.loadRefreshToken(), 'secret-refresh-token');
      expect(secure.store['hydra_refresh_token'], 'secret-refresh-token');
      // Never a plaintext copy - same closure criterion as the access token.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('hydra_refresh_token'), isNull);
    });

    test('saveToken with no refreshToken argument leaves a previously-stored one untouched', () async {
      // A server predating C08 omits refreshToken from POST /api/login's
      // response - a caller re-saving the token pair in that case must not
      // be read as "clear the refresh token", since it never said anything
      // about it either way (see saveToken()'s own doc comment).
      final secure = FakeSecureTokenBackend();
      final authPrefs = AuthPrefs(secureBackend: secure);
      await authPrefs.saveToken('token-1', 'alice', refreshToken: 'refresh-1');

      await authPrefs.saveToken('token-2', 'alice');

      expect(await authPrefs.loadRefreshToken(), 'refresh-1');
    });

    test('a session with no refresh token (pre-C08, or a fresh install) reports null, not an error', () async {
      final authPrefs = AuthPrefs(secureBackend: FakeSecureTokenBackend());
      expect(await authPrefs.loadRefreshToken(), isNull);
    });

    test('a logged-out session never reports a stale refresh token', () async {
      final secure = FakeSecureTokenBackend();
      final authPrefs = AuthPrefs(secureBackend: secure);
      await authPrefs.saveToken('secret-token', 'alice', refreshToken: 'secret-refresh-token');

      await authPrefs.clearToken();

      expect(await authPrefs.loadRefreshToken(), isNull);
      expect(secure.store['hydra_refresh_token'], isNull);
      // The logged-out marker still masks it even if the secure delete failed.
      final afterLogout = AuthPrefs(secureBackend: secure);
      expect(await afterLogout.loadRefreshToken(), isNull);
    });

    test('a partial saveToken whose refresh-token write fails still rolls the access token back', () async {
      final secure = FakeSecureTokenBackend(failWriteKeys: {'hydra_refresh_token'});
      final authPrefs = AuthPrefs(secureBackend: secure);

      await authPrefs.saveToken('secret-token', 'alice', refreshToken: 'secret-refresh-token');

      expect(
        secure.store['hydra_token'],
        isNull,
        reason: 'a half-written session (token saved, refresh-token save failed) must not linger in secure storage',
      );
      expect(secure.store['hydra_refresh_token'], isNull);
      // REV-012's own in-memory fallback still applies - the session stays
      // usable for the rest of this app run.
      expect(await authPrefs.loadToken(), 'secret-token');
      expect(await authPrefs.loadRefreshToken(), 'secret-refresh-token');
    });

    test('when secure storage is genuinely unavailable, the refresh token stays in-memory only, never on disk', () async {
      final secure = FakeSecureTokenBackend(alwaysFail: true);
      final authPrefs = AuthPrefs(secureBackend: secure);

      await authPrefs.saveToken('secret-token', 'alice', refreshToken: 'secret-refresh-token');

      expect(await authPrefs.loadRefreshToken(), 'secret-refresh-token', reason: 'in-memory fallback, this app run only');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('hydra_refresh_token'), isNull);
      final afterRestart = AuthPrefs(secureBackend: secure);
      expect(await afterRestart.loadRefreshToken(), isNull, reason: 'never persisted to disk - a real restart loses it, same as the access token');
    });
  });
}
