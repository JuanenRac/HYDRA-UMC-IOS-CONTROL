// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/totp_screen.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The second sign-in factor of the signed-in account, opened from Settings: turn it on (password, then the key to put in an authenticator
// app, then the first code, then the recovery codes, shown once), see how many recovery codes are left, make new ones and turn it off. It is off
// for every account until its owner turns it on. The same steps, states and texts as the Android app (ui/TotpSection.kt).
//
// The key and the codes are hidden until the person asks to see them, are never put in the saved state of the screen, and are hidden again
// when the app leaves the foreground (so the app switcher never shows them).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../l10n/app_localizations.dart';
import '../state/totp_flow.dart';
import '../util/totp_rules.dart';

/// The text of a refusal of one of the second-factor calls.
String totpFailureText(AppLocalizations l10n, TotpFailure failure) {
  switch (failure.kind) {
    case TotpFailureKind.unsupported:
      return l10n.totpErrorUnsupported;
    case TotpFailureKind.password:
      return l10n.totpErrorPassword;
    case TotpFailureKind.code:
      return l10n.totpErrorCode;
    case TotpFailureKind.wait:
      return l10n.totpErrorWait(failure.number ?? TotpRules.defaultWaitSeconds);
    case TotpFailureKind.already:
      return l10n.totpErrorAlready;
    case TotpFailureKind.forbidden:
      return l10n.totpErrorForbidden;
    case TotpFailureKind.http:
      return l10n.totpErrorHttp(failure.number ?? 0);
    case TotpFailureKind.network:
      return l10n.totpErrorNetwork;
  }
}

class TotpScreen extends StatefulWidget {
  final TotpFlow flow;
  const TotpScreen({super.key, required this.flow});

  @override
  State<TotpScreen> createState() => _TotpScreenState();
}

