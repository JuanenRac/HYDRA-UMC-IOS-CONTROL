// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/login_screen.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/server_info.dart';
import '../network/discovery.dart';
import '../state/robot_view_model.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _hostCtrl = TextEditingController(text: '192.168.1.100');
  final _portCtrl = TextEditingController(text: '3000');
  final _userCtrl = TextEditingController(text: 'admin');
  final _passCtrl = TextEditingController(text: 'admin');
  bool _isSubmitting = false;

  StreamSubscription<ServerInfo>? _scanSub;
  StreamSubscription<ServerInfo>? _mdnsSub;

  @override
  void dispose() {
    _scanSub?.cancel();
    _mdnsSub?.cancel();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  /// Runs [discoverMdns] (real mDNS/Bonjour) and [scanSubnets] (brute-force
  /// subnet scan, see network/discovery.dart) at the same time against this
  /// device's own real local network, showing results live in a bottom
  /// sheet as either path finds them - so a user who doesn't already know
  /// the server's IP can find it instead of always needing to type it
  /// manually. Both paths report through the same [found] list, deduped by
  /// [ServerInfo.connectionId] since a server both paths agree on would
  /// otherwise show up twice.
  Future<void> _openScanSheet() async {
    final found = <ServerInfo>[];
    final foundNotifier = ValueNotifier<List<ServerInfo>>(const []);
    var mdnsDone = false;
    var subnetDone = false;
    final scanningNotifier = ValueNotifier<bool>(true);

    void addResult(ServerInfo server) {
      if (found.any((s) => s.connectionId == server.connectionId)) return;
      found.add(server);
      foundNotifier.value = List.of(found);
    }

    void checkDone() {
      if (mdnsDone && subnetDone) scanningNotifier.value = false;
    }

    _mdnsSub?.cancel();
    _mdnsSub = discoverMdns().listen(
      addResult,
      onDone: () {
        mdnsDone = true;
        checkDone();
      },
      onError: (_) {
        mdnsDone = true;
        checkDone();
      },
    );

    _scanSub?.cancel();
    _scanSub = scanSubnets(lastHost: _hostCtrl.text.trim().isEmpty ? null : _hostCtrl.text.trim()).listen(
      addResult,
      onDone: () {
        subnetDone = true;
        checkDone();
      },
      onError: (_) {
        subnetDone = true;
        checkDone();
      },
    );

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Scanning local network…',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: scanningNotifier,
                      builder: (context, isScanning, _) => isScanning
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check_circle, color: Colors.greenAccent),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ValueListenableBuilder<List<ServerInfo>>(
                    valueListenable: foundNotifier,
                    builder: (context, servers, _) {
                      if (servers.isEmpty) {
                        return ValueListenableBuilder<bool>(
                          valueListenable: scanningNotifier,
                          builder: (context, isScanning, _) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              isScanning ? 'Looking for HYDRA-UMC STUDIO servers…' : 'No servers found on this network.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        );
                      }
                      return ListView.builder(
                        shrinkWrap: true,
                        itemCount: servers.length,
                        itemBuilder: (context, i) {
                          final s = servers[i];
                          return ListTile(
                            leading: const Icon(Icons.dns),
                            title: Text(s.displayName),
                            subtitle: Text('${s.host}:${s.port} · ${s.product.isNotEmpty ? s.product : "HYDRA-UMC STUDIO"}'),
                            onTap: () {
                              _hostCtrl.text = s.host;
                              _portCtrl.text = s.port.toString();
                              Navigator.of(context).pop();
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mdnsDone) unawaited(_mdnsSub?.cancel());
    if (!subnetDone) unawaited(_scanSub?.cancel());
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
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _isSubmitting ? null : _openScanSheet,
                    icon: const Icon(Icons.wifi_find, size: 18),
                    label: const Text('Scan local network'),
                  ),
                ),
                const SizedBox(height: 4),
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
