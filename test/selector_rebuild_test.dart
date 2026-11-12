// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/selector_rebuild_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The screens listen to the fields they draw, not to the whole view model: a
// change that is not theirs must not redraw them, and every change that is
// theirs must. The count is Flutter's own list of widgets rebuilt
// (debugPrintRebuildDirtyWidgets), so a screen that goes back to watching
// everything fails here, and so does one that stops following a field.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydra_umc_control/l10n/app_localizations.dart';
import 'package:hydra_umc_control/models/access.dart';
import 'package:hydra_umc_control/models/ecosystem.dart';
import 'package:hydra_umc_control/network/auth_prefs.dart';
import 'package:hydra_umc_control/state/robot_view_model.dart';
import 'package:hydra_umc_control/ui/camera_screen.dart';
import 'package:hydra_umc_control/ui/control_screen.dart';
import 'package:hydra_umc_control/ui/dashboard_screen.dart';
import 'package:hydra_umc_control/ui/ecosystem_tab.dart';
import 'package:hydra_umc_control/state/hydra_error.dart';
import 'package:hydra_umc_control/ui/login_screen.dart';
import 'package:hydra_umc_control/ui/main_screen.dart';
import 'package:hydra_umc_control/ui/settings_screen.dart';
import 'package:hydra_umc_control/ui/three_d_screen.dart';
import 'package:hydra_umc_control/ui/telemetry_screen.dart';

class _Backend implements SecureTokenBackend {
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> delete(String key) async {}
}

class _Vm extends RobotViewModel {
  _Vm() : super(authPrefs: AuthPrefs(secureBackend: _Backend()));
  void poke() => notifyListeners();
}

Future<_Vm> _pump(WidgetTester tester, Widget screen) async {
  final vm = _Vm();
  vm.state.raw['controllers'] = [
    {
      'id': 'c1',
      'robots': [
        {'id': 1, 'name': 'ARM-1', 'online': true, 'pos': {'x': 10, 'y': 20, 'z': 30}},
      ],
    },
  ];
  vm.selectedRobotId = 1;
  await tester.pumpWidget(
    ChangeNotifierProvider<RobotViewModel>.value(
      value: vm,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Column(children: [Expanded(child: screen)])),
      ),
    ),
  );
  await tester.pump();
  return vm;
}

