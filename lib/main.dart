// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - main.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/robot_view_model.dart';
import 'ui/login_screen.dart';
import 'ui/main_screen.dart';

void main() {
  runApp(const HydraUmcControlApp());
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
class _RootGate extends StatelessWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RobotViewModel>();
    return vm.isLoggedIn ? const MainScreen() : const LoginScreen();
  }
}
