// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/settings_screen.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_version.dart';
import '../l10n/app_localizations.dart';
import '../state/robot_view_model.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
    final server = vm.activeServer;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: const Icon(Icons.dns),
          title: Text(server?.displayName ?? l10n.settingsNotConnected),
          subtitle: Text(server != null ? '${server.host}:${server.port}' : ''),
        ),
        ListTile(
          leading: const Icon(Icons.wifi_tethering),
          title: Text(l10n.settingsStatus(_connectionStatusLabel(l10n, vm.connectionStatus))),
        ),
        if (vm.biometricAvailable) ...[
          const Divider(),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: Text(l10n.settingsRequireBiometric),
            subtitle: Text(l10n.settingsRequireBiometricSubtitle),
            value: vm.biometricEnabled,
            onChanged: (value) => vm.setBiometricEnabled(value),
          ),
        ],
        const Divider(),
        ListTile(
          leading: const Icon(Icons.language),
          title: Text(l10n.settingsLanguage),
          trailing: DropdownButton<String?>(
            value: vm.languageOverride?.languageCode,
            underline: const SizedBox.shrink(),
            items: [
              DropdownMenuItem<String?>(value: null, child: Text(l10n.settingsLanguageSystem)),
              for (final locale in AppLocalizations.supportedLocales)
                DropdownMenuItem<String?>(
                  value: locale.languageCode,
                  child: Text(_languageDisplayName(locale.languageCode)),
                ),
            ],
            onChanged: (code) => vm.setLanguage(code),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.redAccent),
          title: Text(l10n.settingsSignOut),
          onTap: () => vm.logout(),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(l10n.settingsVersion),
          subtitle: const Text('$kAppVersion (build $kAppBuildNumber)'),
        ),
      ],
    );
  }

  static String _languageDisplayName(String code) {
    switch (code) {
      case 'es':
        return 'Español';
      case 'fr':
        return 'Français';
      case 'de':
        return 'Deutsch';
      case 'it':
        return 'Italiano';
      case 'ja':
        return '日本語';
      case 'zh':
        return '简体中文';
      case 'en':
      default:
        return 'English';
    }
  }
}
