// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/saved_data_block_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The optional block on commands while the screen shows the saved copy of the
// robot state: off by default (as the app always behaved), kept across
// launches once turned on, and never applied to STOP.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydra_umc_control/network/auth_prefs.dart';
import 'package:hydra_umc_control/network/client_prefs.dart';
import 'package:hydra_umc_control/network/state_cache.dart';
import 'package:hydra_umc_control/state/hydra_error.dart';
import 'package:hydra_umc_control/state/robot_view_model.dart';

class _FakeSecureBackend implements SecureTokenBackend {
  final Map<String, String> store = {};
  @override
  Future<void> write(String key, String value) async => store[key] = value;
  @override
  Future<String?> read(String key) async => store[key];
  @override
  Future<void> delete(String key) async => store.remove(key);
}

Future<RobotViewModel> _modelShowingSavedData() async {
  await StateCache().saveState({
    'controllers': [
      {
        'id': 'c1',
        'robots': [
          {'id': 1, 'name': 'ARM-1', 'online': true},
        ],
      },
    ],
  });
  final vm = RobotViewModel(authPrefs: AuthPrefs(secureBackend: _FakeSecureBackend()));
  await vm.init();
  vm.selectedRobotId = 1;
  return vm;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('both switches are off by default', () async {
    final prefs = ClientPrefs();
    expect(await prefs.loadBlockCommandsOnSavedData(), isFalse);
    expect(await prefs.loadSkipMobileAndVpnNetworks(), isFalse);
  });

  test('with the block off, a command on saved data goes through the normal path', () async {
    final vm = await _modelShowingSavedData();
    addTearDown(vm.dispose);
    expect(vm.isShowingCachedState, isTrue);
    expect(vm.blockCommandsOnSavedData, isFalse);

    vm.sendCommand('play');
    await Future<void>.delayed(Duration.zero);

    // No server in this test: the command got as far as needing a connection.
    expect(vm.lastError?.kind, HydraErrorKind.notConnected);
  });

  test('with the block on, a command on saved data is held back with its own error', () async {
    final vm = await _modelShowingSavedData();
    addTearDown(vm.dispose);
    await vm.setBlockCommandsOnSavedData(true);

    vm.sendCommand('play');
    await Future<void>.delayed(Duration.zero);

    expect(vm.lastError?.kind, HydraErrorKind.savedDataBlocked);
    expect(vm.state.robotById(1)!.isPlaying, isFalse, reason: 'a held-back command must not change the screen');
  });

  test('STOP is never held back by the block', () async {
    final vm = await _modelShowingSavedData();
    addTearDown(vm.dispose);
    await vm.setBlockCommandsOnSavedData(true);

    vm.sendCommand('stop');
    await Future<void>.delayed(Duration.zero);

    expect(vm.lastError?.kind, isNot(HydraErrorKind.savedDataBlocked));
  });

  test('the choice is saved and read back at the next launch', () async {
    final vm = await _modelShowingSavedData();
    await vm.setBlockCommandsOnSavedData(true);
    vm.dispose();

    final again = RobotViewModel(authPrefs: AuthPrefs(secureBackend: _FakeSecureBackend()));
    addTearDown(again.dispose);
    await again.init();
    expect(again.blockCommandsOnSavedData, isTrue);
  });
}
