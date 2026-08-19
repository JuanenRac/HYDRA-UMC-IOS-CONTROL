// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/login_screen.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/server_info.dart';
import '../state/robot_view_model.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _hostCtrl = TextEditingController(text: '192.168.1.100');
  final _portCtrl = TextEditingController(text: '3000');
  final _userCtrl = TextEditingController(text: 'demo');
  final _passCtrl = TextEditingController(text: 'demo');
  bool _isSubmitting = false;

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 3000;
    if (host.isEmpty) return;
    setState(() => _isSubmitting = true);
    final server = ServerInfo(host: host, port: port, username: _userCtrl.text.trim(), password: _passCtrl.text);
    await context.read<RobotViewModel>().login(server);
    if (mounted) setState(() => _isSubmitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RobotViewModel>();
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.precision_manufacturing, size: 64, color: Color(0xFF00E5FF)),
                const SizedBox(height: 16),
                Text(
                  'HYDRA-UMC CONTROL',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 2),
                ),
                const SizedBox(height: 4),
                Text('Sign in to a HYDRA-UMC STUDIO server', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _hostCtrl,
                        decoration: const InputDecoration(labelText: 'Server IP', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _portCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _userCtrl,
                  decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 24),
                if (vm.lastError.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(vm.lastError, style: const TextStyle(color: Colors.redAccent)),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    icon: _isSubmitting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.login),
                    label: Text(_isSubmitting ? 'Signing in…' : 'Sign In'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
