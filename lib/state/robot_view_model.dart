// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - state/robot_view_model.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Single ChangeNotifier every screen listens to via Provider - the Dart
// counterpart to HYDRA-UMC-ANDROID-CONTROL's own viewmodel/RobotViewModel.kt.
// Every write goes through sendAtomicCommand(), which POSTs the real atomic
// POST /api/robot/:id/command endpoint (server.ts:210-298) instead of
// overwriting the whole settings tree: a small, targeted payload avoids
// read-modify-write races with other connected clients and lets the
// server compute affectedIds (self + combinedWith) itself rather than
// trusting the client to get combined-robot propagation right. Every
// command that needs it (enable/disable/play/pause/stop) propagates to a
// robot's own combinedWith siblings for that same reason.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../l10n/language_prefs.dart';
import '../models/access.dart';
import '../models/assistant_reply.dart';
import '../models/hydra_state.dart';
import '../models/server_info.dart';
import '../models/stop_all_result.dart';
import '../network/auth_prefs.dart';
import '../network/biometric_helper.dart';
import '../network/hydra_api_client.dart';
import '../network/hydra_websocket.dart';
import '../network/client_prefs.dart';
import '../network/state_cache.dart';
import 'hydra_error.dart';

class SystemMetrics {
  final int cpuLoad;
  final int memoryUsage;
  final double temp;
  final int uptime;
  /// False when the host has no temperature sensor: the server then reports
  /// a made-up 45-55 degrees (temp_is_real: false) that must not be shown as
  /// a reading.
  final bool tempIsReal;
  SystemMetrics({
    required this.cpuLoad,
    required this.memoryUsage,
    required this.temp,
    required this.uptime,
    this.tempIsReal = true,
  });
}

class RobotViewModel extends ChangeNotifier {
  // injectable so login / _attemptTokenRefresh / logout get real
  // test coverage against a fake AuthPrefs backed by a fake SecureTokenBackend,
  // the same pattern HYDRA-UMC-DSI's own RobotViewModel already uses.
  RobotViewModel({AuthPrefs? authPrefs}) : _authPrefs = authPrefs ?? AuthPrefs();

  final AuthPrefs _authPrefs;
  final BiometricHelper _biometricHelper = BiometricHelper();
  final LanguagePrefs _languagePrefs = LanguagePrefs();
  final StateCache _stateCache = StateCache();
  final ClientPrefs _clientPrefs = ClientPrefs();

  /// When on, commands are not sent while [isShowingCachedState] is true (the
  /// screen shows the saved copy, not the live state). STOP is never blocked.
  bool blockCommandsOnSavedData = false;

  HydraState state = HydraState();
  HydraApiClient? apiClient;
  HydraWebSocket? _ws;
  Timer? _metricsTimer;
  Timer? _stateCacheTimer;

  // Debounced disk write of state.raw (see network/state_cache.dart's own
  // header comment for why - not on every single notifyListeners() call,
  // which fires on every WS broadcast AND every local optimistic command
  // mutation, several times a second during a held jog).
  void _scheduleCacheSave() {
    // Nothing is written for a signed-out app: the cache would outlive the
    // session it belongs to.
    if (!isLoggedIn) return;
    _stateCacheTimer?.cancel();
    _stateCacheTimer = Timer(const Duration(seconds: 1), () {
      unawaited(_stateCache.saveState(state.raw));
    });
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    // A request still on the wire can finish after the model was disposed
    // (the app closing, a test ending): nothing is listening any more.
    if (_disposed) return;
    _scheduleCacheSave();
    super.notifyListeners();
  }

  // Per-command-name debounce for _sendAtomicCommand()'s own network send -
  // a dragged Slider's onChanged fires many times a second (setSpeed's own
  // real caller, ui/control_screen.dart), and until this existed every one
  // of those ticks fired its own real POST /api/robot/:id/command, unlike
  // HYDRA-UMC-ANDROID-CONTROL's own equivalent sendAtomicCommand(), which
  // already debounces setSpeed 300ms for exactly this reason (see that
  // file's own "a dragged slider fires this many times a second" comment) -
  // this port had the same gap the Android app already closed. Keyed by
  // command name so debouncing 'speed' can never coalesce away or delay an
  // unrelated command (e.g. a jog or E-STOP) that happens to fire during
  // the same debounce window.
  final Map<String, Timer> _debounceTimers = {};

  // Per-robot generation counter guarding _sendAtomicCommand()'s own
  // rollback-on-failure below. A held jog button (joystick_pad.dart's
  // _RepeatButton) fires a new command roughly every 150ms while the API
  // call it's rolling back from can take up to the 5s network timeout - so
  // several commands for the same robot can be in flight at once. Without
  // this guard, an early command failing AFTER later ones already applied
  // (and possibly already succeeded) would restore its own stale
  // pre-mutation snapshot over top of that newer state, silently erasing
  // real progress the operator already made.
  final Map<dynamic, int> _commandGeneration = {};

  // Jog commands on the wire, per robot. A held button repeats every 150 ms;
  // on a slow link the POSTs used to pile up and still be applied after the
  // button was released. While one is in flight the next tick is dropped.
  final Map<dynamic, int> _jogsInFlight = {};

  // One session renewal at a time, however many requests and socket events
  // notice the expired token together: the refresh token is single-use, so a
  // second parallel refresh would be refused and end a session that was fine.
  Future<bool>? _renewalInFlight;
  bool _handlingWsAuthFailure = false;

  // The sign-out in progress (revoking the refresh token, erasing the stored
  // session): a login that starts meanwhile waits for it, or its fresh token
  // would be erased by the logout still running.
  Future<void>? _pendingLogout;

  ServerInfo? activeServer;
  bool isLoggedIn = false;
  HydraError? lastError;
  String connectionStatus = 'disconnected';
  dynamic selectedRobotId;
  SystemMetrics? metrics;

  // `state` shown on screen came from network/state_cache.dart's own
  // persisted last-known tree, not yet from a real, live response - see
  // that file's own header comment for the real risk this closes. Set in
  // init() when a cache is loaded, cleared the moment either real path
  // that replaces `state` with a live server response succeeds (the REST
  // fetch in connect(), or the WS onSettings callback) - so it is never
  // left true once the app has genuinely heard from the server at least
  // once, however long that takes.
  bool isShowingCachedState = false;
  DateTime? cachedStateSavedAt;

