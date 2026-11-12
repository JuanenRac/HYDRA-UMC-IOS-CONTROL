// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - models/assistant_reply.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Reply shape for POST /api/voice/turn (the server relays to HYDRA-UMC-VOICE-UI), field for field the same as the reply of the
// Android app, so every client agrees on what a reply is. It never carries a robot command: a reply about a motion is only
// marked requiresConfirmation and is carried out through the main control screens.
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
