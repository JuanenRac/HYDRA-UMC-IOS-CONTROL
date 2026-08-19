// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/settings_screen.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/robot_view_model.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RobotViewModel>();
    final server = vm.activeServer;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: const Icon(Icons.dns),
          title: Text(server?.displayName ?? 'Not connected'),
          subtitle: Text(server != null ? '${server.host}:${server.port}' : ''),
        ),
        ListTile(
          leading: const Icon(Icons.wifi_tethering),
          title: Text('Status: ${vm.connectionStatus}'),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.redAccent),
          title: const Text('Sign Out'),
          onTap: () => vm.logout(),
        ),
      ],
    );
  }
}