  // In-app voice/text assistant (ui/voice_assistant_dialog.dart) - separate
  // from robot state, same reasoning as HYDRA-UMC-ANDROID-CONTROL's own
  // latestVoiceAssistantReply: a reply must never be mistaken for a
  // physical command or applied optimistically.
  AssistantReply? latestAssistantReply;
  bool voiceAssistantBusy = false;

  // Explicit language override (null = follow the OS locale) - persisted
  // via LanguagePrefs, loaded in init(), read by main.dart's own
  // MaterialApp.locale and changed from ui/settings_screen.dart.
  Locale? languageOverride;

  // Rolling connection/command event log for ui/telemetry_screen.dart -
  // ported from HYDRA-UMC-ANDROID-CONTROL's own logTelemetry()/
  // telemetryLogs, same 50-entry cap and newest-first order. In-memory
  // only (unlike lastError/state, never persisted) - a diagnostic trail
  // for the current session, not something meant to survive a restart.
  final List<String> telemetryLog = [];

  // Deliberately does NOT call notifyListeners() itself - every call site
  // already triggers one shortly after for the state change the log entry
  // is describing, so this would only ever double the rebuild.
  void _logTelemetry(String message) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final timestamp = '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    telemetryLog.insert(0, '[$timestamp] $message');
    if (telemetryLog.length > 50) telemetryLog.removeRange(50, telemetryLog.length);
  }

  /// The error was shown to the user: forget it, so the same kind of error
  /// (the const ones are identical objects) is shown again if it happens again.
  /// Does not notify - nothing needs to repaint.
  void acknowledgeError() {
    lastError = null;
  }

  void clearTelemetryLog() {
    telemetryLog.clear();
    notifyListeners();
  }

  Future<void> setLanguage(String? languageCode) async {
    await _languagePrefs.saveLanguage(languageCode);
    languageOverride = await _languagePrefs.loadLocale();
    notifyListeners();
  }

  // Face ID/Touch ID/Windows Hello gate on restoring a saved session - see
  // network/biometric_helper.dart's own header comment for why this is an
  // adapted equivalent of HYDRA-UMC-ANDROID-CONTROL's own biometric login
  // rather than a literal port. biometricAvailable reflects real hardware/
  // platform capability (checked once in init()); biometricEnabled is the
  // user's own opt-in from ui/settings_screen.dart, persisted via
  // AuthPrefs. needsBiometricUnlock is true only while a restored session
  // is waiting on a successful prompt - main.dart's _RootGate shows
  // ui/biometric_gate_screen.dart for as long as it's true.
  bool biometricAvailable = false;
  bool biometricEnabled = false;
  bool needsBiometricUnlock = false;

  /// [purgeStaleKeychain] is true only for the real app start (main.dart): a
  /// fresh installation must not resume a session the previous installation
  /// left in the iOS Keychain (see AuthPrefs.purgeStaleKeychainOnFirstRun).
  Future<void> init({bool purgeStaleKeychain = false}) async {
    if (purgeStaleKeychain) await _authPrefs.purgeStaleKeychainOnFirstRun();
    languageOverride = await _languagePrefs.loadLocale();
    // Real, if possibly stale, robot data on screen immediately rather than
    // an empty Dashboard/Control while the live connect() round-trip below
    // is still in flight - genuinely useful right after the phone comes
    // back into WiFi range. Superseded by the real fetch the moment
    // connect() succeeds; see network/state_cache.dart's own header comment.
    blockCommandsOnSavedData = await _clientPrefs.loadBlockCommandsOnSavedData();
    // The controller id of this installation: made once, kept, and adopted here.
    final storedControllerId = await _clientPrefs.loadControllerId();
    if (isValidControllerId(storedControllerId)) {
      HydraApiClient.controllerId = storedControllerId!;
    } else {
      await _clientPrefs.saveControllerId(HydraApiClient.controllerId);
    }
    final cached = await _stateCache.loadCachedState();
    if (cached != null) {
      state = HydraState(cached.raw);
      isShowingCachedState = true;
      cachedStateSavedAt = cached.savedAt;
    }
    final saved = await _authPrefs.loadConnection();
    final token = await _authPrefs.loadToken();
    biometricAvailable = await _biometricHelper.isAvailable();
    biometricEnabled = await _authPrefs.loadBiometricEnabled();
    if (saved != null) {
      final (host, port) = saved;
      // The scheme this server was last seen on: one that answered TLS is not
      // probed over plain http again at start-up.
      final useTls = await _authPrefs.loadUseTls();
      final client = HydraApiClient(host, port, useTls: useTls);
      client.authToken = token;
      apiClient = client;
      activeServer = ServerInfo(host: host, port: port, useTls: useTls);
      isLoggedIn = token != null;
    }
    if (isLoggedIn && biometricEnabled) {
      if (biometricAvailable) {
        // Hold off on connect() (and on notifyListeners() showing MainScreen)
        // until unlockWithBiometrics() succeeds - _RootGate reads
        // needsBiometricUnlock before isLoggedIn, so the app shows the
        // unlock gate instead of jumping straight into a live session.
        needsBiometricUnlock = true;
        notifyListeners();
        return;
      }
      // The gate was turned on but cannot be shown now (Face ID permission
      // withdrawn, fingerprints removed, a failing sensor): the lock fails
      // closed. The saved session is dropped and a full sign-in is required
      // instead of skipping the gate.
      isLoggedIn = false;
      apiClient?.authToken = null;
      await _authPrefs.clearToken();
      notifyListeners();
      return;
    }
    notifyListeners();
    // A restored session needs the same real connect() step login() runs
    // (fetch settings, open the WS, start metrics polling) - without this
    // call the app landed straight on MainScreen with isLoggedIn=true but
    // an empty HydraState and no live connection.
    if (isLoggedIn) await connect();
  }

  /// Shows the biometric prompt and, on success, finishes restoring the
  /// session exactly the way init() would have without the gate. Returns
  /// false on cancellation/failure so ui/biometric_gate_screen.dart can
  /// show an error without touching isLoggedIn - the saved token is still
  /// there for another attempt.
  Future<bool> unlockWithBiometrics(String reason) async {
    final ok = await _biometricHelper.authenticate(reason);
    if (ok) {
      needsBiometricUnlock = false;
      notifyListeners();
      await connect();
    }
    return ok;
  }

  /// Escape hatch from the unlock gate for a user who can't or won't
  /// complete the biometric prompt (lost Face ID access, wrong finger
  /// repeatedly, ...) - signs out fully rather than leaving the app stuck
  /// showing the gate forever with no other path back to LoginScreen.
  void cancelBiometricUnlock() {
    needsBiometricUnlock = false;
    isLoggedIn = false;
    unawaited(_authPrefs.clearToken());
    notifyListeners();
  }

  Future<void> setBlockCommandsOnSavedData(bool value) async {
    blockCommandsOnSavedData = value;
    await _clientPrefs.saveBlockCommandsOnSavedData(value);
    notifyListeners();
  }

  Future<void> setBiometricEnabled(bool value) async {
    biometricEnabled = value;
    await _authPrefs.saveBiometricEnabled(value);
    notifyListeners();
  }

  Future<bool> login(ServerInfo server) async {
    _myUsername = null;
    // A sign-out still erasing the previous session must finish first.
    await _pendingLogout;
    // Close out any previous session's client before replacing it - each
    // HydraApiClient owns its own http.Client (its own connection pool),
    // and overwriting apiClient without closing the old one first leaked
    // one on every re-login.
    apiClient?.close();
    final client = HydraApiClient(server.host, server.port);
    apiClient = client;
    _logTelemetry('Logging in to ${server.host}:${server.port}...');
    try {
      final resp = await client.login(server.username, server.password);
      final token = resp['token'] as String?;
      if (resp['success'] != true || token == null) {
        lastError = const HydraError(HydraErrorKind.loginFailed);
        _logTelemetry('Login failed: server rejected credentials');
        notifyListeners();
        return false;
      }
      client.authToken = token;
      isLoggedIn = true;
      // login() resolves the scheme itself (HydraApiClient._resolveScheme), so
      // the server we are now signed in to carries the scheme it really uses.
      activeServer = server.copyWith(useTls: client.usesTls);
      await _authPrefs.saveConnection(server.host, server.port);
      await _authPrefs.saveUseTls(client.usesTls);
      // HYDRA-UMC-SERVER's POST /api/login also returns an opaque
      // refreshToken; a server predating that omits it. Either way a login
      // REPLACES the stored one, so a refresh token left behind by a previous
      // account can never be used for this session.
      final refreshToken = resp['refreshToken'] as String?;
      await _authPrefs.saveToken(token, server.username, refreshToken: refreshToken, replaceRefreshToken: true);
      lastError = null;
      _logTelemetry('Login successful');
      notifyListeners();
      await connect();
      return true;
    } catch (e) {
      lastError = HydraError(HydraErrorKind.loginError, {'error': '$e'});
      _logTelemetry('Login error: $e');
      notifyListeners();
      return false;
    }
  }

  void logout() {
    _myUsername = null;
    claims = const [];
    safetyByRobot.clear();
    jogArmedUntil.clear();
    isLoggedIn = false;
    _ws?.disconnect();
    _metricsTimer?.cancel();
    _stateCacheTimer?.cancel();
    // A pending debounced command (a speed change) would otherwise be sent
    // after sign-out, with no token, and answer with a 401.
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    _jogsInFlight.clear();
    stopAllResult = null;
    stopAllUnconfirmed = false;
    // Clear the bearer token from the live apiClient too, not just from
    // persisted storage.
    final client = apiClient;
    client?.authToken = null;
    _pendingLogout = _finishLogout(client);
    notifyListeners();
  }

  // Strictly in order: read the refresh token, revoke it on the server
  // (best-effort), then erase the stored session and the offline copy of the
  // robot state (it can hold camera credentials and belongs to this session).
  Future<void> _finishLogout(HydraApiClient? client) async {
    try {
      final refreshToken = await _authPrefs.loadRefreshToken();
      if (client != null && refreshToken != null) await client.logoutRemote(refreshToken);
    } finally {
      await _authPrefs.clearToken();
      await _stateCache.clear();
    }
  }

  // The session is over for good (the token is dead and could not be
  // renewed): tell the user and sign out completely - socket, metrics poll,
  // timers and stored tokens - not just flip the flag.
  void _forceLogout() {
    if (!isLoggedIn) return;
    lastError = const HydraError(HydraErrorKind.wsAuthRejected);
    connectionStatus = 'disconnected';
    logout();
  }

  /// try to recover a WebSocket 1008 (auth) close by exchanging the
  /// stored refresh token for a fresh access token, before concluding the
  /// session itself is dead. This app never stores a password (auth_prefs.dart's
  /// own header comment on why), so ANDROID-CONTROL's "replay the remembered
  /// password" approach doesn't apply; this mirrors HYDRA-UMC-DSI's / STUDIO's
  /// own refresh-token client (HYDRA-UMC-SERVER 0.6.2). Fails closed exactly
  /// where a real re-login is still correct: no refresh token on file, or a
  /// non-success / 401 response (the refresh token itself expired, or the
  /// account was genuinely revoked).
  Future<bool> _attemptTokenRefresh() async {
    final client = apiClient;
    final server = activeServer;
    if (client == null || server == null) return false;
    final refreshToken = await _authPrefs.loadRefreshToken();
    if (refreshToken == null) return false;
    try {
      final resp = await client.refresh(refreshToken);
      final newToken = resp['token'] as String?;
      if (resp['success'] != true || newToken == null) return false;
      client.authToken = newToken;
      final username = await _authPrefs.loadUsername() ?? server.username;
      await _authPrefs.saveToken(newToken, username, refreshToken: resp['refreshToken'] as String?);
      lastError = null;
      _logTelemetry('Session renewed with the refresh token');
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  // The single entry to renewing the session: callers that arrive while a
  // renewal is running share its result instead of starting their own.
  Future<bool> _renewSession() {
    final inFlight = _renewalInFlight;
    if (inFlight != null) return inFlight;
    final renewal = _attemptTokenRefresh().whenComplete(() => _renewalInFlight = null);
    _renewalInFlight = renewal;
    return renewal;
  }

  // Runs [call] with the session's token. An expired or invalid token (a 403
  // TOKEN_EXPIRED / TOKEN_INVALID, or a 401) renews the session once and
  // repeats the call; any other answer, or a failed renewal, reaches the
  // caller as it came.
  Future<T> _authed<T>(Future<T> Function(HydraApiClient client) call) async {
    final client = apiClient;
    if (client == null) throw HydraApiException('Not connected');
    try {
      return await call(client);
    } on HydraApiException catch (e) {
      if (!e.isSessionProblem) rethrow;
      if (!await _renewSession()) rethrow;
      return await call(apiClient ?? client);
    }
  }

  // The server closed (or announced it would close) the socket because the
  // token is dead: the error frame and the 1008 close that follows it about
  // 100 ms later are ONE event. Renew once and reopen the socket with the new
  // token; only a failed renewal signs the user out.
  Future<void> _onWsAuthFailure(ServerInfo server) async {
    if (_handlingWsAuthFailure) return;
    _handlingWsAuthFailure = true;
    try {
      if (await _renewSession()) {
        final client = apiClient;
        if (client != null && isLoggedIn) _setupWebSocket(server, client.authToken, client.usesTls);
      } else {
        _forceLogout();
      }
    } finally {
      _handlingWsAuthFailure = false;
    }
  }

  /// Called when the app returns to the foreground (see main.dart's own
  /// _RootGateState.didChangeAppLifecycleState) - iOS can suspend or drop
  /// the socket while backgrounded without hydra_websocket.dart's own
  /// onDone/onError ever firing promptly on return, so this asks for a
  /// fresh connect() explicitly instead of waiting on the WS's own 3s retry
  /// timer to notice by itself. A no-op while logged out, while the
  /// biometric gate is still up, or when already connected/connecting -
  /// connect() itself is safe to call again (it tears down and recreates
  /// the WS/metrics timer), but there's no reason to when nothing suggests
  /// the existing connection needs it.
  void reconnectIfNeeded() {
    if (!isLoggedIn || needsBiometricUnlock) return;
    if (connectionStatus == 'connected' || connectionStatus == 'connecting') return;
    unawaited(connect());
  }

  /// Called when the app is actually backgrounded (main.dart's own
  /// _RootGateState.didChangeAppLifecycleState, AppLifecycleState.paused
  /// specifically - not the merely-transient `inactive` state a system
  /// alert or the app switcher also produces). Real gap found while
  /// auditing the code: this app relied entirely on iOS's own OS-level
  /// socket timeout to eventually notice a backgrounded connection was
  /// dead, rather than actively closing it - HYDRA-UMC-ANDROID-CONTROL's
  /// own equivalent already closes proactively. Explicitly disconnecting
  /// here stops the 5s REST metrics poll and releases the socket the
  /// moment the app leaves the foreground, instead of leaving both alive
  /// against a connection the OS may suspend or kill on its own schedule.
  /// Safe to call while logged out or already disconnected - both
  /// `_ws?.disconnect()`/`_metricsTimer?.cancel()` are no-ops then.
  /// `connect()` (via `reconnectIfNeeded()` on resume) fully
  /// re-establishes both, so nothing here needs its own undo path.
  void pauseForBackground() {
    if (connectionStatus == 'disconnected') return;
    _ws?.disconnect();
    _metricsTimer?.cancel();
    connectionStatus = 'disconnected';
    _logTelemetry('App backgrounded: WebSocket and metrics poll paused');
    notifyListeners();
  }

  Future<void> connect() async {
    final server = activeServer;
    final client = apiClient;
    if (server == null || client == null) return;
    connectionStatus = 'connecting';
    _logTelemetry('Connecting to ${server.host}:${server.port}...');
    notifyListeners();

    try {
      // Through _authed(): a token that expired while the app was closed is
      // renewed with the refresh token instead of ending the session.
      final settings = await _authed((c) => c.getSettings());
      state = HydraState(settings);
      isShowingCachedState = false;
      _ensureSelectedRobot();
      if (client.usesTls) unawaited(_authPrefs.saveUseTls(true));
      _logTelemetry('Initial state synchronized via REST');
      notifyListeners();
    } catch (e) {
      lastError = HydraError(HydraErrorKind.fetchFailed, {'error': '$e'});
      connectionStatus = 'error';
      _logTelemetry('REST sync error: $e');
      if (e is HydraApiException && e.isSessionProblem) {
        // The token is dead and could not be renewed. Sign out for real and
        // stop here: opening the socket and the metrics poll for a session
        // that no longer exists only left them running behind the login screen.
        _forceLogout();
        return;
      }
      notifyListeners();
    }

    _setupWebSocket(server, client.authToken, client.usesTls);
    _startMetricsLoop(client);
  }

  void _setupWebSocket(ServerInfo server, String? token, bool useTls) {
    _ws?.disconnect();
    _ws = HydraWebSocket(
      host: server.host,
      port: server.port,
      useTls: useTls,
      token: token,
      onStatus: (status) {
        connectionStatus = switch (status) {
          WsStatus.connecting => 'connecting',
          WsStatus.connected => 'connected',
          WsStatus.disconnected => 'disconnected',
        };
        _logTelemetry(switch (status) {
          WsStatus.connecting => 'WebSocket connecting...',
          WsStatus.connected => 'WebSocket connected',
          WsStatus.disconnected => 'WebSocket disconnected',
        });
        notifyListeners();
      },
      onSettings: (payload) {
        state = HydraState(payload);
        isShowingCachedState = false;
        _ensureSelectedRobot();
        notifyListeners();
      },
      onDelta: _applyRobotDelta,
      onError: (error) {
        lastError = error;
        _logTelemetry('WebSocket error: ${error.params['message'] ?? error.params['error'] ?? error.kind.name}');
        // The server's "Access denied" frame and the 1008 close that follows
        // it (the WS layer's wsAuthRejected) mean the same thing: this token
        // is dead. A client-side connection failure (wsConnectionLost/
        // wsConnectFailed) is a connectivity problem, never an auth one.
        final isAuthFailure = error.kind == HydraErrorKind.wsAuthRejected ||
            (error.kind == HydraErrorKind.serverMessage &&
                (((error.params['message'] ?? '').contains('denied')) ||
                    ((error.params['message'] ?? '').contains('token'))));
        if (isAuthFailure) unawaited(_onWsAuthFailure(server));
        notifyListeners();
      },
    )..connect();
  }

  static int _asInt(dynamic v) => v is num ? v.toInt() : 0;

  void _startMetricsLoop(HydraApiClient client) {
    _metricsTimer?.cancel();
    _metricsTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        // Carries the bearer token: a server run with
        // HYDRA_UMC_INFO_AUTH=required answers 401 to the open read.
        final m = await client.getSystemMetrics();
        metrics = SystemMetrics(
          cpuLoad: _asInt(m['cpu_load']),
          memoryUsage: _asInt(m['memory_usage']),
          temp: m['temp'] is num ? (m['temp'] as num).toDouble() : 0.0,
          uptime: _asInt(m['uptime']),
          tempIsReal: m['temp_is_real'] != false,
        );
        notifyListeners();
      } catch (_) {
        // best-effort background poll - a miss doesn't clear the last known reading
      }
    });
  }

  /// Sends a typed/recognised transcript from the in-app voice assistant
  /// dialog through the authenticated Server boundary - same real
  /// POST /api/voice/turn route HYDRA-UMC-ANDROID-CONTROL's own
  /// postVoiceTurn()/sendVoiceTurn() use for its own in-app button. A reply
  /// only ever carries text/status; it never invokes sendAtomicCommand or
  /// changes robot state directly.
  Future<void> sendVoiceTurn(String transcript) async {
    final client = apiClient;
    if (client == null) {
      lastError = const HydraError(HydraErrorKind.notConnected);
      notifyListeners();
      return;
    }
    voiceAssistantBusy = true;
    notifyListeners();
    try {
      final reply = await client.postVoiceTurn(transcript, languageOverride?.toLanguageTag() ?? PlatformDispatcher.instance.locale.toLanguageTag());
      latestAssistantReply = reply;
      _logTelemetry('Voice assistant reply received: ${reply.level}; confirmation=${reply.requiresConfirmation}');
    } catch (e) {
      lastError = HydraError(HydraErrorKind.voiceAssistantFailed, {'error': '$e'});
      _logTelemetry('Voice assistant request failed');
    } finally {
      voiceAssistantBusy = false;
      notifyListeners();
    }
  }

  /// Clears the last assistant reply - called when the dialog closes.
  void clearAssistantReply() {
    latestAssistantReply = null;
    notifyListeners();
  }

  /// Applies one {controllerId, robotId, patch, cameraId?, cameraPatch?}
  /// delta in place onto state.raw's own nested Maps - RobotView/
  /// ControllerView already read/write through to these same objects (see
  /// models/hydra_state.dart's own header comment), so mutating here is
  /// visible everywhere else immediately, no rebuild needed.
  ///
  /// Looks the robot up by controllerId + robotId directly rather than via
  /// HydraState.robotById() (which only searches activeController) - a
  /// delta can legitimately target a robot in a non-active controller in a
  /// multi-controller swarm. Validates the robot exists locally BEFORE
  /// touching anything: if it doesn't, the delta is discarded and a full
  /// reload is forced instead of ever creating a "ghost" robot from a
  /// partial patch - the delta-sync design mitigation (b),
  /// non-optional.
  void _applyRobotDelta(Map<String, dynamic> msg) {
    final controllerId = msg['controllerId'];
    final robotId = msg['robotId'];
    final patch = msg['patch'];
    if (controllerId is! String || patch is! Map) return;
    Map<String, dynamic>? targetRobot;
    Map<String, dynamic>? targetCamera;
    for (final c in (state.raw['controllers'] as List? ?? const [])) {
      if (c is! Map || c['id'] != controllerId) continue;
      for (final r in (c['robots'] as List? ?? const [])) {
        if (r is Map && r['id'] == robotId) {
          targetRobot = r as Map<String, dynamic>;
          break;
        }
      }
      final cameraId = msg['cameraId'];
      if (cameraId != null) {
        for (final cam in (c['cameras'] as List? ?? const [])) {
          if (cam is Map && cam['id'] == cameraId) {
            targetCamera = cam as Map<String, dynamic>;
            break;
          }
        }
      }
      break;
    }
    if (targetRobot == null) {
      final client = apiClient;
      if (client != null) {
        unawaited(client.getSettings().then((settings) {
          state = HydraState(settings);
          _ensureSelectedRobot();
          notifyListeners();
        }).catchError((_) {}));
      }
      return;
    }
    targetRobot.addAll(patch.cast<String, dynamic>());
    final cameraPatch = msg['cameraPatch'];
    if (targetCamera != null && cameraPatch is Map) {
      targetCamera.addAll(cameraPatch.cast<String, dynamic>());
    }
    notifyListeners();
  }

  void _ensureSelectedRobot() {
    final robots = state.activeController?.robots ?? const [];
    if (selectedRobotId == null || robots.every((r) => r.id != selectedRobotId)) {
      selectedRobotId = robots.isNotEmpty ? robots.first.id : null;
    }
  }

  /// The camera that shows [robot]: the one whose assignedRobotId is this
  /// robot, else the robot's own id (the pairing used before cameras had an
  /// assignment). The server indexes its streams by camera id.
  dynamic cameraIdFor(RobotView robot) {
    for (final cam in state.activeController?.cameras ?? const <Map<String, dynamic>>[]) {
      if (cam['assignedRobotId'] == robot.id && cam['id'] != null) return cam['id'];
    }
    return robot.id;
  }

  /// The base address of the server as the client has learned it (http or
  /// https), the single source for every URL this app builds itself.
  String? get serverBaseUrl => apiClient?.baseUrl ?? activeServer?.baseUrl;

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
    Duration debounce = Duration.zero,
    required void Function(RobotView) localMutate,
  }) async {
    final robotId = robotIdOverride ?? selectedRobotId;
    if (robotId == null) return;
    if (blockCommandsOnSavedData && isShowingCachedState && command != 'stop') {
      lastError = const HydraError(HydraErrorKind.savedDataBlocked);
      notifyListeners();
      return;
    }
    final target = state.robotById(robotId);
    if (target == null) {
      lastError = const HydraError(HydraErrorKind.robotNotFound);
      notifyListeners();
      return;
    }

    final client = apiClient;
    if (client == null) {
      // Nothing to roll back yet (no mutation applied below) - but this was
      // previously a silent no-op with zero feedback, so a stray command
      // fired while disconnected just vanished with no sign anything was
      // wrong.
      lastError = const HydraError(HydraErrorKind.notConnected);
      notifyListeners();
      return;
    }

    // A jog the server requires to be armed and that is not, or one above the
    // limit it holds for this robot's model, is not sent at all (the server
    // checks both again). Checked before the optimistic change, like the client above.
    if (command == 'jog') {
      if (jogNeedsArming(robotId)) {
        lastError = const HydraError(HydraErrorKind.jogNotArmed);
        notifyListeners();
        return;
      }
      final amount = params?['amount'];
      final exceeded = jogLimitExceeded(
        amount is num ? amount.toDouble() : 0.0,
        safetyByRobot[robotId]?.jog,
        absolute: params?['absolute'] == true,
      );
      if (exceeded != null) {
        lastError = HydraError(HydraErrorKind.jogOverLimit, {'limit': formatLimit(exceeded)});
        notifyListeners();
        return;
      }
    }

    final affectedIds = <dynamic>[robotId];
    if (propagateToCombined) affectedIds.addAll(target.combinedWith);

    // Deep-copy snapshot of every affected robot's raw state before
    // mutating: localMutate() writes straight into raw's own nested
    // maps/lists in place, so a shallow copy could not undo anything.
    //
    // Applied unconditionally here, even when `debounce` delays the actual
    // network send below - a dragged Slider still needs instant per-tick
    // visual feedback; only the real POST round-trip is worth coalescing.
    final snapshots = <dynamic, Map<String, dynamic>>{};
    final myGeneration = <dynamic, int>{};
    for (final id in affectedIds) {
      final r = state.robotById(id);
      if (r != null) {
        snapshots[id] = jsonDecode(jsonEncode(r.raw)) as Map<String, dynamic>;
        localMutate(r);
        myGeneration[id] = _commandGeneration[id] = (_commandGeneration[id] ?? 0) + 1;
      }
    }
    notifyListeners();

    final payload = <String, dynamic>{'command': command};
    if (params != null) payload['params'] = params;

    void rollback() {
      for (final entry in snapshots.entries) {
        // Skip the rollback if a newer command for this same robot has
        // already started since this one's snapshot was taken (see
        // _commandGeneration's own header comment) - this failure is stale,
        // and restoring its snapshot now would overwrite whatever that
        // newer command already applied.
        if (_commandGeneration[entry.key] != myGeneration[entry.key]) continue;
        final r = state.robotById(entry.key);
        if (r != null) {
          r.raw
            ..clear()
            ..addAll(entry.value);
        }
      }
    }

    final isStop = command == 'stop';
    final isJog = command == 'jog';

    Future<void> send() async {
      if (isJog) _jogsInFlight[robotId] = (_jogsInFlight[robotId] ?? 0) + 1;
      try {
        final answer = await _postWithRetry(robotId, payload, urgent: isStop);
        final warnings = _commandWarnings(answer);
        if (warnings != null) {
          // The server answered 200 but applied nothing (a speed outside its
          // range, a malformed jog): the same as a failure.
          rollback();
          lastError = HydraError(HydraErrorKind.commandNotApplied, {'command': command, 'reason': warnings});
          _logTelemetry('TX not applied [$command]: $warnings');
          notifyListeners();
          return;
        }
        lastError = null;
        // The server disarms the jog on a stop.
        if (isStop) jogArmedUntil.remove(robotId);
        _logTelemetry('TX OK [$command] -> robot $robotId');
        notifyListeners();
      } catch (e) {
        // Catches everything, not just HydraApiException: a plain network
        // failure (timeout, connection refused, DNS failure) throws
        // TimeoutException/SocketException/http's own ClientException, none
        // of which is a HydraApiException. Roll back to the pre-mutation
        // snapshot and surface the failure (see ui/main_screen.dart's own
        // lastError listener) instead of leaving the UI showing a command
        // that never reached the robot.
        rollback();
        lastError = _commandError(command, e);
        // The arming ended (it times out, or a stop cleared it): the screen offers to arm again.
        if (e is HydraApiException && e.isJogNotArmed) jogArmedUntil.remove(robotId);
        _logTelemetry('TX error [$command]: $e');
        if (e is HydraApiException && e.isSessionProblem) {
          // The renewal inside _authed() already failed: the session is over.
          _forceLogout();
        }
        notifyListeners();
      } finally {
        if (isJog) {
          final left = (_jogsInFlight[robotId] ?? 1) - 1;
          if (left <= 0) {
            _jogsInFlight.remove(robotId);
          } else {
            _jogsInFlight[robotId] = left;
          }
        }
      }
    }

    // Debounced (same real mechanism as HYDRA-UMC-ANDROID-CONTROL's own
    // sendAtomicCommand): cancel any still-pending send for this exact
    // command name, then schedule a new one after `debounce` - a rapid
    // burst of calls for the same command (e.g. every Slider drag frame)
    // collapses into exactly one real POST once the drag settles.
    _debounceTimers.remove(command)?.cancel();
    if (debounce > Duration.zero) {
      _debounceTimers[command] = Timer(debounce, send);
    } else {
      await send();
    }
  }

  // A STOP is posted with short timeouts and, when nobody answers (a network
  // failure, not a refusal), sent again up to 3 times in about a second. An
  // answer from the server, of any kind, is final.
  Future<Map<String, dynamic>> _postWithRetry(dynamic robotId, Map<String, dynamic> payload, {required bool urgent}) async {
    var attempt = 0;
    while (true) {
      try {
        return await _authed(
          (c) => c.postRobotCommand(
            robotId,
            payload,
            timeout: urgent ? const Duration(seconds: 2) : const Duration(seconds: 5),
          ),
        );
      } on HydraApiException {
        rethrow; // the server answered: not a delivery problem
      } catch (_) {
        if (!urgent || attempt >= 2) rethrow;
      }
      attempt++;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  // The `warnings` of a 200 answer (the server applied nothing), joined; null when there are none.
  String? _commandWarnings(Map<String, dynamic> answer) {
    final warnings = answer['warnings'];
    if (warnings is! List || warnings.isEmpty) return null;
    return warnings.map((w) => w is Map && w['message'] is String ? w['message'] as String : '$w').join('; ');
  }

  // The user-facing error for a command that failed, by what the server said.
  HydraError _commandError(String command, Object e) {
    if (e is HydraApiException) {
      if (e.isJogNotArmed) return const HydraError(HydraErrorKind.jogNotArmed);
      if (e.isOtherController) return HydraError(HydraErrorKind.claimOtherController, {'detail': e.serverMessage ?? ''});
      if (e.isControllerIdRequired) return HydraError(HydraErrorKind.claimControllerRequired, {'detail': e.serverMessage ?? ''});
      if (e.isReservedByAnother) {
        return HydraError(HydraErrorKind.robotReserved, {'owner': e.serverMessage ?? ''});
      }
      if (e.isPermissionDenied) return const HydraError(HydraErrorKind.permissionDenied);
      if (e.isRejectedCommand) {
        return HydraError(HydraErrorKind.commandRejected, {'command': command, 'reason': e.serverMessage ?? ''});
      }
      if (e.isSessionProblem) return const HydraError(HydraErrorKind.wsAuthRejected);
    } else if (command == 'stop') {
      return const HydraError(HydraErrorKind.stopNotConfirmed);
    }
    return HydraError(HydraErrorKind.txError, {'command': command, 'error': '$e'});
  }

  void sendCommand(String command) {
    switch (command) {
      case 'play':
        _sendAtomicCommand(command, propagateToCombined: true, localMutate: (r) => r.setPlaying(true));
      case 'pause':
        // Sent as an explicit desired state, computed once from the selected
        // robot and applied identically to its combined group. Toggling each
        // member from its own local state let a pair drift in opposite
        // directions, while the server resolves one desired state.
        final paused = !(selectedRobot?.isPaused ?? false);
        _sendAtomicCommand(command, params: {'paused': paused}, propagateToCombined: true, localMutate: (r) => r.setPaused(paused));
      case 'stop':
        _sendAtomicCommand(command, propagateToCombined: true, localMutate: (r) => r.stop());
      default:
        // (There is no "enable"/"disable": the server has no such command and
        // answers 400.)
        lastError = HydraError(HydraErrorKind.unknownCommand, {'command': command});
        notifyListeners();
    }
  }

  // ---- Global STOP -------------------------------------------------------
  //
  // One tap, no confirmation, every robot: POST /api/stop-all. It does not
  // wait for any roster refresh and a reservation held by another account
  // never blocks it.

  /// The newest answer of the global STOP, shown until the user closes it.
  StopAllResult? stopAllResult;

  /// True after a STOP that never got an answer (and until a later one does):
  /// the robots may still be moving, so the app keeps saying so.
  bool stopAllUnconfirmed = false;

  /// Global STOPs on the wire right now.
  int _stopAllInFlight = 0;
  bool get stopAllInFlight => _stopAllInFlight > 0;

  void dismissStopAllResult() {
    if (stopAllResult == null) return;
    stopAllResult = null;
    notifyListeners();
  }

  /// Stops every robot at once. Never throws.
  Future<void> stopAll() async {
    _stopAllInFlight++;
    notifyListeners();
    try {
      StopAllResult? result;
      Object? failure;
      try {
        result = StopAllResult.fromJson(await _postStopAllWithRetry());
      } on HydraApiException catch (e) {
        if (e.isRateLimited || e.isNotFound) {
          // Over the global route's rate limit, or an older server without
          // it: stop the robots one by one instead.
          result = await _stopEachRobot();
        } else {
          failure = e;
        }
      } catch (e) {
        failure = e;
      }

      if (result == null) {
        stopAllUnconfirmed = true;
        lastError = const HydraError(HydraErrorKind.stopNotConfirmed);
        _logTelemetry('STOP ALL not confirmed: $failure');
        if (failure is HydraApiException && failure.isSessionProblem) {
          // The renewal inside _authed() already failed: the session is over.
          _forceLogout();
        }
        notifyListeners();
        return;
      }

      stopAllUnconfirmed = false;
      jogArmedUntil.clear(); // the server disarms every jog on a global stop
      stopAllResult = result;
      for (final entry in result.robots) {
        if (!entry.stopped) continue;
        for (final c in state.controllers) {
          if (entry.controllerId != null && c.id != entry.controllerId) continue;
          c.robotById(entry.robotId)?.stop();
        }
      }
      _logTelemetry('STOP ALL: ${result.stoppedCount} stopped, ${result.failedCount} failed'
          '${result.persisted ? '' : ', not saved'}${result.viaFallback ? ' (robot by robot)' : ''}');
      notifyListeners();
      _refreshAfterStopAll();
    } finally {
      _stopAllInFlight--;
      notifyListeners();
    }
  }

  // A network failure (not an answer of the server) is tried once more after a
  // short pause; an answer of any kind is final.
  Future<Map<String, dynamic>> _postStopAllWithRetry() async {
    try {
      return await _authed((c) => c.postStopAll());
    } on HydraApiException {
      rethrow;
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      return await _authed((c) => c.postStopAll());
    }
  }

  // The per-robot "stop" for every robot of every controller, all at once.
  Future<StopAllResult> _stopEachRobot() async {
    final targets = <(String, RobotView)>[
      for (final c in state.controllers)
        for (final r in c.robots) (c.id, r),
    ];
    final entries = await Future.wait(targets.map((t) async {
      final (controllerId, robot) = t;
      try {
        await _authed((c) => c.postRobotCommand(robot.id, {'command': 'stop'}, timeout: const Duration(seconds: 2)));
        return StopAllRobot(robotId: robot.id, controllerId: controllerId, name: robot.name, stopped: true);
      } catch (e) {
        return StopAllRobot(robotId: robot.id, controllerId: controllerId, name: robot.name, stopped: false, error: '$e');
      }
    }));
    return StopAllResult.fromRobots(entries, viaFallback: true);
  }

  // Reads the state again after a STOP (the WebSocket deltas usually got there
  // first); a failure is ignored, the socket keeps the picture up to date.
  void _refreshAfterStopAll() {
    if (apiClient == null) return;
    unawaited(
      _authed((c) => c.getSettings())
          .then((settings) {
            state = HydraState(settings);
            _ensureSelectedRobot();
            notifyListeners();
          })
          .catchError((_) {}),
    );
  }

  // ---- Reservations, safety limits and jog arming (contract v2, block 1) ----
  //
  // Reservations are optional: a robot nobody reserved is commanded as before.
  // The controller id (HydraApiClient.controllerId) is sent with every reserve,
  // release, jog-arm and command, so a reservation belongs to the account AND
  // to this installation.

  /// Every active reservation, as of the last refresh (GET /api/claims).
  List<ClaimInfo> claims = const [];

  /// The limits of each robot's model the server told this app about, by robot id.
  final Map<dynamic, RobotSafety> safetyByRobot = {};

  /// Until when (this device's clock) the jog of each robot is armed from this app.
  final Map<dynamic, DateTime> jogArmedUntil = {};

  /// True while a reservation or arming request is on the wire.
  bool accessBusy = false;

  String get controllerId => HydraApiClient.controllerId;

  /// The reservation of [robotId], if any.
  ClaimInfo? claimOf(dynamic robotId) {
    for (final c in claims) {
      if (c.robotId == robotId) return c;
    }
    return null;
  }

  /// Where [robotId] stands for this installation, from the last list of reservations.
  ClaimStanding claimStandingOf(dynamic robotId) =>
      claimStanding(claimOf(robotId), _myUsername ?? activeServer?.username ?? '', controllerId);

  // The account name of this session: a restored session has no password and
  // so no username on the server entry; the saved one is read once.
  String? _myUsername;

  /// True when the server requires the jog of [robotId] to be armed and it is
  /// not (this app's view of it).
  bool jogNeedsArming(dynamic robotId, [DateTime? now]) {
    final safety = safetyByRobot[robotId];
    if (safety == null || !safety.armRequired) return false;
    final until = jogArmedUntil[robotId];
    return until == null || !until.isAfter(now ?? DateTime.now());
  }

  /// Reads the reservations and the limits of the selected robot's model from
  /// the server. Called when the control screen opens, when the robot changes
  /// and now and then while it is open; it never raises an error on the screen
  /// (the server may simply be an older one).
  Future<void> refreshAccess() async {
    if (apiClient == null) return;
    final robotId = selectedRobotId;
    if (_myUsername == null) {
      final named = activeServer?.username ?? '';
      _myUsername = named.isNotEmpty ? named : await _authPrefs.loadUsername();
    }
    try {
      claims = await _authed((c) => c.getClaims());
    } catch (e) {
      if (e is HydraApiException && e.isSessionProblem) _forceLogout();
    }
    if (robotId != null) {
      try {
        final safety = await _authed((c) => c.getRobotSafety(robotId));
        if (safety != null) {
          safetyByRobot[robotId] = safety;
          final until = safety.jogArmedUntil;
          final now = DateTime.now();
          // The server clock and this device clock may differ: the arming is
          // shown as ending no later than its length allows.
          if (until != null && until > now.millisecondsSinceEpoch) {
            final byServer = DateTime.fromMillisecondsSinceEpoch(until);
            final byLength = now.add(Duration(milliseconds: safety.armTtlMs));
            jogArmedUntil[robotId] = byServer.isBefore(byLength) ? byServer : byLength;
          } else {
            jogArmedUntil.remove(robotId);
          }
        }
      } catch (e) {
        if (e is HydraApiException && e.isSessionProblem) _forceLogout();
      }
    }
    notifyListeners();
  }

  /// Reserves the selected robot for this account on this installation.
  Future<void> claimSelectedRobot() => _runAccessRequest('claim', (c, id) => c.postClaim(id));

  /// Whether this session is an administrator's (the role in its token; the server checks it again).
  bool get isAdmin => jwtRole(apiClient?.authToken) == 'admin';

  /// Whether the take-over button applies to [robotId]: an administrator, and someone else holds it.
  bool canTakeOver(dynamic robotId) => canTakeOverRobot(jwtRole(apiClient?.authToken), claimStandingOf(robotId));

  /// Takes the selected robot over from whoever holds it (`force: true`; the server accepts it from administrators
  /// only). The screen asks the operator to confirm first; nothing is sent when it does not apply.
  Future<void> takeOverSelectedRobot() {
    if (!canTakeOver(selectedRobotId)) return Future.value();
    return _runAccessRequest('claim', (c, id) => c.postClaim(id, force: true));
  }

  /// Releases the selected robot's reservation. Also ends the arming of its jog, as the server does.
  Future<void> releaseSelectedRobot() => _runAccessRequest('release', (c, id) async {
        final answer = await c.postRelease(id);
        jogArmedUntil.remove(id);
        return answer;
      });

  /// Arms or disarms the jog of the selected robot (only needed when the server requires it).
  Future<void> setJogArmed(bool armed) => _runAccessRequest('jog-arm', (c, id) async {
        final answer = await c.postJogArm(id, armed);
        if (armed) {
          final ttl = answer['ttlMs'] is num ? (answer['ttlMs'] as num).toInt() : (safetyByRobot[id]?.armTtlMs ?? 60000);
          jogArmedUntil[id] = DateTime.now().add(Duration(milliseconds: ttl));
        } else {
          jogArmedUntil.remove(id);
        }
        return answer;
      });

  Future<void> _runAccessRequest(String what, Future<Map<String, dynamic>> Function(HydraApiClient, dynamic) call) async {
    final robotId = selectedRobotId;
    if (robotId == null) return;
    if (apiClient == null) {
      lastError = const HydraError(HydraErrorKind.notConnected);
      notifyListeners();
      return;
    }
    accessBusy = true;
    notifyListeners();
    try {
      await _authed((c) => call(c, robotId));
      lastError = null;
      _logTelemetry('TX OK [$what] -> robot $robotId');
    } catch (e) {
      lastError = _commandError(what, e);
      _logTelemetry('TX error [$what]: $e');
      if (e is HydraApiException && e.isSessionProblem) _forceLogout();
    } finally {
      accessBusy = false;
    }
    notifyListeners();
    await refreshAccess();
  }

  /// True while a jog should not be sent: the previous tick is still on the
  /// wire, or the robot is running a trajectory (the server's playback and a
  /// jog would both write the same setpoint).
  bool jogBlocked([dynamic robotId]) {
    final id = robotId ?? selectedRobotId;
    if (id == null) return true;
    if ((_jogsInFlight[id] ?? 0) > 0) return true;
    final robot = state.robotById(id);
    if (robot == null) return true;
    return robot.isPlaying && !robot.isPaused;
  }

  /// One tick of a held jog button: up to three axes in one go, dropped as a
  /// whole while the previous tick is still on the wire.
  void jogXYZ(String target, int dx, int dy, int dz, double step) {
    if (jogBlocked()) return;
    if (dx != 0) jog(target, 'x', dx * step);
    if (dy != 0) jog(target, 'y', dy * step);
    if (dz != 0) jog('robot', 'z', dz * step);
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

  /// Debounced (300ms, matching HYDRA-UMC-ANDROID-CONTROL's own setSpeed) -
  /// a dragged Slider's onChanged (ui/control_screen.dart) fires this many
  /// times a second.
  void setSpeed(double speed, double acceleration) {
    _sendAtomicCommand(
      'speed',
      params: {'speed': speed, 'acceleration': acceleration},
      debounce: const Duration(milliseconds: 300),
      localMutate: (r) {
        r.setSpeed(speed);
        r.setAcceleration(acceleration);
      },
    );
  }

  /// Toggles a robot's vision system on/off from the Camera screen
  /// (server.ts's own "vision" command). Takes an explicit robotId since
  /// the camera being browsed isn't necessarily the globally selected
  /// control robot - same design as HYDRA-UMC-ANDROID-CONTROL's own
  /// setVisionEnabled(robotId, enabled).
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
    _disposed = true;
    _ws?.disconnect();
    _metricsTimer?.cancel();
    _stateCacheTimer?.cancel();
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    apiClient?.close();
    super.dispose();
  }
}
