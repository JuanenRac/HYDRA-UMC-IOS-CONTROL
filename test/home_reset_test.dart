// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/home_reset_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// HOME/RESET: the rules (when the app refuses to offer it, the confirmation in
// steps), the switch (off by default, kept across launches) and the screen (no
// button while it is off, two confirmations before anything is sent, a blocked
// robot opens nothing). No robot is involved: the view model here only records.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydra_umc_control/l10n/app_localizations.dart';
import 'package:hydra_umc_control/models/robot_command_contract.dart';
import 'package:hydra_umc_control/network/auth_prefs.dart';
import 'package:hydra_umc_control/network/client_prefs.dart';
import 'package:hydra_umc_control/network/command_sequence.dart';
import 'package:hydra_umc_control/state/robot_view_model.dart';
import 'package:hydra_umc_control/ui/control_screen.dart';
import 'package:hydra_umc_control/util/home_reset.dart';

class _FakeSecureBackend implements SecureTokenBackend {
  final Map<String, String> store = {};
  @override
  Future<void> write(String key, String value) async => store[key] = value;
  @override
  Future<String?> read(String key) async => store[key];
  @override
  Future<void> delete(String key) async => store.remove(key);
}

class _RecordingViewModel extends RobotViewModel {
  _RecordingViewModel() : super(authPrefs: AuthPrefs(secureBackend: _FakeSecureBackend()));
  int resets = 0;
  HomeResetBlock blocked = HomeResetBlock.none;

  /// Replaces the check so the screen can be driven without a server; the real check is covered below.
  @override
  HomeResetBlock homeResetBlock([dynamic robotId, DateTime? now]) => homeResetEnabled ? blocked : HomeResetBlock.off;

  /// Never reaches a network: it only counts.
  @override
  void homeReset() => resets++;
}

_RecordingViewModel _modelWithRobot() {
  final vm = _RecordingViewModel();
  vm.state.raw['controllers'] = [
    {
      'id': 'c1',
      'robots': [
        {
          'id': 1,
          'name': 'ARM-1',
          'online': true,
          'pos': {'x': 10, 'y': 20, 'z': 30},
          'playbackState': {'isPlaying': false},
        },
      ],
    },
  ];
  vm.selectedRobotId = 1;
  return vm;
}

Future<void> _pump(WidgetTester tester, RobotViewModel vm) async {
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
        home: const Scaffold(body: ControlScreen()),
      ),
    ),
  );
  await tester.pump();
}

