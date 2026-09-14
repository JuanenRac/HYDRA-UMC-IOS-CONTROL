// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/main_screen_cached_state_banner_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
//
// I07: real widget coverage for MainScreen's own cached-data banner - the
// visible half of state/robot_view_model.dart's own isShowingCachedState.
// A logic-only test proving the flag flips correctly is not enough on its
// own: this proves an operator looking at the actual screen really sees
// (or does not see) the warning.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydra_umc_control/l10n/app_localizations.dart';
import 'package:hydra_umc_control/network/auth_prefs.dart';
import 'package:hydra_umc_control/state/robot_view_model.dart';
import 'package:hydra_umc_control/ui/main_screen.dart';

class _FakeSecureBackend implements SecureTokenBackend {
  final Map<String, String> store = {};
  @override
  Future<void> write(String key, String value) async => store[key] = value;
  @override
  Future<String?> read(String key) async => store[key];
  @override
  Future<void> delete(String key) async => store.remove(key);
}

Future<void> _pumpMainScreen(WidgetTester tester, RobotViewModel vm) async {
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: vm,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const MainScreen(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the cached-data banner when the view model is showing cached data', (tester) async {
    final vm = RobotViewModel(authPrefs: AuthPrefs(secureBackend: _FakeSecureBackend()));
    addTearDown(vm.dispose);
    vm.isShowingCachedState = true;
    vm.cachedStateSavedAt = DateTime(2026, 1, 1, 14, 32);

    await _pumpMainScreen(tester, vm);

    expect(find.textContaining('14:32'), findsOneWidget);
    expect(find.byIcon(Icons.history), findsOneWidget);
  });

  testWidgets('shows no cached-data banner once real, live data has replaced it', (tester) async {
    final vm = RobotViewModel(authPrefs: AuthPrefs(secureBackend: _FakeSecureBackend()));
    addTearDown(vm.dispose);
    vm.isShowingCachedState = false;

    await _pumpMainScreen(tester, vm);

    expect(find.byIcon(Icons.history), findsNothing);
  });
}
