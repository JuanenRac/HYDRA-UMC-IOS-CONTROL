// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/login_screen.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/server_info.dart';
import '../network/client_prefs.dart';
import '../network/discovery.dart';
import '../state/robot_view_model.dart';
import 'widgets/hydra_mark.dart';
import 'widgets/security_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _hostCtrl = TextEditingController(text: '192.168.1.100');
  final _portCtrl = TextEditingController(text: '3000');
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _isSubmitting = false;
  bool _skipMobileVpn = false;
  bool _showPassword = false;
  final _clientPrefs = ClientPrefs();

  StreamSubscription<ServerInfo>? _scanSub;
  StreamSubscription<ServerInfo>? _mdnsSub;

  @override
  void initState() {
    super.initState();
    _clientPrefs.loadSkipMobileAndVpnNetworks().then((value) {
      if (mounted) setState(() => _skipMobileVpn = value);
    });
  }

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
    final l10n = AppLocalizations.of(context)!;
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
    _scanSub =
        scanSubnets(
          lastHost: _hostCtrl.text.trim().isEmpty
              ? null
              : _hostCtrl.text.trim(),
          skipMobileAndVpn: _skipMobileVpn,
        ).listen(
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
                        l10n.loginScanTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: scanningNotifier,
                      builder: (context, isScanning, _) => isScanning
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.check_circle,
                              color: Colors.greenAccent,
                            ),
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
                              isScanning
                                  ? l10n.loginScanSearching
                                  : l10n.loginScanNoneFound,
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
                            subtitle: Text(
                              '${s.host}:${s.port} · ${s.product.isNotEmpty ? s.product : "HYDRA-UMC STUDIO"}',
                            ),
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
    if (host.isEmpty ||
        _userCtrl.text.trim().isEmpty ||
        _passCtrl.text.isEmpty) {
      return;
    }
    setState(() => _isSubmitting = true);
    final server = ServerInfo(
      host: host,
      port: port,
      username: _userCtrl.text.trim(),
      password: _passCtrl.text,
    );
    await context.read<RobotViewModel>().login(server);
    if (mounted) setState(() => _isSubmitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RobotViewModel>();
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A2A33), Color(0xFF07090C), Color(0xFF07090C)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const HydraMark(size: 84),
                    const SizedBox(height: 14),
                    const Text(
                      'HYDRA-UMC',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 5,
                        color: Color(0xFFEDF7FF),
                      ),
                    ),
                    Text(
                      l10n.startupTagline,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF8E9AAF),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Material(
                      color: const Color(0xFF0D1218),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: Color(0xFF1B3A46)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              l10n.loginSubtitle,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: const Color(0xFF8E9AAF)),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: TextField(
                                    controller: _hostCtrl,
                                    decoration: InputDecoration(
                                      labelText: l10n.loginServerIp,
                                      prefixIcon: const Icon(Icons.dns),
                                      border: const OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 1,
                                  child: TextField(
                                    controller: _portCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: l10n.loginPort,
                                      border: const OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: _isSubmitting
                                    ? null
                                    : _openScanSheet,
                                icon: const Icon(Icons.wifi_find, size: 18),
                                label: Text(l10n.loginScanNetwork),
                              ),
                            ),
                            CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(l10n.loginScanSkipMobileVpn),
                              value: _skipMobileVpn,
                              onChanged: (value) {
                                final v = value ?? false;
                                setState(() => _skipMobileVpn = v);
                                _clientPrefs.saveSkipMobileAndVpnNetworks(v);
                              },
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _userCtrl,
                              decoration: InputDecoration(
                                labelText: l10n.loginUsername,
                                prefixIcon: const Icon(Icons.person),
                                border: const OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _passCtrl,
                              obscureText: !_showPassword,
                              decoration: InputDecoration(
                                labelText: l10n.loginPassword,
                                prefixIcon: const Icon(Icons.lock),
                                suffixIcon: IconButton(
                                  tooltip: _showPassword
                                      ? l10n.loginHidePassword
                                      : l10n.loginShowPassword,
                                  icon: Icon(
                                    _showPassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                  onPressed: () => setState(
                                    () => _showPassword = !_showPassword,
                                  ),
                                ),
                                border: const OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              height: 52,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: _isSubmitting ? null : _submit,
                                icon: _isSubmitting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.login),
                                label: Text(
                                  _isSubmitting
                                      ? l10n.loginSigningIn
                                      : l10n.loginSignIn,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                key: const Key('login-security'),
                                onPressed: () => showSecurityDialog(
                                  context,
                                  vm,
                                  host: _hostCtrl.text.trim(),
                                  port: int.tryParse(_portCtrl.text.trim()) ?? 3000,
                                ),
                                icon: const Icon(Icons.shield_outlined, size: 18),
                                label: Text(l10n.securityOpen),
                              ),
                            ),
                            if (vm.lastError != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      size: 20,
                                      color: scheme.error,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        vm.lastError!.localize(l10n),
                                        style: TextStyle(color: scheme.error),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