HomeResetSituation _ready({
  bool switchedOn = true,
  bool connected = true,
  bool robotOnline = true,
  bool robotEnabled = true,
  bool robotPlaying = false,
  bool jogInFlight = false,
  bool stopInProgress = false,
  bool needsArming = false,
  String? role = 'operator',
  bool hasPose = true,
  bool serverSupports = true,
}) =>
    HomeResetSituation(
      switchedOn: switchedOn,
      connected: connected,
      robotOnline: robotOnline,
      robotEnabled: robotEnabled,
      robotPlaying: robotPlaying,
      jogInFlight: jogInFlight,
      stopInProgress: stopInProgress,
      needsArming: needsArming,
      role: role,
      hasPose: hasPose,
      serverSupports: serverSupports,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('it is off by default, asks twice, and the reset is numbered like the jog', () {
    expect(RobotCommandContract.homeResetEnabledByDefault, isFalse);
    expect(RobotCommandContract.homeResetConfirmSteps, 2);
    expect(RobotCommandContract.homeResetConfirmWindowMs, greaterThan(0));
    expect(CommandSequence.isNumbered(RobotCommandContract.reset), isTrue);
  });

  test('a ready situation has no block, and a role that cannot be read is left to the server', () {
    expect(homeResetBlockOf(_ready()), HomeResetBlock.none);
    expect(homeResetBlockOf(_ready(role: 'admin')), HomeResetBlock.none);
    expect(homeResetBlockOf(_ready(role: null)), HomeResetBlock.none);
  });

  test('each reason blocks, and the switch wins over everything else', () {
    expect(homeResetBlockOf(_ready(switchedOn: false)), HomeResetBlock.off);
    expect(homeResetBlockOf(_ready(connected: false)), HomeResetBlock.notConnected);
    expect(homeResetBlockOf(_ready(serverSupports: false)), HomeResetBlock.notSupported);
    expect(homeResetBlockOf(_ready(role: 'viewer')), HomeResetBlock.role);
    expect(homeResetBlockOf(_ready(robotOnline: false)), HomeResetBlock.offline);
    expect(homeResetBlockOf(_ready(robotEnabled: false)), HomeResetBlock.safeMode);
    expect(homeResetBlockOf(_ready(stopInProgress: true)), HomeResetBlock.stopPending);
    expect(homeResetBlockOf(_ready(robotPlaying: true)), HomeResetBlock.moving);
    expect(homeResetBlockOf(_ready(jogInFlight: true)), HomeResetBlock.jogBusy);
    expect(homeResetBlockOf(_ready(needsArming: true)), HomeResetBlock.notArmed);
    expect(homeResetBlockOf(_ready(hasPose: false)), HomeResetBlock.noPose);
    expect(homeResetBlockOf(_ready(switchedOn: false, connected: false, robotPlaying: true)), HomeResetBlock.off);
  });

  test('only the last step finishes', () {
    var now = DateTime(2000, 1, 1);
    final confirmation = HomeResetConfirmation(steps: 2, window: const Duration(seconds: 20), clock: () => now);
    expect(confirmation.advance(), const HomeResetProgress.waiting(2));
    now = now.add(const Duration(seconds: 5));
    expect(confirmation.advance().isDone, isTrue);
  });

  test('a step given after the window starts over, and cancel and a finished confirmation both start over', () {
    var now = DateTime(2000, 1, 1);
    final confirmation = HomeResetConfirmation(steps: 2, window: const Duration(seconds: 20), clock: () => now);
    confirmation.advance();
    now = now.add(const Duration(seconds: 21));
    expect(confirmation.current, 1);
    expect(confirmation.advance(), const HomeResetProgress.waiting(2), reason: 'the late press counts as a first step');
    confirmation.cancel();
    expect(confirmation.advance(), const HomeResetProgress.waiting(2));
    expect(confirmation.advance().isDone, isTrue);
    expect(confirmation.advance(), const HomeResetProgress.waiting(2), reason: 'done does not stay armed');
    expect(HomeResetConfirmation(steps: 1, window: const Duration(seconds: 1)).advance().isDone, isTrue);
    expect(HomeResetConfirmation(steps: 0, window: const Duration(seconds: 1)).advance().isDone, isTrue);
  });

  test('the switch is off before any choice, and a choice is kept across launches', () async {
    expect(await ClientPrefs().loadHomeReset(false), isFalse);
    final vm = _RecordingViewModel();
    addTearDown(vm.dispose);
    expect(vm.homeResetEnabled, isFalse);
    await vm.setHomeResetEnabled(true);
    expect(vm.homeResetEnabled, isTrue);
    expect(await ClientPrefs().loadHomeReset(false), isTrue);
    final next = _RecordingViewModel();
    addTearDown(next.dispose);
    await next.init();
    expect(next.homeResetEnabled, isTrue);
    await next.setHomeResetEnabled(false);
    expect(await ClientPrefs().loadHomeReset(false), isFalse);
  });

  testWidgets('with the switch off there is no button', (tester) async {
    final vm = _modelWithRobot();
    addTearDown(vm.dispose);
    await _pump(tester, vm);
    expect(find.byKey(const Key('home-reset-button')), findsNothing);
  });

  testWidgets('two confirmations are needed before anything is sent', (tester) async {
    final vm = _modelWithRobot();
    addTearDown(vm.dispose);
    await vm.setHomeResetEnabled(true);
    await _pump(tester, vm);

    await tester.ensureVisible(find.byKey(const Key('home-reset-button')));
    await tester.tap(find.byKey(const Key('home-reset-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('(1 of 2)'), findsOneWidget);
    expect(vm.resets, 0);

    await tester.tap(find.byKey(const Key('home-reset-confirm-first')));
    await tester.pumpAndSettle();
    expect(find.text('Last check (2 of 2)'), findsOneWidget);
    expect(vm.resets, 0, reason: 'the first confirmation alone sends nothing');

    await tester.tap(find.byKey(const Key('home-reset-confirm-last')));
    await tester.pumpAndSettle();
    expect(vm.resets, 1);
  });

  testWidgets('cancelling at either step sends nothing and starts over', (tester) async {
    final vm = _modelWithRobot();
    addTearDown(vm.dispose);
    await vm.setHomeResetEnabled(true);
    await _pump(tester, vm);

    await tester.ensureVisible(find.byKey(const Key('home-reset-button')));
    await tester.tap(find.byKey(const Key('home-reset-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(vm.resets, 0);

    await tester.tap(find.byKey(const Key('home-reset-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-reset-confirm-first')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(vm.resets, 0);

    // After a cancel the next press starts at the first step again.
    await tester.tap(find.byKey(const Key('home-reset-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('(1 of 2)'), findsOneWidget);
  });

  testWidgets('a blocked robot opens no dialog and the reason is on screen', (tester) async {
    final vm = _modelWithRobot()..blocked = HomeResetBlock.moving;
    addTearDown(vm.dispose);
    await vm.setHomeResetEnabled(true);
    await _pump(tester, vm);

    expect(find.text('The robot is running a trajectory: press STOP first.'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('home-reset-button')));
    await tester.tap(find.byKey(const Key('home-reset-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('(1 of 2)'), findsNothing);
    expect(vm.resets, 1, reason: 'the press reaches homeReset(), which reports the reason and sends nothing');
  });
}
