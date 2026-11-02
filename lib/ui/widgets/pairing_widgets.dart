// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/widgets/pairing_widgets.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Port of HYDRA-UMC-ANDROID-CONTROL's PairingSection and PairingDialog (ui/LinkAndWatchSettings.kt). Pairing by link: the
// admin page of the server shows a QR code with its address and the fingerprint of its certificate; the camera of the phone
// opens the link with this app, or the person pastes it here. The app shows what it read and asks before it keeps anything.
// The switch is off by default and nothing is read while it is off.
// =============================================================================

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../network/tls_settings.dart';
import '../../state/robot_view_model.dart';

/// The box to paste a pairing link and the button that reads it; drawn only while the pairing switch is on.
class PairingPasteBox extends StatefulWidget {
  const PairingPasteBox({super.key, required this.vm});

  final RobotViewModel vm;

  @override
  State<PairingPasteBox> createState() => _PairingPasteBoxState();
}

class _PairingPasteBoxState extends State<PairingPasteBox> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: widget.vm,
      builder: (context, _) {
        if (!widget.vm.pairingEnabled) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('pairing-link-field'),
                controller: _controller,
                decoration: InputDecoration(labelText: l10n.pairingPasteLabel, border: const OutlineInputBorder(), isDense: true),
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('pairing-read-button'),
                onPressed: _controller.text.trim().isEmpty
                    ? null
                    : () async {
                        // Not a pairing link at all: said once and the text stays so it can be corrected.
                        final taken = await widget.vm.readPastedPairing(_controller.text);
                        if (taken) {
                          _controller.clear();
                          if (mounted) setState(() {});
                        }
                      },
                child: Text(l10n.pairingPasteButton),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// What the person is asked before a pairing is kept: the name, the address and, when there is one, the fingerprint that will be pinned.
Future<void> showPairingDialog(BuildContext context, RobotViewModel vm) async {
  final l10n = AppLocalizations.of(context)!;
  final offer = vm.pairingOffer;
  if (offer == null) return;
  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      key: const Key('pairing-dialog'),
      title: Text(l10n.pairingDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.pairingDialogMessage(offer.name, offer.host, offer.port)),
            const SizedBox(height: 8),
            if (offer.fingerprint != null) ...[
              Text(l10n.pairingDialogFingerprint(TlsFingerprint.display(offer.fingerprint!)), style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              Text(l10n.pairingDialogPinReplace, style: const TextStyle(fontSize: 12)),
            ] else
              Text(l10n.pairingDialogNoFingerprint, style: const TextStyle(fontSize: 12, color: Color(0xFFF59E0B))),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.playConfirmCancel)),
        FilledButton(key: const Key('pairing-confirm'), onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(l10n.pairingDialogConfirm)),
      ],
    ),
  );
  if (accepted == true) {
    await vm.confirmPairing();
  } else {
    vm.dismissPairing();
  }
}

/// Wraps the app and opens the question of the pairing over whatever screen is up (also the sign-in) as soon as there is an offer.
class PairingDialogHost extends StatefulWidget {
  const PairingDialogHost({super.key, required this.vm, required this.navigatorKey, required this.child});

  final RobotViewModel vm;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<PairingDialogHost> createState() => _PairingDialogHostState();
}

class _PairingDialogHostState extends State<PairingDialogHost> {
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    widget.vm.addListener(_check);
  }

  @override
  void didUpdateWidget(PairingDialogHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vm != widget.vm) {
      oldWidget.vm.removeListener(_check);
      widget.vm.addListener(_check);
    }
  }

  @override
  void dispose() {
    widget.vm.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (_showing || widget.vm.pairingOffer == null) return;
    _showing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final context = widget.navigatorKey.currentContext;
      if (context != null && context.mounted) await showPairingDialog(context, widget.vm);
      _showing = false;
      // Another offer may have arrived meanwhile.
      if (mounted) _check();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
