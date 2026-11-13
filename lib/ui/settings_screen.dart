// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/settings_screen.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_version.dart';
import '../l10n/app_localizations.dart';
import '../network/tls_settings.dart';
import '../state/robot_view_model.dart';
import 'connection_diagnostics_dialog.dart';
import 'widgets/ble_dialog.dart';
import 'widgets/pairing_widgets.dart';
import 'widgets/security_dialog.dart';
import 'widgets/server_options_dialog.dart';

/// Everything the settings draw or decide from the view model, as one text: the list is redrawn when this text changes
/// and not for the metrics tick or the robots. A field the screen starts to read must be added here
/// (test/selector_rebuild_test.dart checks the fields it has now).
String settingsScreenShape(RobotViewModel vm) {
  final server = vm.activeServer;
  return [
    server?.displayName,
    server?.host,
    server?.port,
    vm.connectionStatus,
    vm.biometricAvailable,
    vm.biometricEnabled,
    vm.blockCommandsOnSavedData,
    vm.confirmPlay,
    vm.homeResetEnabled,
    vm.deadMan.enabled,
    vm.deadMan.blockOnBadLink,
    vm.deadMan.indicator,
    vm.pairingEnabled,
    vm.pushState,
    vm.pushNotifications,
    vm.jobAlertsEnabled,
    vm.surfaces.liveActivityRefusedBySystem,
    vm.liveActivityEnabled,
    vm.liveActivityPushState,
    vm.liveActivityPushEnabled,
    vm.watchEnabled,
    vm.watchAlertsEnabled,
    vm.presenceRelayEnabled,
    vm.voiceConfirmRelayEnabled,
    vm.dictationEnabled,
    vm.dictationOnline,
    vm.tlsSettings.pinnedFingerprint,
    vm.isAdmin,
    vm.languageOverride?.languageCode,
  ].join('|');
}

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
    // Redrawn when something this screen draws changes (see settingsScreenShape), not for the metrics tick.
    context.select<RobotViewModel, String>(settingsScreenShape);
    final vm = context.read<RobotViewModel>();
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
        SwitchListTile(
          secondary: const Icon(Icons.history_toggle_off),
          title: Text(l10n.settingsBlockCachedCommands),
          subtitle: Text(l10n.settingsBlockCachedCommandsSubtitle),
          value: vm.blockCommandsOnSavedData,
          onChanged: (value) => vm.setBlockCommandsOnSavedData(value),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.play_circle_outline),
          title: Text(l10n.settingsConfirmPlay),
          subtitle: Text(l10n.settingsConfirmPlaySubtitle),
          value: vm.confirmPlay,
          onChanged: (value) => vm.setConfirmPlay(value),
        ),
        SwitchListTile(
          key: const Key('settings-listen-only'),
          secondary: const Icon(Icons.hearing),
          title: Text(l10n.settingsListenOnly),
          subtitle: Text(l10n.settingsListenOnlySubtitle),
          value: vm.listenOnly,
          onChanged: (value) => vm.setListenOnly(value),
        ),
        if (vm.activeServer != null)
          SwitchListTile(
            key: const Key('settings-listen-only-server'),
            secondary: const Icon(Icons.hearing_disabled_outlined),
            title: Text(l10n.settingsListenOnlyServer),
            subtitle: Text(l10n.settingsListenOnlyServerSubtitle),
            value: vm.listenOnlyThisServer,
            onChanged: (value) => vm.setListenOnlyThisServer(value),
          ),
        // HOME/RESET moves the real robot to zero: off by default, two confirmations when on.
        SwitchListTile(
          key: const Key('settings-home-reset'),
          secondary: const Icon(Icons.home_outlined),
          title: Text(l10n.homeResetSwitchLabel),
          subtitle: Text(l10n.homeResetSwitchHint),
          value: vm.homeResetEnabled,
          onChanged: (value) => vm.setHomeResetEnabled(value),
        ),
        // The continuous jog moves a real robot while a button is held: off by default. The link switches belong to it.
        SwitchListTile(
          key: const Key('settings-dead-man'),
          secondary: const Icon(Icons.touch_app_outlined),
          title: Text(l10n.deadManSwitchLabel),
          subtitle: Text(l10n.deadManSwitchHint),
          value: vm.deadMan.enabled,
          onChanged: (value) => vm.setDeadManEnabled(value),
        ),
        SwitchListTile(
          key: const Key('settings-link-block'),
          secondary: const Icon(Icons.speed),
          title: Text(l10n.linkBlockSwitchLabel),
          subtitle: Text(l10n.linkBlockSwitchHint),
          value: vm.deadMan.blockOnBadLink,
          onChanged: (value) => vm.setLinkBlockOnBadLink(value),
        ),
        SwitchListTile(
          key: const Key('settings-link-indicator'),
          secondary: const Icon(Icons.network_ping),
          title: Text(l10n.linkIndicatorSwitchLabel),
          subtitle: Text(l10n.linkIndicatorSwitchHint),
          value: vm.deadMan.indicator,
          onChanged: (value) => vm.setLinkIndicator(value),
        ),
        // Pairing by link: off by default; the camera opens the link with this app or the person pastes it here.
        SwitchListTile(
          key: const Key('settings-pairing'),
          secondary: const Icon(Icons.qr_code_scanner),
          title: Text(l10n.pairingSwitchLabel),
          subtitle: Text(l10n.pairingSwitchHint),
          value: vm.pairingEnabled,
          onChanged: (value) => vm.setPairingEnabled(value),
        ),
        PairingPasteBox(vm: vm),
        const Divider(),
        SwitchListTile(
          key: const Key('settings-push'),
          secondary: const Icon(Icons.notifications_outlined),
          title: Text(l10n.pushTitle),
          subtitle: Text(switch (vm.pushState) {
            PushState.denied => l10n.pushDenied,
            PushState.serverOff => l10n.pushServerOff,
            PushState.failed => l10n.pushFailed,
            PushState.registered => l10n.pushRegistered,
            _ => l10n.pushSubtitle,
          }),
          value: vm.pushNotifications,
          onChanged: (value) => vm.setPushNotifications(value),
        ),
        // What reaches out of the app: every one starts off and has its own switch.
        SwitchListTile(
          key: const Key('settings-job-alerts'),
          secondary: const Icon(Icons.notifications_active_outlined),
          title: Text(l10n.jobAlertsTitle),
          subtitle: Text(l10n.jobAlertsSubtitle),
          value: vm.jobAlertsEnabled,
          onChanged: (value) async {
            final messenger = ScaffoldMessenger.maybeOf(context);
            final on = await vm.setJobAlerts(value);
            if (value && !on) messenger?.showSnackBar(SnackBar(content: Text(l10n.jobAlertsDenied)));
          },
        ),
        SwitchListTile(
          key: const Key('settings-live-activity'),
          secondary: const Icon(Icons.lock_clock),
          title: Text(l10n.liveActivityTitle),
          subtitle: Text(vm.surfaces.liveActivityRefusedBySystem ? l10n.liveActivityRefused : l10n.liveActivitySubtitle),
          value: vm.liveActivityEnabled,
          onChanged: (value) => vm.setLiveActivity(value),
        ),
        // The server refreshes the card while the app is suspended. Off by default, and only for a Live Activity that is on.
        SwitchListTile(
          key: const Key('settings-live-activity-push'),
          secondary: const Icon(Icons.cloud_sync_outlined),
          title: Text(l10n.liveActivityPushTitle),
          subtitle: Text(switch (vm.liveActivityPushState) {
            LiveActivityPushState.serverOff => l10n.liveActivityPushUnavailable,
            LiveActivityPushState.failed => l10n.liveActivityPushFailed,
            _ => l10n.liveActivityPushSubtitle,
          }),
          value: vm.liveActivityPushEnabled,
          onChanged: vm.liveActivityEnabled ? (value) => vm.setLiveActivityPush(value) : null,
        ),
        SwitchListTile(
          key: const Key('settings-watch'),
          secondary: const Icon(Icons.watch_outlined),
          title: Text(l10n.watchTitle),
          subtitle: Text(l10n.watchSubtitle),
          value: vm.watchEnabled,
          onChanged: (value) => vm.setWatch(value),
        ),
        // What the phone tells the watch and passes on from it (the first needs the option above too; the two relays are off).
        SwitchListTile(
          key: const Key('settings-watch-alerts'),
          secondary: const Icon(Icons.watch_later_outlined),
          title: Text(l10n.watchAlertsSwitchLabel),
          subtitle: Text(l10n.watchAlertsSwitchHint),
          value: vm.watchAlertsEnabled,
          onChanged: (value) => vm.setWatchAlertsEnabled(value),
        ),
        SwitchListTile(
          key: const Key('settings-presence-relay'),
          secondary: const Icon(Icons.person_pin_circle_outlined),
          title: Text(l10n.presenceRelaySwitchLabel),
          subtitle: Text(l10n.presenceRelaySwitchHint),
          value: vm.presenceRelayEnabled,
          onChanged: (value) => vm.setPresenceRelayEnabled(value),
        ),
        SwitchListTile(
          key: const Key('settings-voice-confirm-relay'),
          secondary: const Icon(Icons.record_voice_over_outlined),
          title: Text(l10n.voiceConfirmSwitchLabel),
          subtitle: Text(l10n.voiceConfirmSwitchHint),
          value: vm.voiceConfirmRelayEnabled,
          onChanged: (value) => vm.setVoiceConfirmRelayEnabled(value),
        ),
        SwitchListTile(
          key: const Key('settings-dictation'),
          secondary: const Icon(Icons.mic_none),
          title: Text(l10n.dictationTitle),
          subtitle: Text(l10n.dictationSubtitle),
          value: vm.dictationEnabled,
          onChanged: (value) => vm.setDictation(value),
        ),
        if (vm.dictationEnabled)
          SwitchListTile(
            key: const Key('settings-dictation-online'),
            secondary: const Icon(Icons.cloud_outlined),
            title: Text(l10n.dictationOnlineTitle),
            subtitle: Text(l10n.dictationOnlineSubtitle),
            value: vm.dictationOnline,
            onChanged: (value) => vm.setDictationOnline(value),
          ),
        ListTile(
          key: const Key('settings-diagnostics'),
          leading: const Icon(Icons.network_check),
          title: Text(l10n.diagTitle),
          subtitle: Text(l10n.diagIntro, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () => showConnectionDiagnosticsDialog(context, vm),
        ),
        ListTile(
          key: const Key('settings-security'),
          leading: const Icon(Icons.shield_outlined),
          title: Text(l10n.securityTitle),
          subtitle: Text(vm.tlsSettings.pinnedFingerprint.isNotEmpty
              ? TlsFingerprint.display(vm.tlsSettings.pinnedFingerprint)
              : l10n.securityIntro),
          onTap: () => showSecurityDialog(
            context,
            vm,
            host: server?.host ?? '',
            port: server?.port ?? 3000,
          ),
        ),
        ListTile(
          key: const Key('settings-bluetooth'),
          leading: const Icon(Icons.bluetooth),
          title: Text(l10n.bleTitle),
          subtitle: Text(l10n.bleIntro, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () => showBleDialog(context, vm),
        ),
        // The access options of the server itself: only an administrator can read or change them.
        if (vm.isAdmin)
          ListTile(
            key: const Key('settings-server-options'),
            leading: const Icon(Icons.admin_panel_settings_outlined),
            title: Text(l10n.serverOptionsTitle),
            subtitle: Text(l10n.serverOptionsIntro, maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: () => showServerOptionsDialog(context, vm),
          ),
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
      case 'pt':
        return 'Português';
      case 'en':
      default:
        return 'English';
    }
  }
}
