// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/joystick_pad_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The jog pad is usable with a screen reader (every button has a spoken
// label in the app language) and every button is at least 44 points wide and
// tall.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydra_umc_control/l10n/app_localizations.dart';
import 'package:hydra_umc_control/ui/widgets/joystick_pad.dart';

Widget _app(Locale locale, void Function(int, int, int) onJog) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: JoystickPad(onJog: onJog))),
    );

void main() {
  testWidgets('every button is announced with its own label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(const Locale('en'), (a, b, c) {}));
    for (final label in [
      'Jog X minus, Y plus',
      'Jog Y plus',
      'Jog X plus, Y plus',
      'Jog X minus',
      'Jog X plus',
      'Jog X minus, Y minus',
      'Jog Y minus',
      'Jog X plus, Y minus',
      'Jog Z plus',
      'Jog Z minus',
    ]) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    handle.dispose();
  });

  testWidgets('the labels follow the app language', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(const Locale('es'), (a, b, c) {}));
    expect(find.bySemanticsLabel('Mover Z más'), findsOneWidget);
    expect(find.bySemanticsLabel('Mover X menos, Y más'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a screen-reader activation sends one step', (tester) async {
    final handle = tester.ensureSemantics();
    final jogs = <List<int>>[];
    await tester.pumpWidget(_app(const Locale('en'), (x, y, z) => jogs.add([x, y, z])));
    tester.semantics.tap(find.semantics.byLabel('Jog Y plus'));
    await tester.pump();
    expect(jogs, [
      [0, 1, 0],
    ]);
    handle.dispose();
  });

  testWidgets('every button is at least 44 x 44 points', (tester) async {
    await tester.pumpWidget(_app(const Locale('en'), (a, b, c) {}));
    final buttons = find.byType(Opacity); // one per button
    expect(buttons, findsNWidgets(10));
    for (final element in buttons.evaluate()) {
      final size = tester.getSize(find.byWidget(element.widget));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
  });
}
