// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - state/robot_view_model.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
//
// Single ChangeNotifier every screen listens to via Provider - the Dart
// counterpart to HYDRA-UMC-ANDROID-CONTROL's own viewmodel/RobotViewModel.kt.
// Every write goes through sendAtomicCommand(), which POSTs the real atomic
// POST /api/robot/:id/command endpoint (server.ts:210-298) instead of
// always overwriting the whole settings tree - built this way from day
// one, unlike the Android app, which had to be migrated to it the same
// day (2026-08-19) after shipping the slower/heavier full-tree approach
// first. Combined-robot propagation (a robot's own combinedWith siblings)
// is correct from day one too for the same reason - see that project's
// own SONNET/ tracking for the Enable/Disable bug this avoids by
// construction.
// =============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/hydra_state.dart';
import '../models/server_info.dart';
import '../network/auth_prefs.dart';
import '../network/hydra_api_client.dart';
import '../network/hydra_websocket.dart';

class SystemMetrics {
  final int cpuLoad;
  final int memoryUsage;
  final double temp;
  final int uptime;
  SystemMetrics({required this.cpuLoad, required this.memoryUsage, required this.temp, required this.uptime});
}

class RobotViewModel extends ChangeNotifier {
  final AuthPrefs _authPrefs = AuthPrefs();

  HydraState state = HydraState();
  HydraApiClient? apiClient;
  HydraWebSocket? _ws;
  Timer? _metricsTimer;

  ServerInfo? activeServer;
  bool isLoggedIn = false;
  String lastError = '';
  String connectionStatus = 'disconnected';
  dynamic selectedRobotId;
  SystemMetrics? metrics;

  Future<void> init() async {
    final saved = await _authPrefs.loadConnection();
    final token = await _authPrefs.loadToken();
    if (saved != null) {
      final (host, port) = saved;
      final client = HydraApiClient(host, port);
      client.authToken = token;
      apiClient = client;
      activeServer = ServerInfo(host: host, port: port);
      isLoggedIn = token != null;
    }
    notifyListeners();
  }

  Future<bool> login(ServerInfo server) async {
    final client = HydraApiClient(server.host, server.port);
    apiClient = client;
    try {
      final resp = await client.login(server.username, server.password);
      final token = resp['token'] as String?;
      if (resp['success'] != true || token == null) {
        lastError = 'Login failed: server rejected credentials';
        notifyListeners();
        return false;
      }
      client.authToken = token;
      isLoggedIn = true;
      activeServer = server;
      await _authPrefs.saveConnection(server.host, server.port);
      await _authPrefs.saveToken(token, server.username);
      lastError = '';
      notifyListeners();
      await connect();
      return true;
    } catch (e) {
      lastError = 'Login error: $e';
      notifyListeners();
      return false;
    }
  }

  void logout() {
    isLoggedIn = false;
    _ws?.disconnect();
    _metricsTimer?.cancel();
    unawaited(_authPrefs.clearToken());
    notifyListeners();
  }

  Future<void> connect() async {
    final server = activeServer;
    final client = apiClient;
    if (server == null || client == null) return;
    connectionStatus = 'connecting';
    notifyListeners();

    try {
      final settings = await client.getSettings();
      state = HydraState(settings);
      _ensureSelectedRobot();
      notifyListeners();
    } catch (e) {
      lastError = 'Initial fetch failed: $e';
      connectionStatus = 'error';
      notifyListeners();
    }

    _setupWebSocket(server, client.authToken);
    _startMetricsLoop(client);
  }

  void _setupWebSocket(ServerInfo server, String? token) {
    _ws?.disconnect();
    _ws = HydraWebSocket(
      host: server.host,
      port: server.port,
      token: token,
      onStatus: (status) {
        connectionStatus = switch (status) {
          WsStatus.connecting => 'connecting',
          WsStatus.connected => 'connected',
          WsStatus.disconnected => 'disconnected',
        };
        notifyListeners();
      },
      onSettings: (payload) {
        state = HydraState(payload);
        _ensureSelectedRobot();
        notifyListeners();
      },
      onError: (message) {
        lastError = message;
        if (message.contains('denied') || message.contains('token')) {
          isLoggedIn = false;
          connectionStatus = 'disconnected';
          _ws?.disconnect();
        }
        notifyListeners();
      },
    )..connect();
  }

