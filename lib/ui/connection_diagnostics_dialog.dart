// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/connection_diagnostics_dialog.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The connection diagnostics: the address and scheme, how the certificate is trusted, the versions of the server and of
// this app, the latency of a few small reads of GET /api/hydra-info, the grade of the link and the state of the live
// connection. A button copies a plain-text report that holds no password and no token (see
// util/connection_diagnostics.dart). Useful on the plant floor, where "it does not connect" has many causes.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/ios_feature_contract.dart';
import '../state/robot_view_model.dart';
import '../util/connection_diagnostics.dart';
import '../util/link_health.dart';

Future<void> showConnectionDiagnosticsDialog(BuildContext context, RobotViewModel vm) {
  return showDialog<void>(context: context, builder: (_) => ConnectionDiagnosticsDialog(vm: vm));
}

class ConnectionDiagnosticsDialog extends StatefulWidget {
  const ConnectionDiagnosticsDialog({super.key, required this.vm});
  final RobotViewModel vm;

  @override
  State<ConnectionDiagnosticsDialog> createState() => _ConnectionDiagnosticsDialogState();
}

class _ConnectionDiagnosticsDialogState extends State<ConnectionDiagnosticsDialog> {
  ConnectionDiagnostics? _result;
  bool _running = false;
  bool _noServer = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _running = true);
    final result = await widget.vm.runDiagnostics();
    if (!mounted) return;
    setState(() {
      _result = result;
      _noServer = result == null;
      _running = false;
    });
  }

  String _trust(AppLocalizations l10n, TrustMode mode) => switch (mode) {
        TrustMode.plainHttp => l10n.diagTrustPlain,
        TrustMode.pinnedFingerprint => l10n.diagTrustPinned,
        TrustMode.customAuthority => l10n.diagTrustCustom,
        TrustMode.systemCertificates => l10n.diagTrustSystem,
      };

  String _level(AppLocalizations l10n, LinkLevel level) => switch (level) {
        LinkLevel.unknown => l10n.diagLinkUnknown,
        LinkLevel.good => l10n.diagLinkGood,
        LinkLevel.poor => l10n.diagLinkPoor,
        LinkLevel.bad => l10n.diagLinkBad,
        LinkLevel.lost => l10n.diagLinkLost,
      };

  String _socket(AppLocalizations l10n, String status) => switch (status) {
        'connected' => l10n.connStatusConnected,
        'connecting' => l10n.connStatusConnecting,
        'error' => l10n.connStatusError,
        _ => l10n.connStatusDisconnected,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final result = _result;

    Widget row(String label, String value, {Key? key}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12))),
              Expanded(flex: 5, child: Text(value, key: key, style: const TextStyle(fontSize: 13))),
            ],
          ),
        );

    String ms(int? v) => v == null ? l10n.diagUnknown : '$v ms';

    return AlertDialog(
      title: Text(l10n.diagTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.diagIntro, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            if (_running) ...[
              Text(l10n.diagMeasuring),
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ] else if (_noServer)
              Text(l10n.diagNoServer)
            else if (result != null) ...[
              row(l10n.diagAddress, '${result.scheme}://${result.host}:${result.port}', key: const Key('diag-address')),
              row(l10n.diagTrust, _trust(l10n, result.trust)),
              if (result.pinnedFingerprint.isNotEmpty) row(l10n.diagFingerprint, result.pinnedFingerprint),
              row(l10n.diagServerApi, result.remoteApiVersion?.toString() ?? l10n.diagUnknown),
              row(l10n.diagServerApp, result.serverAppVersion ?? l10n.diagUnknown),
              row(l10n.diagClient, result.clientVersion),
              row(l10n.diagLatency, '${ms(result.minMs)} / ${ms(result.averageMs)} / ${ms(result.maxMs)}', key: const Key('diag-latency')),
              if (result.lost > 0) row('', l10n.diagProbesLost(result.lost)),
              row(l10n.diagLink, _level(l10n, result.level), key: const Key('diag-link')),
              row(l10n.diagWebsocket, _socket(l10n, result.websocket)),
              row(l10n.diagRole, result.role ?? l10n.diagUnknown),
              row(l10n.diagSavedData, result.showingSavedData ? l10n.diagYes : l10n.diagNo),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _running ? null : _run, child: Text(l10n.diagRun)),
        TextButton(
          key: const Key('diag-copy'),
          onPressed: result == null
              ? null
              : () async {
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  await Clipboard.setData(ClipboardData(text: result.report(maxLines: DiagnosticsContract.reportMaxLines)));
                  messenger?.showSnackBar(SnackBar(content: Text(l10n.diagCopied)));
                },
          child: Text(l10n.diagCopy),
        ),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.actionClose)),
      ],
    );
  }
}
