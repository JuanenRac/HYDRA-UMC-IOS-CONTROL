// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - main.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
// =============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'l10n/app_localizations.dart';
import 'state/robot_view_model.dart';
import 'ui/biometric_gate_screen.dart';
import 'ui/login_screen.dart';
import 'ui/main_screen.dart';
import 'ui/startup_screen.dart';
import 'ui/widgets/pairing_widgets.dart';

/// Attached to MaterialApp's own `scaffoldMessengerKey` below - the only way
/// _surfaceAsyncError() (errors caught outside Flutter's build/layout/paint
/// pipeline, so no BuildContext of their own to show a SnackBar with) can
/// still put something on screen instead of only reaching debugPrint, which
/// is a release-build no-op invisible to a real operator with no debugger
/// attached.
final GlobalKey<ScaffoldMessengerState> _rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// The navigator of the app, so the question of a pairing link can open over any screen (also the sign-in).
final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

void _surfaceAsyncError(Object error) {
  final context = _rootMessengerKey.currentContext;
  final message = context != null
      ? AppLocalizations.of(context)?.errorUnexpected('$error')
      : null;
  _rootMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Text(message ?? 'Unexpected error: $error'),
      backgroundColor: const Color(0xFFB91C1C),
      duration: const Duration(seconds: 6),
    ),
  );
}

/// Global error handling. An uncaught error is made visible: a widget that fails to build shows a message on the screen
/// (ErrorWidget.builder, _CrashScreen), and an error in an async callback outside the build pipeline shows a SnackBar through
/// the root ScaffoldMessengerKey (_surfaceAsyncError). The build failures do not go through _surfaceAsyncError, so one failure is
/// reported once. debugPrint stays as the log, but is silent in a release build.
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
    // AppLocalizations may not be resolvable yet if this widget somehow
    // renders before MaterialApp's own localization delegates are ready
    // (a build failure in the very first frame) - fall back to the
    // English literal rather than crashing the crash screen itself.
    final l10n = AppLocalizations.of(context);
    return Container(
      color: const Color(0xFF07090C),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFF43F5E), size: 48),
          const SizedBox(height: 12),
          Text(
            l10n?.crashMessage ?? 'Something went wrong displaying this screen.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
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
              label: Text(
                _copied ? (l10n?.crashCopied ?? 'Copied') : (l10n?.crashCopyDetails ?? 'Copy error details'),
                style: TextStyle(color: _copied ? const Color(0xFF10B981) : Colors.white70),
              ),
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
      create: (_) => RobotViewModel()..init(purgeStaleKeychain: true),
      // Only the language the person chose rebuilds the whole app: a state or a socket message never does.
      child: Selector<RobotViewModel, Locale?>(
        selector: (_, vm) => vm.languageOverride,
        builder: (context, languageOverride, _) => MaterialApp(
          title: 'HYDRA-UMC Control',
          scaffoldMessengerKey: _rootMessengerKey,
          navigatorKey: _rootNavigatorKey,
          builder: (context, child) => PairingDialogHost(vm: context.read<RobotViewModel>(), navigatorKey: _rootNavigatorKey, child: child ?? const SizedBox.shrink()),
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          // null lets Flutter resolve the OS locale itself against
          // supportedLocales (falling back to English) - only set once the
          // user has made an explicit choice in ui/settings_screen.dart,
          // see state/robot_view_model.dart's own languageOverride.
          locale: languageOverride,
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
      ),
    );
  }
}

/// Shows the login screen until a session is active. needsBiometricUnlock is checked first: a restored session behind the
/// biometric gate (init() in state/robot_view_model.dart) does not reach MainScreen just because isLoggedIn is already true.
///
/// Also the one WidgetsBindingObserver for the whole app: iOS suspends (and
/// may eventually kill) network sockets while the app is backgrounded, so
/// the WebSocket's own 3-second retry timer (network/hydra_websocket.dart)
/// isn't guaranteed to have noticed and reconnected by the time the user
/// switches back - resumed() asks RobotViewModel to reconnect explicitly
/// rather than relying on that timer alone. paused() actively closes the
/// socket and pauses the metrics poll instead of leaving both running
/// against a connection the OS may suspend or kill on its own schedule -
/// `inactive` (a system alert, the app switcher) is deliberately NOT
/// treated as backgrounded here, since it's normally momentary.
class _RootGate extends StatefulWidget {
  const _RootGate();

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> with WidgetsBindingObserver {
  /// The quiet start-up screen (ui/startup_screen.dart) shows once per launch, then the app.
  bool _introDone = false;

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
    } else if (state == AppLifecycleState.paused) {
      context.read<RobotViewModel>().pauseForBackground();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only the lock and the session decide this screen, not every change of the model.
    final (needsUnlock, loggedIn) = context.select<RobotViewModel, (bool, bool)>((vm) => (vm.needsBiometricUnlock, vm.isLoggedIn));
    if (!_introDone) {
      return StartupScreen(onDone: () => setState(() => _introDone = true));
    }
    if (needsUnlock) return const BiometricGateScreen();
    return loggedIn ? const MainScreen() : const LoginScreen();
  }
}
