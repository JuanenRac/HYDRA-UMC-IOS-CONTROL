// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/strong_session_backend_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The strong biometric mode of the saved session against fake Keychain stores (the prompt itself needs an iPhone):
// off by default, the session goes to the protected store only while the mode is on, switching moves it both ways and a
// refusal of the protected store leaves everything as it was.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydra_umc_control/network/auth_prefs.dart';

class _Store implements SecureTokenBackend {
  _Store({this.refuseWrites = false});
  final bool refuseWrites;
  final Map<String, String> items = {};
  int reads = 0;

  @override
  Future<void> write(String key, String value) async {
    if (refuseWrites) throw Exception('no passcode set');
    items[key] = value;
  }

  @override
  Future<String?> read(String key) async {
    reads++;
    return items[key];
  }

  @override
  Future<void> delete(String key) async => items.remove(key);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the strong mode is off by default and the session stays in the normal store', () async {
    final normal = _Store();
    final strong = _Store();
    final prefs = AuthPrefs(secureBackend: normal, strongBackend: strong);
    expect(await prefs.loadBiometricStrong(), isFalse);
    await prefs.saveToken('tok', 'ana', refreshToken: 'ref');
    expect(normal.items, isNotEmpty);
    expect(strong.items, isEmpty);
    expect(await prefs.loadToken(), 'tok');
  });

  test('switching the mode on moves the session to the protected store and empties the normal one', () async {
    final normal = _Store();
    final strong = _Store();
    final prefs = AuthPrefs(secureBackend: normal, strongBackend: strong);
    await prefs.saveToken('tok', 'ana', refreshToken: 'ref');
    await prefs.setBiometricStrong(true);
    expect(await prefs.loadBiometricStrong(), isTrue);
    expect(normal.items, isEmpty);
    expect(strong.items.values.toSet(), {'tok', 'ana', 'ref'});
    expect(await prefs.loadToken(), 'tok');
    expect(await prefs.loadRefreshToken(), 'ref');
  });

  test('a new session is written to the protected store only while the mode is on', () async {
    final normal = _Store();
    final strong = _Store();
    final prefs = AuthPrefs(secureBackend: normal, strongBackend: strong);
    await prefs.setBiometricStrong(true);
    await prefs.saveToken('tok2', 'bea', refreshToken: 'ref2');
    expect(normal.items, isEmpty);
    expect(strong.items.values.toSet(), {'tok2', 'bea', 'ref2'});
  });

  test('one read of the protected store covers the reads that follow in the run', () async {
    final strong = _Store();
    final prefs = AuthPrefs(secureBackend: _Store(), strongBackend: strong);
    await prefs.setBiometricStrong(true);
    await prefs.saveToken('tok', 'ana', refreshToken: 'ref');
    strong.reads = 0;
    // A fresh object with the same stores stands for the next launch: its first read goes to the store, the second does not.
    final next = AuthPrefs(secureBackend: _Store(), strongBackend: strong);
    expect(await next.loadToken(), 'tok');
    expect(await next.loadToken(), 'tok');
    expect(await next.loadUsername(), 'ana');
    expect(strong.reads, 2, reason: 'the token once and the user name once');
  });

  test('switching the mode off brings the session back to the normal store', () async {
    final normal = _Store();
    final strong = _Store();
    final prefs = AuthPrefs(secureBackend: normal, strongBackend: strong);
    await prefs.saveToken('tok', 'ana', refreshToken: 'ref');
    await prefs.setBiometricStrong(true);
    await prefs.setBiometricStrong(false);
    expect(await prefs.loadBiometricStrong(), isFalse);
    expect(strong.items, isEmpty);
    expect(normal.items.values.toSet(), {'tok', 'ana', 'ref'});
  });

  test('a device that refuses the protected item leaves the mode off and the session where it was', () async {
    final normal = _Store();
    final prefs = AuthPrefs(secureBackend: normal, strongBackend: _Store(refuseWrites: true));
    await prefs.saveToken('tok', 'ana', refreshToken: 'ref');
    await expectLater(prefs.setBiometricStrong(true), throwsException);
    expect(await prefs.loadBiometricStrong(), isFalse);
    expect(normal.items.values.toSet(), {'tok', 'ana', 'ref'});
    expect(await prefs.loadToken(), 'tok');
  });

  test('clearing the session erases it from the protected store too', () async {
    final strong = _Store();
    final prefs = AuthPrefs(secureBackend: _Store(), strongBackend: strong);
    await prefs.setBiometricStrong(true);
    await prefs.saveToken('tok', 'ana', refreshToken: 'ref');
    await prefs.clearToken();
    expect(strong.items, isEmpty);
    expect(await prefs.loadToken(), isNull);
  });
}
