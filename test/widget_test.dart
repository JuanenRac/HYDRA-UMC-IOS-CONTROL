// Basic smoke tests - confirm that the app builds, that it starts with the quiet start-up screen
// and that, once that is over and no session is active, it shows the login screen (the real
// starting state, not the default Flutter counter template this replaced).

import 'package:flutter_test/flutter_test.dart';

import 'package:hydra_umc_control/main.dart';

void main() {
  testWidgets('Starts with the quiet start-up screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const HydraUmcControlApp());
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('HYDRA-UMC'), findsOneWidget);
    expect(find.text('Server IP'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('Shows the login screen when not signed in', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const HydraUmcControlApp());
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.text('HYDRA-UMC'), findsOneWidget);
    expect(find.text('Server IP'), findsOneWidget);
  });
}