  void _startMetricsLoop(HydraApiClient client) {
    _metricsTimer?.cancel();
    _metricsTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final m = await client.getSystemMetrics();
        metrics = SystemMetrics(
          cpuLoad: (m['cpu_load'] ?? 0) as int,
          memoryUsage: (m['memory_usage'] ?? 0) as int,
          temp: ((m['temp'] ?? 0) as num).toDouble(),
          uptime: (m['uptime'] ?? 0) as int,
        );
        notifyListeners();
      } catch (_) {
        // best-effort background poll - a miss doesn't clear the last known reading
      }
    });
  }

  void _ensureSelectedRobot() {
    final robots = state.activeController?.robots ?? const [];
    if (selectedRobotId == null || robots.every((r) => r.id != selectedRobotId)) {
      selectedRobotId = robots.isNotEmpty ? robots.first.id : null;
    }
  }

  RobotView? get selectedRobot => selectedRobotId == null ? null : state.robotById(selectedRobotId);
  List<RobotView> get robots => state.activeController?.robots ?? const [];

  void selectRobot(dynamic robotId) {
    selectedRobotId = robotId;
    notifyListeners();
  }

  /// Applies [command]/[params] to [robotId] (defaults to the selected
  /// robot) and, when [propagateToCombined] is true, its own combinedWith
  /// siblings too - locally for instant UI feedback via [localMutate], then
  /// via the real atomic endpoint. See this file's own header comment.
  Future<void> _sendAtomicCommand(
    String command, {
    Map<String, dynamic>? params,
    bool propagateToCombined = false,
    dynamic robotIdOverride,
    required void Function(RobotView) localMutate,
  }) async {
    final robotId = robotIdOverride ?? selectedRobotId;
    if (robotId == null) return;
    final target = state.robotById(robotId);
    if (target == null) {
      lastError = 'Robot not found';
      notifyListeners();
      return;
    }

    final affectedIds = <dynamic>[robotId];
    if (propagateToCombined) affectedIds.addAll(target.combinedWith);
    for (final id in affectedIds) {
      final r = state.robotById(id);
      if (r != null) localMutate(r);
    }
    notifyListeners();

    final client = apiClient;
    if (client == null) return;
    final payload = <String, dynamic>{'command': command};
    if (params != null) payload['params'] = params;

    try {
      await client.postRobotCommand(robotId, payload);
      lastError = '';
    } on HydraApiException catch (e) {
      lastError = 'TX error [$command]: $e';
      if (e.toString().contains('401') || e.toString().contains('403')) {
        isLoggedIn = false;
        connectionStatus = 'disconnected';
        _ws?.disconnect();
      }
      notifyListeners();
    }
  }

  void sendCommand(String command) {
    switch (command) {
      case 'enable':
        _sendAtomicCommand(command, propagateToCombined: true, localMutate: (r) => r.setOnline(true));
      case 'disable':
        _sendAtomicCommand(command, propagateToCombined: true, localMutate: (r) => r.setOnline(false));
      case 'play':
        _sendAtomicCommand(command, propagateToCombined: true, localMutate: (r) => r.setPlaying(true));
      case 'pause':
        _sendAtomicCommand(command, propagateToCombined: true, localMutate: (r) => r.togglePaused());
      case 'stop':
        _sendAtomicCommand(command, propagateToCombined: true, localMutate: (r) => r.stop());
      default:
        lastError = 'Unknown command: $command';
        notifyListeners();
    }
  }

  void jog(String target, String axis, double amount) {
    final params = {'axis': axis, 'amount': amount, 'target': target};
    _sendAtomicCommand(
      'jog',
      params: params,
      localMutate: (r) {
        if (target == 'robot') {
          r.setPosAxis(axis, r.posAxis(axis) + amount);
        } else if (target == 'xytable') {
          r.setXyTableAxis(axis, (r.xyTablePos[axis] ?? 0.0) + amount);
        }
      },
    );
  }

  void toggleValve(int index) {
    final r = selectedRobot;
    if (r == null) return;
    final newState = !((r.valves[index] ?? false) as bool);
    _sendAtomicCommand('valve', params: {'index': index, 'state': newState}, localMutate: (r) => r.setValve(index, newState));
  }

  void togglePump(int index) {
    final r = selectedRobot;
    if (r == null) return;
    final newState = !((r.pumps[index] ?? false) as bool);
    _sendAtomicCommand('pump', params: {'index': index, 'state': newState}, localMutate: (r) => r.setPump(index, newState));
  }

  void setSpeed(double speed, double acceleration) {
    _sendAtomicCommand(
      'speed',
      params: {'speed': speed, 'acceleration': acceleration},
      localMutate: (r) {
        r.setSpeed(speed);
        r.setAcceleration(acceleration);
      },
    );
  }

  /// Toggles a robot's vision system on/off from the Camera screen
  /// (server.ts's own "vision" command, added 2026-08-19). Takes an
  /// explicit robotId since the camera being browsed isn't necessarily the
  /// globally selected control robot - same design as
  /// HYDRA-UMC-ANDROID-CONTROL's own setVisionEnabled(robotId, enabled).
  void setVisionEnabled(dynamic robotId, bool enabled) {
    _sendAtomicCommand(
      'vision',
      params: {'enabled': enabled},
      robotIdOverride: robotId,
      localMutate: (r) => r.raw['visionEnabled'] = enabled,
    );
  }

  @override
  void dispose() {
    _ws?.disconnect();
    _metricsTimer?.cancel();
    apiClient?.close();
    super.dispose();
  }
}
