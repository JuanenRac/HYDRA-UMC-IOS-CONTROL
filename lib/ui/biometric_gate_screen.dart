// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/biometric_gate_screen.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
//
// Shown by main.dart's _RootGate instead of MainScreen/LoginScreen while
// RobotViewModel.needsBiometricUnlock is true - a saved session exists but
// hasn't been unlocked with Face ID/Touch ID/Windows Hello yet (see
// state/robot_view_model.dart's own init()/unlockWithBiometrics()).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/robot_view_model.dart';

class BiometricGateScreen extends StatefulWidget {
  const BiometricGateScreen({super.key});

  @override
  State<BiometricGateScreen> createState() => _BiometricGateScreenState();
}

class _BiometricGateScreenState extends State<BiometricGateScreen> {
  bool _authenticating = false;
  bool _failed = false;

  Future<void> _unlock() async {
    setState(() {
      _authenticating = true;
      _failed = false;
    });
    final ok = await context.read<RobotViewModel>().unlockWithBiometrics();
    if (mounted) {
      setState(() {
        _authenticating = false;
        _failed = !ok;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RobotViewModel>();
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.fingerprint, size: 72, color: Color(0xFF00E5FF)),
              const SizedBox(height: 16),
              Text(
                'HYDRA-UMC CONTROL',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 2),
              ),
              const SizedBox(height: 4),
              Text(
                'Unlock to reconnect to ${vm.activeServer?.displayName ?? "the last server"}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 32),
              if (_failed)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('Authentication failed or cancelled.', style: TextStyle(color: Colors.redAccent)),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _authenticating ? null : _unlock,
                  icon: _authenticating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.fingerprint),
                  label: Text(_authenticating ? 'Waiting…' : 'Unlock'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _authenticating ? null : vm.cancelBiometricUnlock,
                child: const Text('Sign out instead'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
