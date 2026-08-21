// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - main.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
// =============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/robot_view_model.dart';
import 'ui/biometric_gate_screen.dart';
import 'ui/login_screen.dart';
import 'ui/main_screen.dart';

/// Global error handling: without this, an uncaught exception (a bad
/// server payload, a null a screen didn't guard against, ...) either shows
/// Flutter's own default ErrorWidget - a blank grey box with zero
/// information in a release build, red text only in debug - or, for an
/// error thrown outside Flutter's own build/layout/paint pipeline (a
/// fire-and-forget async callback with no try/catch), an unhandled
/// exception that crashes the whole isolate with no on-screen sign
/// anything went wrong at all. Neither gives the operator any indication
/// of what happened or a way to recover short of force-quitting the app.
void main() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Uncaught Flutter error: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught async error: $error\n$stack');
    return true; // handled - don't crash the isolate over it
  };
  ErrorWidget.builder = (details) => _CrashScreen(details: details);
  runZonedGuarded(
    () => runApp(const HydraUmcControlApp()),
    (error, stack) => debugPrint('Uncaught zone error: $error\n$stack'),
  );
}

/// Replaces Flutter's own default ErrorWidget for a widget that fails to
/// build - a real message instead of a blank grey box, with a way back to
/// a known-good screen instead of a dead end.
class _CrashScreen extends StatelessWidget {
  final FlutterErrorDetails details;
  const _CrashScreen({required this.details});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF07090C),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFF43F5E), size: 48),
          const SizedBox(height: 12),
          const Text(
            'Something went wrong displaying this screen.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white),
          ),
          if (kDebugMode) ...[
            const SizedBox(height: 8),
            Text(
              details.exceptionAsString(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class HydraUmcControlApp extends StatelessWidget {
  const HydraUmcControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RobotViewModel()..init(),
      child: MaterialApp(
        title: 'HYDRA-UMC Control',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF07090C),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF00E5FF),
            brightness: Brightness.dark,
            surface: const Color(0xFF12161C),
          ),
          useMaterial3: true,
        ),
        home: const _RootGate(),
      ),
    );
  }
}

/// Shows the login screen until a session is active - mirrors
/// HYDRA-UMC-ANDROID-CONTROL's own MainActivity gating on isLoggedIn.
/// needsBiometricUnlock is checked first: a restored session with the
/// biometric gate enabled (see state/robot_view_model.dart's own init())
/// must not fall through to MainScreen just because isLoggedIn is already
/// true.
///
/// Also the one WidgetsBindingObserver for the whole app: iOS suspends (and
/// may eventually kill) network sockets while the app is backgrounded, so
/// the WebSocket's own 3-second retry timer (network/hydra_websocket.dart)
/// isn't guaranteed to have noticed and reconnected by the time the user
/// switches back - resumed() asks RobotViewModel to reconnect explicitly
/// rather than relying on that timer alone.
class _RootGate extends StatefulWidget {
  const _RootGate();

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<RobotViewModel>().reconnectIfNeeded();
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RobotViewModel>();
    if (vm.needsBiometricUnlock) return const BiometricGateScreen();
    return vm.isLoggedIn ? const MainScreen() : const LoginScreen();
  }
}
