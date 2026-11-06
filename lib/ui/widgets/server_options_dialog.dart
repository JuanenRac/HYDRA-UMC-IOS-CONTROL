// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/widgets/server_options_dialog.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The access options of the server (administrators only): nine switches with
// where each value comes from. A value fixed by the environment of the server
// is locked, a change that lowers the protection is asked about first, and a
// server that predates an option simply does not show it.
// =============================================================================

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/server_security.dart';
import '../../state/robot_view_model.dart';

String serverOptionsFailureText(AppLocalizations l10n, ServerOptionsFailure failure) => switch (failure) {
      ServerOptionsFailure.unavailable => l10n.serverOptionsFailureUnavailable,
      ServerOptionsFailure.session => l10n.serverOptionsFailureSession,
      ServerOptionsFailure.forbidden => l10n.serverOptionsFailureForbidden,
      ServerOptionsFailure.network => l10n.serverOptionsFailureNetwork,
      ServerOptionsFailure.other => l10n.serverOptionsFailureOther,
    };

String protectionLoweringText(AppLocalizations l10n, ProtectionLowering lowering) => switch (lowering) {
      ProtectionLowering.healthOpen => l10n.serverOptionsHealthConfirm,
      ProtectionLowering.recordAddress => l10n.serverOptionsAddressConfirm,
      ProtectionLowering.cameraOpen => l10n.serverOptionsConfirmCamera,
      ProtectionLowering.wsQueryToken => l10n.serverOptionsConfirmWs,
      ProtectionLowering.logRedactionOff => l10n.serverOptionsConfirmLog,
      ProtectionLowering.voiceSignatureOff => l10n.serverOptionsConfirmVoice,
      ProtectionLowering.cameraCredentialsInArguments => l10n.serverOptionsConfirmCameraCredentials,
      ProtectionLowering.newInstallTlsOff => l10n.serverOptionsConfirmInstallTls,
    };

String optionSourceText(AppLocalizations l10n, OptionSource source) => switch (source) {
      OptionSource.env => l10n.serverOptionsSourceEnv,
      OptionSource.config => l10n.serverOptionsSourceConfig,
      OptionSource.defaultValue => l10n.serverOptionsSourceDefault,
    };

/// Opens the dialog; the caller shows it to an administrator only (the server refuses anyone else).
Future<void> showServerOptionsDialog(BuildContext context, RobotViewModel vm) =>
    showDialog<void>(context: context, builder: (_) => ServerOptionsDialog(vm: vm));

class ServerOptionsDialog extends StatefulWidget {
  final RobotViewModel vm;
  const ServerOptionsDialog({super.key, required this.vm});

  @override
  State<ServerOptionsDialog> createState() => _ServerOptionsDialogState();
}

class _ServerOptionsDialogState extends State<ServerOptionsDialog> {
  ServerSecurityOptions? _seen;
  ServerSecurityValues? _values;

  void _changed() {
    if (!mounted) return;
    setState(() {
      // New options from the server start the switches again from what it holds.
      if (!identical(_seen, widget.vm.serverOptions)) {
        _seen = widget.vm.serverOptions;
        _values = _seen?.toValues();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    widget.vm.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.vm.refreshServerOptions());
  }

  @override
  void dispose() {
    widget.vm.removeListener(_changed);
    super.dispose();
  }

  Widget _row(AppLocalizations l10n, String key, ServerOption? option, bool checked, String label, String? help,
      ValueChanged<bool> onChange) {
    if (option == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SwitchListTile(
        key: ValueKey('server-option-$key'),
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (help != null) Text(help),
            Text(optionSourceText(l10n, option.source), style: const TextStyle(fontSize: 11)),
          ],
        ),
        value: checked,
        onChanged: option.locked ? null : onChange,
      ),
    );
  }

