// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - main.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
// =============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';

import 'state/robot_view_model.dart';
import 'ui/biometric_gate_screen.dart';
import 'ui/login_screen.dart';
import 'ui/main_screen.dart';

/// Attached to MaterialApp's own `scaffoldMessengerKey` below - the only way
/// _surfaceAsyncError() (errors caught outside Flutter's build/layout/paint
/// pipeline, so no BuildContext of their own to show a SnackBar with) can
/// still put something on screen instead of only reaching debugPrint, which
/// is a release-build no-op invisible to a real operator with no debugger
/// attached.
final GlobalKey<ScaffoldMessengerState> _rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

void _surfaceAsyncError(Object error) {
  _rootMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Text('Unexpected error: $error'),
      backgroundColor: const Color(0xFFB91C1C),
      duration: const Duration(seconds: 6),
    ),
  );
}

/// Global error handling: without this, an uncaught exception (a bad
/// server payload, a null a screen didn't guard against, ...) either shows
/// Flutter's own default ErrorWidget - a blank grey box with zero
/// information in a release build, red text only in debug - or, for an
/// error thrown outside Flutter's own build/layout/paint pipeline (a
/// fire-and-forget async callback with no try/catch), an unhandled
/// exception that crashes the whole isolate with no on-screen sign
/// anything went wrong at all. Neither gives the operator any indication
/// of what happened or a way to recover short of force-quitting the app.
///
/// debugPrint alone (the only channel this had before) is a real gap for
/// the 2 async-error paths below: it's a no-op in release builds with no
/// attached debugger/log tool, so an uncaught async error there used to be
/// genuinely invisible - the app would just silently stop doing whatever
/// that callback was supposed to do, with the operator seeing nothing.
/// _surfaceAsyncError() adds a real on-screen SnackBar via the root
/// ScaffoldMessengerKey for those 2 paths; the 3rd path (a widget failing
/// to build) already gets its own dedicated on-screen message via
/// ErrorWidget.builder/_CrashScreen below, so it isn't routed through
/// _surfaceAsyncError() too (that would double-report the same failure).
void main() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Uncaught Flutter error: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught async error: $error\n$stack');
    _surfaceAsyncError(error);
    return true; // handled - don't crash the isolate over it
  };
  ErrorWidget.builder = (details) => _CrashScreen(details: details);
  runZonedGuarded(
    () => runApp(const HydraUmcControlApp()),
    (error, stack) {
      debugPrint('Uncaught zone error: $error\n$stack');
      _surfaceAsyncError(error);
    },
  );
}

/// Replaces Flutter's own default ErrorWidget for a widget that fails to
/// build - a real message instead of a blank grey box, with a way back to
/// a known-good screen instead of a dead end.
class _CrashScreen extends StatefulWidget {
  final FlutterErrorDetails details;
  const _CrashScreen({required this.details});

  @override
  State<_CrashScreen> createState() => _CrashScreenState();
}

class _CrashScreenState extends State<_CrashScreen> {
  bool _copied = false;

  /// Copies the full exception + stack trace to the clipboard regardless of
  /// build mode - unlike the on-screen text above (kDebugMode-only, so a
  /// real operator on a release build could never actually see what broke),
  /// this is the one channel that gets enough detail out of the device for
  /// a real bug report without a debugger attached.
  Future<void> _copyDetails() async {
    final text = '${widget.details.exceptionAsString()}\n\n${widget.details.stack ?? ''}';
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) setState(() => _copied = true);
  }

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
              widget.details.exceptionAsString(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ],
          const SizedBox(height: 16),
          // Material(transparency) instead of relying on an ancestor: this
          // ErrorWidget can replace a widget anywhere in the tree, not
          // necessarily one already inside a Scaffold/Material ancestor.
          Material(
            type: MaterialType.transparency,
            child: TextButton.icon(
              onPressed: _copyDetails,
              icon: Icon(_copied ? Icons.check : Icons.copy, size: 16, color: _copied ? const Color(0xFF10B981) : Colors.white70),
              label: Text(_copied ? 'Copied' : 'Copy error details', style: TextStyle(color: _copied ? const Color(0xFF10B981) : Colors.white70)),
            ),
          ),
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
        scaffoldMessengerKey: _rootMessengerKey,
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
