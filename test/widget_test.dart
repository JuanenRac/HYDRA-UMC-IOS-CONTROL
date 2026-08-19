// Basic smoke test - confirms the app builds and shows the login screen
// when no session is active (the real starting state, not the default
// Flutter counter template this replaced).

import 'package:flutter_test/flutter_test.dart';

import 'package:hydra_umc_control/main.dart';

void main() {
  testWidgets('Shows the login screen when not signed in', (WidgetTester tester) async {
    await tester.pumpWidget(const HydraUmcControlApp());
    await tester.pump();

    expect(find.text('HYDRA-UMC CONTROL'), findsOneWidget);
    expect(find.text('Server IP'), findsOneWidget);
  });
}
