// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - network/hydra_websocket.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
//
// /ws live-sync connection. On connect, the server immediately sends one
// {"type":"settings","payload":{...}} message with the current full
// state, then pushes the same shape to every connected client (sender
// included) whenever the state changes, from either a POST /api/settings,
// a POST /api/robot/:id/command (broadcast as "delta" - SAME payload
// shape, only the label differs), or a client sending the "settings"
// envelope back over its own socket.
//
// server.ts's /ws upgrade REQUIRES ?token= in the query string
// unconditionally (closes with code 1008 otherwise), so the token is
// always attached to the connection URL here rather than treated as
// optional - a socket opened without it would just get closed by the
// server immediately.
// =============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

enum WsStatus { connecting, connected, disconnected }

const Duration reconnectDelay = Duration(seconds: 3);

class HydraWebSocket {
  final String host;
  final int port;
  String? token;
  final void Function(WsStatus status) onStatus;
  final void Function(Map<String, dynamic> payload) onSettings;
  final void Function(String message) onError;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _closingByUser = false;
  Timer? _reconnectTimer;
  String? _lastPayloadJson;

  HydraWebSocket({
    required this.host,
    required this.port,
    this.token,
    required this.onStatus,
    required this.onSettings,
    required this.onError,
  });

  void connect() {
    _closingByUser = false;
    _openSocket();
  }

  void _openSocket() {
    onStatus(WsStatus.connecting);
    final base = 'ws://$host:$port/ws';
    final url = token != null ? '$base?token=$token' : base;
    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channel = channel;
      _sub = channel.stream.listen(
        (raw) => _handleMessage(raw as String),
        onDone: () {
          onStatus(WsStatus.disconnected);
          _channel = null;
          _scheduleReconnect();
        },
        onError: (Object e) {
          onStatus(WsStatus.disconnected);
          onError('WebSocket connection lost: $e');
          _channel = null;
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
      // WebSocketChannel.connect() doesn't confirm the handshake itself -
      // report "connected" once the stream is actually listening; a genuine
      // failure surfaces via onError/onDone above instead.
      onStatus(WsStatus.connected);
    } catch (e) {
      onStatus(WsStatus.disconnected);
      onError('WebSocket connect failed: $e');
      _scheduleReconnect();
    }
  }

  void _handleMessage(String raw) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return; // malformed frame - ignore rather than tear down the connection
    }
    final err = msg['error'];
    if (err is String && err.isNotEmpty) {
      onError(err);
      return;
    }
    final type = msg['type'];
    if (type != 'settings' && type != 'delta') return;
    final payload = msg['payload'];
    if (payload is! Map<String, dynamic>) return;
    final payloadJson = jsonEncode(payload);
    if (payloadJson == _lastPayloadJson) return; // our own echoed-back write
    _lastPayloadJson = payloadJson;
    onSettings(payload);
  }

  /// Sends the current full state over the socket - the WS-side half of
  /// the dual REST+WS write path (see state/robot_view_model.dart).
  bool send(Map<String, dynamic> payload) {
    final payloadJson = jsonEncode(payload);
    if (payloadJson == _lastPayloadJson) return true;
    final channel = _channel;
    if (channel == null) return false;
    channel.sink.add(jsonEncode({'type': 'settings', 'payload': payload}));
    _lastPayloadJson = payloadJson;
    return true;
  }

  void _scheduleReconnect() {
    if (_closingByUser) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(reconnectDelay, () {
      if (!_closingByUser) _openSocket();
    });
  }

  void disconnect() {
    _closingByUser = true;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    onStatus(WsStatus.disconnected);
  }
}
