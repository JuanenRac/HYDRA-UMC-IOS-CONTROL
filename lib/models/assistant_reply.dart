// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - models/assistant_reply.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
//
// Reply shape for POST /api/voice/turn (Server relays to HYDRA-UMC-VOICE-UI)
// - mirrors HYDRA-UMC-ANDROID-CONTROL's own wear/WatchVoiceRelayContract.kt
// WatchAssistantReply field-for-field, so all clients agree on what a
// voice-assistant reply is even though none of them share code. Never
// carries a robot command: a motion-related reply is only ever marked
// requiresConfirmation, to be actioned through this app's own primary
// control UI, not applied automatically.
// =============================================================================

class AssistantReply {
  final String requestId;
  final String text;
  final String level;
  final bool speak;
  final bool requiresConfirmation;

  const AssistantReply({
    required this.requestId,
    required this.text,
    required this.level,
    required this.speak,
    required this.requiresConfirmation,
  });

  factory AssistantReply.fromJson(Map<String, dynamic> json) {
    if (json['type'] != 'assistant_reply') {
      throw const FormatException('unexpected voice response type');
    }
    return AssistantReply(
      requestId: json['requestId'] as String,
      text: json['text'] as String,
      level: json['level'] as String,
      speak: json['speak'] as bool,
      requiresConfirmation: json['requiresConfirmation'] as bool,
    );
  }
}