class _TotpScreenState extends State<TotpScreen> with WidgetsBindingObserver {
  final _passwordCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _revealed = false;
  bool _showPassword = false;
  TotpStep? _lastStep;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.flow.addListener(_onFlow);
    // after the first frame: the flow tells its listeners as soon as it starts to read
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.flow.load();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.flow.removeListener(_onFlow);
    // what the person typed or was shown goes with the screen
    widget.flow.clear();
    _passwordCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  // The app switcher takes a picture of the screen when the app leaves the foreground: the key and the codes are hidden by then.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _revealed) setState(() => _revealed = false);
  }

  // Every change of step starts the fields and the reveal over.
  void _onFlow() {
    if (_lastStep != widget.flow.step) {
      _lastStep = widget.flow.step;
      _passwordCtrl.clear();
      _codeCtrl.clear();
      _revealed = false;
    }
    if (mounted) setState(() {});
  }

  Widget _secretField(AppLocalizations l10n, TextEditingController ctrl, String label, {required bool password}) {
    return TextField(
      controller: ctrl,
      enabled: !widget.flow.busy,
      obscureText: password ? !_showPassword : true,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.visiblePassword,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: password
            ? IconButton(
                tooltip: _showPassword ? l10n.loginHidePassword : l10n.loginShowPassword,
                icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              )
            : null,
      ),
    );
  }

  Future<void> _copyKey(AppLocalizations l10n) async {
    await Clipboard.setData(ClipboardData(text: widget.flow.secret));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.totpKeyCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final flow = widget.flow;
    final busy = flow.busy;
    final failure = flow.failure;
    final notice = flow.notice;
    final password = _passwordCtrl.text;
    final code = _codeCtrl.text;
    final children = <Widget>[
      Text(l10n.totpIntro, style: Theme.of(context).textTheme.bodySmall),
      if (failure != null)
        Semantics(
          liveRegion: true,
          child: Text(totpFailureText(l10n, failure), style: TextStyle(color: scheme.error)),
        ),
      if (notice != null)
        Semantics(
          liveRegion: true,
          child: Text(switch (notice) {
            TotpNotice.turnedOn => l10n.totpDoneOn,
            TotpNotice.turnedOff => l10n.totpDoneOff,
            TotpNotice.newCodes => l10n.totpDoneNewCodes,
          }),
        ),
    ];

    switch (flow.step) {
      case TotpStep.loading:
        children.add(Text(l10n.totpLoading));
        if (failure != null && !busy) {
          children.add(TextButton(onPressed: flow.load, child: Text(l10n.totpRetry)));
        }
      case TotpStep.unsupported:
        break; // the refusal above already says it
      case TotpStep.off:
        children.addAll([
          Text(l10n.totpStatusOff),
          _secretField(l10n, _passwordCtrl, l10n.totpPasswordLabel, password: true),
          FilledButton(
            key: const Key('totp-start'),
            onPressed: busy || password.isEmpty ? null : () => flow.begin(_passwordCtrl.text),
            child: Text(l10n.totpStart),
          ),
        ]);
      case TotpStep.enrolling:
        children.addAll([
          Semantics(header: true, child: Text(l10n.totpKeyTitle, style: Theme.of(context).textTheme.titleSmall)),
          Text(l10n.totpScanHint, style: Theme.of(context).textTheme.bodySmall),
          Semantics(
            label: _revealed ? null : l10n.totpKeyHiddenDesc,
            excludeSemantics: !_revealed,
            child: Text(
              _revealed ? TotpRules.groupedKey(flow.secret) : TotpRules.maskedKey(flow.secret),
              key: const Key('totp-key'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          TextButton(
            key: const Key('totp-key-toggle'),
            onPressed: () => setState(() => _revealed = !_revealed),
            child: Text(_revealed ? l10n.totpKeyHide : l10n.totpKeyShow),
          ),
          OutlinedButton(onPressed: () => _copyKey(l10n), child: Text(l10n.totpCopyKey)),
          _secretField(l10n, _codeCtrl, l10n.totpCodeLabel, password: false),
          Row(children: [
            Expanded(
              child: FilledButton(
                key: const Key('totp-confirm'),
                onPressed: busy || code.trim().isEmpty ? null : () => flow.confirm(_codeCtrl.text),
                child: Text(l10n.totpConfirm),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: busy ? null : flow.cancelEnrolment, child: Text(l10n.totpCancel)),
          ]),
        ]);
      case TotpStep.recovery:
        children.addAll([
          Semantics(header: true, child: Text(l10n.totpRecoveryTitle, style: Theme.of(context).textTheme.titleSmall)),
          Text(l10n.totpRecoveryHint, style: Theme.of(context).textTheme.bodySmall),
          Semantics(
            label: _revealed ? null : l10n.totpRecoveryHiddenDesc,
            excludeSemantics: !_revealed,
            container: true,
            child: Column(
              key: const Key('totp-recovery'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in flow.recoveryCodes)
                  Text(_revealed ? item : TotpRules.maskedRecoveryCode, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          TextButton(
            key: const Key('totp-recovery-toggle'),
            onPressed: () => setState(() => _revealed = !_revealed),
            child: Text(_revealed ? l10n.totpRecoveryHide : l10n.totpRecoveryShow),
          ),
          FilledButton(
            key: const Key('totp-recovery-saved'),
            onPressed: flow.acknowledgeRecovery,
            child: Text(l10n.totpRecoverySaved),
          ),
        ]);
      case TotpStep.on:
        final ready = !busy && password.isNotEmpty && code.trim().isNotEmpty;
        children.addAll([
          Text(l10n.totpStatusOn(flow.recoveryLeft)),
          if (flow.recoveryLow)
            Semantics(
              liveRegion: true,
              child: Text(l10n.totpLowWarning(flow.recoveryLeft), style: TextStyle(color: scheme.error)),
            ),
          _secretField(l10n, _passwordCtrl, l10n.totpPasswordLabel, password: true),
          _secretField(l10n, _codeCtrl, l10n.totpTurnOffCodeLabel, password: false),
          FilledButton(
            key: const Key('totp-new-codes'),
            onPressed: ready ? () => flow.newRecoveryCodes(_passwordCtrl.text, _codeCtrl.text) : null,
            child: Text(l10n.totpNewCodes),
          ),
          Text(l10n.totpNewCodesHint, style: Theme.of(context).textTheme.bodySmall),
          FilledButton(
            key: const Key('totp-turn-off'),
            onPressed: ready ? () => flow.disable(_passwordCtrl.text, _codeCtrl.text) : null,
            child: Text(l10n.totpTurnOff),
          ),
        ]);
    }

    return Scaffold(
      appBar: AppBar(title: Semantics(header: true, child: Text(l10n.totpTitle))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final child in children) Padding(padding: const EdgeInsets.only(bottom: 12), child: child),
          ],
        ),
      ),
    );
  }
}
