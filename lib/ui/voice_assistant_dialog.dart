// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/voice_assistant_dialog.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
//
// Lets the operator ask HYDRA-UMC-VOICE-UI a question or give it an order
// by typing - the same real POST /api/voice/turn route
// HYDRA-UMC-ANDROID-CONTROL's own in-app voice button and paired-Watch
// relay both use. Text input only for now: unlike Android's
// RecognizerIntent (a system intent, always present), on-device speech
// recognition on iOS needs the native Speech framework wired through a
// real plugin and Info.plist entries (NSSpeechRecognitionUsageDescription/
// NSMicrophoneUsageDescription) that this Windows-only development
// environment cannot build or verify against a real device/Xcode - see
// this repo's own established precedent (network/README notes on
// BLE/notifications/widget gaps) for not claiming an Xcode-only feature
// verified when it never actually ran on one. Typing already delivers the
// real request in full (ask a question or give an order); a mic button can
// follow once there's a way to actually build and test it.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../state/robot_view_model.dart';

class VoiceAssistantDialog extends StatefulWidget {
  const VoiceAssistantDialog({super.key});

  @override
  State<VoiceAssistantDialog> createState() => _VoiceAssistantDialogState();
}

class _VoiceAssistantDialogState extends State<VoiceAssistantDialog> {
  final _controller = TextEditingController();

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
              ),
              onSubmitted: (_) => _send(vm),
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
