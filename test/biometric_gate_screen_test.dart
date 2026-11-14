// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/biometric_gate_screen_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The unlock screen shown while a saved session waits for Face ID or Touch ID:
// it names the server, asks for the prompt, says plainly when the prompt did
// not unlock, disables both buttons while the prompt is open and lets the
// person sign out instead. The view model is a stand-in that answers the
// prompt the test decides; the words are the ones of the eight languages.
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hydra_umc_control/l10n/app_localizations.dart';
import 'package:hydra_umc_control/models/server_info.dart';
import 'package:hydra_umc_control/network/auth_prefs.dart';
import 'package:hydra_umc_control/state/robot_view_model.dart';
import 'package:hydra_umc_control/ui/biometric_gate_screen.dart';

class _Backend implements SecureTokenBackend {
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> delete(String key) async {}
}

/// Answers the prompt with whatever the test completes, and counts the asks.
class _GateVm extends RobotViewModel {
  _GateVm() : super(authPrefs: AuthPrefs(secureBackend: _Backend()));

  final List<String> reasons = [];
  Completer<bool> prompt = Completer<bool>();
  int signedOutInstead = 0;

  @override
  Future<bool> unlockWithBiometrics(String reason) {
    reasons.add(reason);
    return prompt.future;
  }

  @override
  void cancelBiometricUnlock() => signedOutInstead++;
}

Future<void> _show(WidgetTester tester, _GateVm vm, {Locale locale = const Locale('en')}) async {
  await tester.pumpWidget(ChangeNotifierProvider<RobotViewModel>.value(
    value: vm,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const BiometricGateScreen(),
    ),
  ));
  await tester.pump();
}

Future<AppLocalizations> _words(String language) => AppLocalizations.delegate.load(Locale(language));

void main() {
  testWidgets('it names the server and offers the prompt and the way out', (tester) async {
    final vm = _GateVm();
    vm.activeServer = const ServerInfo(host: '192.168.0.50', port: 18080, useTls: false);
    await _show(tester, vm);
    final l10n = await _words('en');
    expect(find.text('HYDRA-UMC CONTROL'), findsOneWidget);
    expect(find.text(l10n.biometricUnlockToReconnect(vm.activeServer!.displayName)), findsOneWidget);
    expect(find.text(l10n.biometricUnlock), findsOneWidget);
    expect(find.text(l10n.biometricSignOutInstead), findsOneWidget);
    expect(find.text(l10n.biometricAuthFailed), findsNothing, reason: 'no failure is shown before the first try');
    expect(vm.reasons, isEmpty, reason: 'the prompt is asked for by the person, not on its own');
  });

  testWidgets('with no server known it says the last server', (tester) async {
    final vm = _GateVm();
    await _show(tester, vm);
    final l10n = await _words('en');
    expect(find.text(l10n.biometricUnlockToReconnect(l10n.biometricLastServerFallback)), findsOneWidget);
  });

  testWidgets('while the prompt is open both buttons wait and the words say so', (tester) async {
    final vm = _GateVm();
    await _show(tester, vm);
    final l10n = await _words('en');
    await tester.tap(find.text(l10n.biometricUnlock));
    await tester.pump();
    expect(vm.reasons, [l10n.biometricReason], reason: 'the person is told why in their language');
    expect(find.text(l10n.biometricWaiting), findsOneWidget);
    expect(find.text(l10n.biometricUnlock), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Neither button does anything while the prompt is open.
    await tester.tap(find.text(l10n.biometricWaiting), warnIfMissed: false);
    await tester.tap(find.text(l10n.biometricSignOutInstead), warnIfMissed: false);
    await tester.pump();
    expect(vm.reasons, hasLength(1));
    expect(vm.signedOutInstead, 0);
    vm.prompt.complete(true);
    await tester.pump();
  });

  testWidgets('a refused prompt shows the failure and can be tried again', (tester) async {
    final vm = _GateVm();
    await _show(tester, vm);
    final l10n = await _words('en');
    await tester.tap(find.text(l10n.biometricUnlock));
    await tester.pump();
    vm.prompt.complete(false);
    await tester.pump();
    expect(find.text(l10n.biometricAuthFailed), findsOneWidget);
    expect(find.text(l10n.biometricUnlock), findsOneWidget, reason: 'the button is back');

    vm.prompt = Completer<bool>();
    await tester.tap(find.text(l10n.biometricUnlock));
    await tester.pump();
    expect(find.text(l10n.biometricAuthFailed), findsNothing, reason: 'a new try clears the old failure');
    expect(vm.reasons, hasLength(2));
    vm.prompt.complete(true);
    await tester.pump();
    expect(find.text(l10n.biometricAuthFailed), findsNothing);
  });

  testWidgets('signing out instead calls the escape hatch of the view model', (tester) async {
    final vm = _GateVm();
    await _show(tester, vm);
    final l10n = await _words('en');
    await tester.tap(find.text(l10n.biometricSignOutInstead));
    await tester.pump();
    expect(vm.signedOutInstead, 1);
    expect(vm.reasons, isEmpty);
  });

  testWidgets('every language has the words of the screen', (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      final vm = _GateVm();
      await _show(tester, vm, locale: locale);
      final l10n = await _words(locale.languageCode);
      expect(find.text(l10n.biometricUnlock), findsOneWidget, reason: locale.languageCode);
      expect(find.text(l10n.biometricSignOutInstead), findsOneWidget, reason: locale.languageCode);
      expect(l10n.biometricReason.trim(), isNotEmpty, reason: locale.languageCode);
      expect(l10n.biometricAuthFailed.trim(), isNotEmpty, reason: locale.languageCode);
      expect(l10n.biometricWaiting.trim(), isNotEmpty, reason: locale.languageCode);
    }
  });
}