  Future<void> _save(AppLocalizations l10n, ServerSecurityOptions current, ServerSecurityValues shown) async {
    final lowering = ServerSecurity.lowerings(current, shown);
    if (lowering.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          key: const ValueKey('server-options-confirm'),
          title: Text(l10n.serverOptionsConfirmTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final item in lowering) Text('- ${protectionLoweringText(l10n, item)}')],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: Text(l10n.securityCancel)),
            FilledButton(
              key: const ValueKey('server-options-confirm-yes'),
              onPressed: () => Navigator.of(dialog).pop(true),
              child: Text(l10n.serverOptionsConfirmYes),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await widget.vm.saveServerOptions(shown);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final vm = widget.vm;
    final current = vm.serverOptions;
    if (!identical(_seen, current)) {
      _seen = current;
      _values = current?.toValues();
    }
    final shown = _values;
    final failure = vm.serverOptionsFailure;
    const grey = TextStyle(color: Colors.grey, fontSize: 12);
    void set(ServerSecurityValues next) => setState(() => _values = next);

    return AlertDialog(
      key: const ValueKey('server-options-dialog'),
      title: Text(l10n.serverOptionsTitle),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.serverOptionsIntro, style: grey),
              if (failure != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(serverOptionsFailureText(l10n, failure),
                      key: const ValueKey('server-options-failure'),
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  key: const ValueKey('server-options-refresh'),
                  onPressed: vm.serverOptionsBusy ? null : () => vm.refreshServerOptions(),
                  child: Text(l10n.connectionsRefresh),
                ),
              ),
              if (current != null && shown != null)
                if (current.isEmpty)
                  Text(l10n.serverOptionsNone, style: grey)
                else ...[
                  _row(l10n, 'health', current.healthOpen, shown.healthOpen, l10n.serverOptionsHealthLabel,
                      l10n.serverOptionsHealthHelp, (v) => set(shown.copyWith(healthOpen: v))),
                  _row(l10n, 'stop', current.publishGlobalStop, shown.publishGlobalStop, l10n.serverOptionsStopLabel,
                      l10n.serverOptionsStopHelp, (v) => set(shown.copyWith(publishGlobalStop: v))),
                  _row(l10n, 'address', current.recordAddress, shown.recordAddress, l10n.serverOptionsAddressLabel,
                      l10n.serverOptionsAddressHelp, (v) => set(shown.copyWith(recordAddress: v))),
                  _row(l10n, 'camera', current.cameraOpen, shown.cameraOpen, l10n.serverOptionsCameraLabel,
                      l10n.serverOptionsExposureHelp, (v) => set(shown.copyWith(cameraOpen: v))),
                  _row(l10n, 'ws', current.wsQueryToken, shown.wsQueryToken, l10n.serverOptionsWsLabel, null,
                      (v) => set(shown.copyWith(wsQueryToken: v))),
                  _row(l10n, 'log', current.logRedaction, shown.logRedaction, l10n.serverOptionsLogLabel, null,
                      (v) => set(shown.copyWith(logRedaction: v))),
                  _row(l10n, 'voice', current.voiceSignature, shown.voiceSignature, l10n.serverOptionsVoiceLabel, null,
                      (v) => set(shown.copyWith(voiceSignature: v))),
                  _row(l10n, 'camera-credentials', current.cameraCredentialsViaEnv, shown.cameraCredentialsViaEnv,
                      l10n.serverOptionsCameraCredentialsLabel, l10n.serverOptionsInstallHelp,
                      (v) => set(shown.copyWith(cameraCredentialsViaEnv: v))),
                  _row(l10n, 'install-tls', current.newInstallTls, shown.newInstallTls, l10n.serverOptionsInstallTlsLabel,
                      null, (v) => set(shown.copyWith(newInstallTls: v))),
                  if (vm.serverOptionsSaved && failure == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(l10n.serverOptionsSaved, key: const ValueKey('server-options-saved'), style: grey),
                    ),
                ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.actionClose)),
        if (current != null && shown != null && !current.isEmpty)
          FilledButton(
            key: const ValueKey('server-options-save'),
            onPressed: !vm.serverOptionsBusy && ServerSecurity.patch(current, shown) != null ? () => _save(l10n, current, shown) : null,
            child: Text(l10n.serverOptionsSave),
          ),
      ],
    );
  }
}
