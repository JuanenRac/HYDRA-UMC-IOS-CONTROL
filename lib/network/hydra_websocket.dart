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
  /// A real targeted delta (server.ts's own broadcastRobotDelta(), sent
  /// only once this connection declares schema 2 via ?remoteApiVersion=2
  /// below - see DISEÑO_SYNC_DELTAS.txt section 2/3). Optional: a caller
  /// that doesn't pass this still gets every delta folded into onSettings
  /// as a full-tree replace, same as before this existed.
  final void Function(Map<String, dynamic> delta)? onDelta;

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
    this.onDelta,
  });

  void connect() {
    _closingByUser = false;
    unawaited(_openSocket());
  }

  Future<void> _openSocket() async {
    onStatus(WsStatus.connecting);
    final base = 'ws://$host:$port/ws';
    // remoteApiVersion=2 declares this connection understands a real
    // targeted delta - reused from GET /api/hydra-info's own field name
    // (see DISEÑO_SYNC_DELTAS.txt section 3/8q3). A server that doesn't
    // recognize it just keeps sending the full tree under "delta" like
    // before, so this is safe regardless of server version.
    final url = token != null ? '$base?token=$token&remoteApiVersion=2' : base;
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
      // WebSocketChannel.connect() returns immediately and connects lazily -
      // the previous version of this code reported "connected" right here,
      // before the handshake even started, so a bad host/port/refused
      // connection still showed a green "CONNECTED" status in the UI until
      // the onDone/onError callbacks above eventually fired. channel.ready
      // is the real handshake signal (completes once the connection is
      // actually open, throws if it never completes) - wait for it before
      // reporting connected, exactly like this fix's own external audit
      // finding (#059/#254) described. A failure here still flows through
      // the same onError/_scheduleReconnect path as a message-time failure.
      await channel.ready;
      if (_closingByUser || _channel != channel) return;
      onStatus(WsStatus.connected);
    } catch (e) {
      onStatus(WsStatus.disconnected);
      onError('WebSocket connect failed: $e');
      _channel = null;
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
    if (type == 'delta' && msg['schema'] == 2 && msg.containsKey('robotId')) {
      final handler = onDelta;
      if (handler != null) {
        handler(msg);
        return;
      }
      // No onDelta wired up - fall through and let it hit the `type !=
      // 'settings' && type != 'delta'` check below, which is false for
      // 'delta', so this would actually try to read `payload` next. A
      // schema-2 delta has no `payload` key (see server.ts's own
      // broadcastRobotDelta()), so that read would silently no-op via the
      // `payload is! Map` guard right after - safe, just a dropped update,
      // never a crash or a corrupted full-tree replace.
    }
    if (type != 'settings' && type != 'delta') return;
    final payload = msg['payload'];
    if (payload is! Map<String, dynamic>) return;
    final payloadJson = jsonEncode(payload);
    if (payloadJson == _lastPayloadJson) return; // our own echoed-back write
    _lastPayloadJson = payloadJson;
    onSettings(payload);
  }

  /// Sends [payload] as a "settings" envelope over the socket. Not
  /// currently called anywhere in this app - state/robot_view_model.dart
  /// writes exclusively through the REST POST /api/robot/:id/command
  /// endpoint (see this file's own header comment), there is no "dual
  /// REST+WS write path" today despite what an earlier version of this
  /// comment claimed. Kept as a capability of this class rather than
  /// removed, since the server's own wire protocol does accept a
  /// client-sent "settings" envelope this way.
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
      if (!_closingByUser) unawaited(_openSocket());
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
