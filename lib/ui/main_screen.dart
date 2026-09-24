// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/main_screen.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../state/hydra_error.dart';
import '../state/robot_view_model.dart';
import 'camera_screen.dart';
import 'control_screen.dart';
import 'dashboard_screen.dart';
import 'settings_screen.dart';
import 'telemetry_screen.dart';
import 'three_d_screen.dart';
import 'voice_assistant_dialog.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _index = 0;
  RobotViewModel? _vm;
  HydraError? _lastShownError;

  static const _screens = [
    DashboardScreen(),
    ControlScreen(),
    CameraScreen(),
    ThreeDScreen(),
    TelemetryScreen(),
    SettingsScreen(),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final vm = context.read<RobotViewModel>();
    if (!identical(_vm, vm)) {
      _vm?.removeListener(_onVmChanged);
      _vm = vm;
      _vm!.addListener(_onVmChanged);
    }
  }

  @override
  void dispose() {
    _vm?.removeListener(_onVmChanged);
    super.dispose();
  }

  /// Surfaces robot_view_model.dart's own lastError as a SnackBar regardless
  /// of which of the 5 tabs is active. Before this, lastError was only ever
  /// rendered on login_screen.dart - unreachable once isLoggedIn is true -
  /// so a failed command (a rejected STOP, a network error mid-jog, ...) set
  /// lastError correctly but nothing on screen ever showed it: the operator
  /// had no way to know a command they just sent hadn't actually gone
  /// through.
  void _onVmChanged() {
    if (!mounted) return;
    final err = _vm?.lastError;
    if (err != null && !identical(err, _lastShownError)) {
      _lastShownError = err;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err.localize(AppLocalizations.of(context)!)), backgroundColor: const Color(0xFFB91C1C)),
      );
    }
  }

  static String _connectionStatusLabel(AppLocalizations l10n, String status) {
    switch (status) {
      case 'connected':
        return l10n.connStatusConnected;
      case 'connecting':
        return l10n.connStatusConnecting;
      case 'error':
        return l10n.connStatusError;
      case 'disconnected':
      default:
        return l10n.connStatusDisconnected;
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RobotViewModel>();
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(vm.activeServer?.displayName ?? 'HYDRA-UMC CONTROL'),
        actions: [
          IconButton(
            icon: const Icon(Icons.mic),
            tooltip: l10n.voiceAssistantTitle,
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const VoiceAssistantDialog(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                _connectionStatusLabel(l10n, vm.connectionStatus).toUpperCase(),
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
      body: Column(
        children: [
          if (vm.isShowingCachedState) _CachedStateBanner(savedAt: vm.cachedStateSavedAt),
          Expanded(child: IndexedStack(index: _index, children: _screens)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.dashboard), label: l10n.navDashboard),
          NavigationDestination(icon: const Icon(Icons.gamepad), label: l10n.navControl),
          NavigationDestination(icon: const Icon(Icons.videocam), label: l10n.navCamera),
          NavigationDestination(icon: const Icon(Icons.view_in_ar), label: l10n.nav3d),
          NavigationDestination(icon: const Icon(Icons.terminal), label: l10n.navTelemetry),
          NavigationDestination(icon: const Icon(Icons.settings), label: l10n.navSettings),
        ],
      ),
    );
  }
}

/// visible while `state` still comes from network/state_cache.dart's
/// own persisted last-known tree rather than a real, live server response -
/// see robot_view_model.dart's own isShowingCachedState header comment.
/// Shown regardless of which of the 6 tabs is active, same as
/// MainScreen's own SnackBar error surface above, since a stale robot
/// state matters on every one of them, not only Dashboard.
class _CachedStateBanner extends StatelessWidget {
  final DateTime? savedAt;
  const _CachedStateBanner({required this.savedAt});

  static String _formatTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final time = savedAt == null ? '--:--' : _formatTime(savedAt!.toLocal());
    return Container(
      width: double.infinity,
      color: const Color(0xFFF59E0B),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.history, size: 16, color: Colors.black87),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.dashboardCachedDataBanner(time),
              style: const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
