// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/voice_assistant_dialog.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Lets the operator ask HYDRA-UMC-VOICE-UI a question or give it an order by typing, through POST /api/voice/turn (the route of
// the assistant of the Android app). Text input only: dictation is a separate native channel (state/external_surfaces.dart) that
// needs the Speech framework and its Info.plist entries on a real device.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../network/native_bridges.dart';
import '../state/robot_view_model.dart';

class VoiceAssistantDialog extends StatefulWidget {
  const VoiceAssistantDialog({super.key});

  @override
  State<VoiceAssistantDialog> createState() => _VoiceAssistantDialogState();
}

class _VoiceAssistantDialogState extends State<VoiceAssistantDialog> {
  final _controller = TextEditingController();
  bool _listening = false;
  String? _dictationNote;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send(RobotViewModel vm) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    vm.sendVoiceTurn(text);
    _controller.clear();
  }

  // Listens once and writes what was understood into the box. It never sends: the person reads it and presses Send.
  Future<void> _dictate(RobotViewModel vm, AppLocalizations l10n) async {
    if (_listening) {
      await vm.cancelDictation();
      return;
    }
    setState(() {
      _listening = true;
      _dictationNote = null;
    });
    final outcome = await vm.dictate();
    if (!mounted) return;
    setState(() {
      _listening = false;
      switch (outcome.status) {
        case SpeechStatus.ok:
          _controller.text = outcome.text;
          _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
          _dictationNote = l10n.dictationReview;
        case SpeechStatus.denied:
          _dictationNote = l10n.dictationDenied;
        case SpeechStatus.unavailable:
          _dictationNote = l10n.dictationUnavailable;
        case SpeechStatus.needsOnline:
          _dictationNote = l10n.dictationNeedsOnline;
        case SpeechStatus.empty:
          _dictationNote = l10n.dictationEmpty;
        case SpeechStatus.failed:
          _dictationNote = l10n.dictationFailed;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final vm = context.watch<RobotViewModel>();
    final reply = vm.latestAssistantReply;
    final busy = vm.voiceAssistantBusy;

    return AlertDialog(
      title: Text(l10n.voiceAssistantTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.voiceAssistantHint, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              enabled: !busy,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.voiceAssistantInputLabel,
                border: const OutlineInputBorder(),
                suffixIcon: vm.dictationEnabled
                    ? IconButton(
                        key: const Key('assistant-dictate'),
                        icon: Icon(_listening ? Icons.stop_circle_outlined : Icons.mic),
                        tooltip: _listening ? l10n.dictationStop : l10n.dictationMic,
                        onPressed: busy ? null : () => _dictate(vm, l10n),
                      )
                    : null,
              ),
              onSubmitted: (_) => _send(vm),
            ),
            if (_listening) Padding(padding: const EdgeInsets.only(top: 8), child: Text(l10n.dictationListening)),
            if (_dictationNote != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_dictationNote!, key: const Key('assistant-dictation-note'), style: Theme.of(context).textTheme.bodySmall),
              ),
            if (busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
            if (reply != null) ...[
              const SizedBox(height: 16),
              Text(reply.text, style: Theme.of(context).textTheme.bodyMedium),
              if (reply.requiresConfirmation) ...[
                const SizedBox(height: 4),
                Text(
                  l10n.voiceAssistantRequiresConfirmation,
                  style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            vm.clearAssistantReply();
            Navigator.of(context).pop();
          },
          child: Text(l10n.actionClose),
        ),
        FilledButton(
          onPressed: busy ? null : () => _send(vm),
          child: Text(l10n.voiceSend),
        ),
      ],
    );
  }
}
