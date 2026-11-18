// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/totp_screen_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The second-factor screen draws with a fake server and shows the words a person needs; the key stays hidden until asked for. The same cases
// as the Android app (TotpScreenRenderTest).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_umc_control/l10n/app_localizations.dart';
import 'package:hydra_umc_control/l10n/app_localizations_en.dart';
import 'package:hydra_umc_control/network/totp_api.dart';
import 'package:hydra_umc_control/state/totp_flow.dart';
import 'package:hydra_umc_control/ui/totp_screen.dart';
import 'package:hydra_umc_control/util/totp_rules.dart';

final _en = AppLocalizationsEn();
const _key = 'JBSWY3DPEHPK3PXP';

class _Fake implements TotpEndpoint {
  final bool enabled;
  final int left;
  _Fake(this.enabled, this.left);

  @override
  Future<TotpStatus> status() async => TotpStatus(enabled, left);
  @override
  Future<TotpEnrolment> begin(String password) async => TotpEnrolment(_key, 'otpauth://totp/HYDRA:ana?secret=$_key');
  @override
  Future<List<String>> confirm(String code) async => ['0a1b2-c3d4e'];
  @override
  Future<void> disable(String password, String code) async {}
  @override
  Future<List<String>> newRecoveryCodes(String password, String code) async => ['99999-88888'];
}

Future<TotpFlow> _open(WidgetTester tester, TotpEndpoint api) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  final flow = TotpFlow(() => api);
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: TotpScreen(flow: flow),
  ));
  await tester.pump();
  await tester.pump();
  return flow;
}

void main() {
  testWidgets('an account with the second factor off offers to turn it on', (tester) async {
    await _open(tester, _Fake(false, 0));
    expect(find.text(_en.totpTitle), findsWidgets);
    expect(find.text(_en.totpStatusOff), findsOneWidget);
    expect(find.byKey(const Key('totp-start')), findsOneWidget);
  });

  testWidgets('few recovery codes left shows the warning and the button for new ones', (tester) async {
    await _open(tester, _Fake(true, 1));
    expect(find.text(_en.totpStatusOn(1)), findsOneWidget);
    expect(find.text(_en.totpLowWarning(1)), findsOneWidget);
    expect(find.byKey(const Key('totp-new-codes')), findsOneWidget);
    expect(find.byKey(const Key('totp-turn-off')), findsOneWidget);
  });

  testWidgets('plenty of codes shows no warning', (tester) async {
    await _open(tester, _Fake(true, 8));
    expect(find.text(_en.totpStatusOn(8)), findsOneWidget);
    expect(find.text(_en.totpLowWarning(8)), findsNothing);
  });

  testWidgets('the key is hidden until the person asks to see it', (tester) async {
    await _open(tester, _Fake(false, 0));
    await tester.enterText(find.byType(TextField).first, 'pw');
    await tester.pump();
    await tester.tap(find.byKey(const Key('totp-start')));
    await tester.pump();
    await tester.pump();

    expect(find.text(_en.totpKeyShow), findsOneWidget);
    expect(find.text(TotpRules.groupedKey(_key)), findsNothing);
    await tester.tap(find.byKey(const Key('totp-key-toggle')));
    await tester.pump();
    expect(find.text(TotpRules.groupedKey(_key)), findsOneWidget);
    expect(find.text(_en.totpKeyHide), findsOneWidget);
  });

  testWidgets('the recovery codes are shown once and dropped when saved', (tester) async {
    final flow = await _open(tester, _Fake(false, 0));
    await flow.begin('pw');
    await flow.confirm('123456');
    await tester.pump();
    expect(find.text(TotpRules.maskedRecoveryCode), findsOneWidget);
    expect(find.text('0a1b2-c3d4e'), findsNothing);
    await tester.tap(find.byKey(const Key('totp-recovery-toggle')));
    await tester.pump();
    expect(find.text('0a1b2-c3d4e'), findsOneWidget);

    await tester.tap(find.byKey(const Key('totp-recovery-saved')));
    await tester.pump();
    expect(find.text('0a1b2-c3d4e'), findsNothing);
    expect(find.text(_en.totpDoneOn), findsOneWidget);
    expect(flow.recoveryCodes, isEmpty);
  });
}
