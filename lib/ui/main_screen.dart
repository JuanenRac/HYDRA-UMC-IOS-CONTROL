// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/main_screen.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/robot_view_model.dart';
import 'camera_screen.dart';
import 'control_screen.dart';
import 'dashboard_screen.dart';
import 'settings_screen.dart';
import 'three_d_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _index = 0;

  static const _screens = [
    DashboardScreen(),
    ControlScreen(),
    CameraScreen(),
    ThreeDScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RobotViewModel>();
    return Scaffold(
      appBar: AppBar(
        title: Text(vm.activeServer?.displayName ?? 'HYDRA-UMC CONTROL'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                vm.connectionStatus.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: vm.connectionStatus == 'connected' ? const Color(0xFF10B981) : const Color(0xFFF43F5E),
                ),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.gamepad), label: 'Control'),
          NavigationDestination(icon: Icon(Icons.videocam), label: 'Camera'),
          NavigationDestination(icon: Icon(Icons.view_in_ar), label: '3D'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