/// The names of the widgets rebuilt while [action] runs.
Future<String> _rebuilt(WidgetTester tester, Future<void> Function() action) async {
  final lines = <String>[];
  final oldPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) => lines.add(message ?? '');
  debugPrintRebuildDirtyWidgets = true;
  try {
    await action();
    await tester.pump();
  } finally {
    debugPrintRebuildDirtyWidgets = false;
    debugPrint = oldPrint;
  }
  return lines.join('\n');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the control screen ignores what it does not show', (tester) async {
    final vm = await _pump(tester, const ControlScreen());
    addTearDown(vm.dispose);
    // The texts of the language load a frame later: wait for them, or their redraw is counted as the screen's.
    await tester.pumpAndSettle();
    // Drawing the robot fills in the parts of its state it did not have (joints, valves, pumps): that one change is the screen's own.
    vm.poke();
    await tester.pump();
    final unrelated = await _rebuilt(tester, () async {
      vm.connectionStatus = 'connected';
      vm.isShowingCachedState = true;
      vm.poke();
    });
    expect(unrelated, isNot(contains('ControlScreen')));
  });

  testWidgets('the control screen follows each thing it draws or decides', (tester) async {
    final vm = await _pump(tester, const ControlScreen());
    addTearDown(vm.dispose);
    // The texts of the language load a frame later: wait for them, or their redraw is counted as the screen's.
    await tester.pumpAndSettle();
    // Drawing the robot fills in the parts of its state it did not have (joints, valves, pumps): that one change is the screen's own.
    vm.poke();
    await tester.pump();
    final changes = <String, void Function()>{
      'the robot moves': () => vm.selectedRobot!.raw['pos']['x'] = 99,
      'the robot goes offline': () => vm.selectedRobot!.raw['online'] = false,
      'a reservation appears': () => vm.claims = [
        ClaimInfo(robotId: 1, robotName: 'ARM-1', ownerUsername: 'bob', controllerId: 'other', expiresAt: 5),
      ],
      'the arming of the jog changes': () => vm.jogArmedUntil[1] = DateTime.utc(2031),
      'the limits of the robot change': () => vm.safetyByRobot[1] = RobotSafety(
        robotId: 1,
        jog: const JogLimits(10, 100),
        bedMaxC: 0,
        armRequired: true,
        armTtlMs: 60000,
        jogArmedUntil: null,
      ),
      'a request is under way': () => vm.accessBusy = true,
      'the STOP is not confirmed': () => vm.stopAllUnconfirmed = true,
      'the switch of the home reset changes': () => vm.homeResetEnabled = !vm.homeResetEnabled,
      'the question before PLAY changes': () => vm.confirmPlay = !vm.confirmPlay,
    };
    for (final change in changes.entries) {
      final related = await _rebuilt(tester, () async {
        change.value();
        vm.poke();
      });
      expect(related, contains('ControlScreen'), reason: change.key);
    }
  });

  testWidgets('the camera screen ignores what it does not show', (tester) async {
    final vm = await _pump(tester, const CameraScreen());
    addTearDown(vm.dispose);
    await tester.pumpAndSettle();
    vm.poke();
    await tester.pump();
    final unrelated = await _rebuilt(tester, () async {
      vm.connectionStatus = 'connected';
      vm.isShowingCachedState = true;
      vm.confirmPlay = !vm.confirmPlay;
      vm.poke();
    });
    expect(unrelated, isNot(contains('CameraScreen')));
  });

  testWidgets('the camera screen follows the robots and their cameras', (tester) async {
    final vm = await _pump(tester, const CameraScreen());
    addTearDown(vm.dispose);
    await tester.pumpAndSettle();
    vm.poke();
    await tester.pump();
    final changes = <String, void Function()>{
      'the robot goes offline': () => vm.selectedRobot!.raw['online'] = false,
      'the vision of the robot is switched': () => vm.selectedRobot!.raw['visionEnabled'] = true,
      'a camera is assigned to the robot': () => vm.state.raw['controllers'][0]['cameras'] = [
        {'id': 'cam-9', 'assignedRobotId': 1},
      ],
    };
    for (final change in changes.entries) {
      final related = await _rebuilt(tester, () async {
        change.value();
        vm.poke();
      });
      expect(related, contains('CameraScreen'), reason: change.key);
    }
  });

  testWidgets('the dashboard ignores what it does not show', (tester) async {
    final vm = await _pump(tester, const DashboardScreen());
    addTearDown(vm.dispose);
    // An online robot's lamp animates for ever: wait a few frames instead of settling.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    vm.poke();
    await tester.pump();
    final unrelated = await _rebuilt(tester, () async {
      vm.connectionStatus = 'connected';
      vm.isShowingCachedState = true;
      vm.confirmPlay = !vm.confirmPlay;
      vm.poke();
    });
    expect(unrelated, isNot(contains('DashboardScreen')));
  });

  testWidgets('the dashboard follows the robots it lists', (tester) async {
    final vm = await _pump(tester, const DashboardScreen());
    addTearDown(vm.dispose);
    // An online robot's lamp animates for ever: wait a few frames instead of settling.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    vm.poke();
    await tester.pump();
    final changes = <String, void Function()>{
      'the robot moves': () => vm.selectedRobot!.raw['pos']['x'] = 99,
      'the robot goes offline': () => vm.selectedRobot!.raw['online'] = false,
      'the robot is renamed': () => vm.selectedRobot!.raw['name'] = 'ARM-2',
    };
    for (final change in changes.entries) {
      final related = await _rebuilt(tester, () async {
        change.value();
        vm.poke();
      });
      expect(related, contains('DashboardScreen'), reason: change.key);
    }
  });

  testWidgets('the log tab ignores what it does not show and follows the log', (tester) async {
    final vm = await _pump(tester, const TelemetryScreen());
    addTearDown(vm.dispose);
    await tester.pumpAndSettle();
    final unrelated = await _rebuilt(tester, () async {
      vm.connectionStatus = 'connected';
      vm.isShowingCachedState = true;
      vm.poke();
    });
    expect(unrelated, isNot(contains('_LogsTab')));
    final related = await _rebuilt(tester, () async {
      vm.telemetryLog.insert(0, '[00:00] one more line');
      vm.poke();
    });
    expect(related, contains('_LogsTab'));
  });

  testWidgets('the ecosystem tab ignores what it does not show and follows its list', (tester) async {
    final vm = await _pump(tester, const EcosystemTab());
    addTearDown(vm.dispose);
    await tester.pumpAndSettle();
    final unrelated = await _rebuilt(tester, () async {
      vm.connectionStatus = 'connected';
      vm.isShowingCachedState = true;
      vm.poke();
    });
    expect(unrelated, isNot(contains('EcosystemTab')));
    final changes = <String, void Function()>{
      'a project is listed': () => vm.ecosystem = const EcosystemStatus(
        available: true,
        projects: [EcosystemProject(name: 'P1', family: 'F', live: false, servicePort: 1)],
      ),
      'a project goes live': () => vm.ecosystem = const EcosystemStatus(
        available: true,
        projects: [EcosystemProject(name: 'P1', family: 'F', live: true, servicePort: 1)],
      ),
      'a read is under way': () => vm.ecosystemLoading = true,
    };
    for (final change in changes.entries) {
      final related = await _rebuilt(tester, () async {
        change.value();
        vm.poke();
      });
      expect(related, contains('EcosystemTab'), reason: change.key);
    }
  });

  testWidgets('the main screen ignores what it does not show and follows its title and banner', (tester) async {
    final vm = await _pump(tester, const MainScreen());
    addTearDown(vm.dispose);
    // An online robot's lamp animates for ever: wait a few frames instead of settling.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    vm.poke();
    await tester.pump();
    final unrelated = await _rebuilt(tester, () async {
      vm.confirmPlay = !vm.confirmPlay;
      vm.homeResetEnabled = !vm.homeResetEnabled;
      vm.poke();
    });
    expect(unrelated, isNot(contains('MainScreen')));
    final changes = <String, void Function()>{
      'the connection status changes': () => vm.connectionStatus = 'connected',
      'the saved-data banner appears': () => vm.isShowingCachedState = true,
    };
    for (final change in changes.entries) {
      final related = await _rebuilt(tester, () async {
        change.value();
        vm.poke();
      });
      expect(related, contains('MainScreen'), reason: change.key);
    }
  });

  testWidgets('the sign-in screen follows its errors and its pairing, and not the robots', (tester) async {
    final vm = await _pump(tester, const LoginScreen());
    addTearDown(vm.dispose);
    await tester.pump(const Duration(milliseconds: 200));
    vm.poke();
    await tester.pump();
    final unrelated = await _rebuilt(tester, () async {
      vm.selectedRobot!.raw['pos']['x'] = 99;
      vm.confirmPlay = !vm.confirmPlay;
      vm.poke();
    });
    expect(unrelated, isNot(contains('LoginScreen')));
    final changes = <String, void Function()>{
      'a sign-in is refused': () => vm.lastError = const HydraError(HydraErrorKind.loginFailed),
      'a pairing gives an address': () {
        vm.pairedHost = 'hydra.local';
        vm.pairedPort = 3443;
        vm.pairedStamp++;
      },
    };
    for (final change in changes.entries) {
      final related = await _rebuilt(tester, () async {
        change.value();
        vm.poke();
      });
      expect(related, contains('LoginScreen'), reason: change.key);
    }
  });

  testWidgets('the settings follow what they show and not the robots', (tester) async {
    final vm = await _pump(tester, const SettingsScreen());
    addTearDown(vm.dispose);
    await tester.pump(const Duration(milliseconds: 200));
    vm.poke();
    await tester.pump();
    final unrelated = await _rebuilt(tester, () async {
      vm.selectedRobot!.raw['pos']['x'] = 99;
      vm.selectedRobot!.raw['online'] = false;
      vm.poke();
    });
    expect(unrelated, isNot(contains('SettingsScreen')));
    final changes = <String, void Function()>{
      'the connection status changes': () => vm.connectionStatus = 'connected',
      'the question before PLAY changes': () => vm.confirmPlay = !vm.confirmPlay,
      'the switch of the home reset changes': () => vm.homeResetEnabled = !vm.homeResetEnabled,
      'the dictation is switched': () => vm.dictationEnabled = !vm.dictationEnabled,
      'the pairing is switched': () => vm.pairingEnabled = !vm.pairingEnabled,
    };
    for (final change in changes.entries) {
      final related = await _rebuilt(tester, () async {
        change.value();
        vm.poke();
      });
      expect(related, contains('SettingsScreen'), reason: change.key);
    }
  });

  testWidgets('the 3D screen follows the robot and the sign-in, and not the robots moving', (tester) async {
    final vm = await _pump(tester, const ThreeDScreen());
    addTearDown(vm.dispose);
    await tester.pump(const Duration(milliseconds: 200));
    vm.poke();
    await tester.pump();
    final unrelated = await _rebuilt(tester, () async {
      vm.selectedRobot!.raw['pos']['x'] = 99;
      vm.connectionStatus = 'connected';
      vm.poke();
    });
    expect(unrelated, isNot(contains('ThreeDScreen')));
    final related = await _rebuilt(tester, () async {
      vm.selectedRobotId = 2;
      vm.poke();
    });
    expect(related, contains('ThreeDScreen'));
  });
}
