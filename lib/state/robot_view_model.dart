// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - state/robot_view_model.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The single ChangeNotifier every screen listens to through Provider (the counterpart of the view model of the Android app).
// Contract: every write is one POST /api/robot/:id/command with a small payload; the server computes the affected robots
// (itself and its combinedWith) and broadcasts the change, so the app never rewrites the settings tree. Enable, disable,
// play, pause and stop are propagated to the combined robots.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../kinematics/parol6_kinematics.dart';
import '../app_version.dart';
import '../l10n/language_prefs.dart';
import '../models/access.dart';
import '../models/assistant_reply.dart';
import '../models/connection_history.dart';
import '../models/ecosystem.dart';
import '../models/contract_v2.dart';
import '../models/hydra_state.dart';
import '../models/ios_feature_contract.dart';
import '../models/robot_command_contract.dart';
import '../models/server_info.dart';
import '../models/server_security.dart';
import '../models/stop_all_result.dart';
import '../network/listen_only_gate.dart';
import '../network/auth_prefs.dart';
import '../network/ble_contract.dart';
import '../network/ble_gatt.dart';
import '../network/ble_gatt_fbp.dart';
import '../network/hydra_ble_client.dart';
import '../network/push_bridge.dart';
import '../network/shortcut_bridge.dart';
import '../network/biometric_helper.dart';
import '../network/hydra_api_client.dart';
import '../network/hydra_websocket.dart';
import '../network/native_bridges.dart';
import '../network/client_prefs.dart';
import '../network/state_cache.dart';
import '../network/tls_settings.dart';
import '../util/connection_diagnostics.dart';
import '../util/dead_man_jog.dart';
import '../util/pairing_link.dart';
import '../util/watch_alerts.dart';
import '../util/watch_relay.dart';
import '../util/work_files.dart';
import '../l10n/app_localizations.dart';
import 'dead_man_jog_controller.dart';
import '../util/home_reset.dart';
import '../util/job_alerts.dart';
import '../util/link_health.dart';
import 'external_surfaces.dart';
import 'hydra_error.dart';
import 'robot_command_repository.dart';
import 'session_manager.dart';

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

/// What became of the registration of this phone for push notifications.
enum PushState { off, registering, registered, denied, serverOff, failed }

/// What became of handing the token of the Live Activity to the server (see [RobotViewModel.liveActivityPushState]).
enum LiveActivityPushState { off, registered, serverOff, failed }

/// Why the audit record could not be read, for the sentence the screen shows.
enum AuditFailure { forbidden, unavailable, session, network, other }

class RobotViewModel extends ChangeNotifier {
  // The stores and clients are injectable, so sign-in, token renewal and sign-out run in tests against a fake AuthPrefs.
  RobotViewModel({
    AuthPrefs? authPrefs,
    BleScanner? bleScanner,
    BleGattConnector? bleConnector,
    PushBridge? pushBridge,
    ShortcutBridge? shortcutBridge,
    AlertsBridge? alertsBridge,
    LiveActivityBridge? liveActivityBridge,
    WatchBridge? watchBridge,
    SpeechBridge? speechBridge,
    PairingBridge? pairingBridge,
  })  : _authPrefs = authPrefs ?? AuthPrefs(),
        _pairing = pairingBridge ?? MethodChannelPairingBridge(),
        surfaces = ExternalSurfaces(alerts: alertsBridge, liveActivity: liveActivityBridge, watch: watchBridge),
        _speech = speechBridge ?? MethodChannelSpeechBridge(),
        _push = pushBridge ?? MethodChannelPushBridge(),
        _shortcuts = shortcutBridge ?? MethodChannelShortcutBridge(),
        _bleScanner = bleScanner ?? FbpBleScanner(),
        _bleConnector = bleConnector ?? const FbpBleGattConnector();

  final PushBridge _push;
  final SpeechBridge _speech;
  final PairingBridge _pairing;

  /// The notifications of a job, the Live Activity and the Apple Watch (see state/external_surfaces.dart).
  final ExternalSurfaces surfaces;
  final ShortcutBridge _shortcuts;
  final BleScanner _bleScanner;
  final BleGattConnector _bleConnector;

  final AuthPrefs _authPrefs;
  final BiometricHelper _biometricHelper = BiometricHelper();
  final LanguagePrefs _languagePrefs = LanguagePrefs();
  final StateCache _stateCache = StateCache();
  final ClientPrefs _clientPrefs = ClientPrefs();
  final TlsPrefs _tlsPrefs = TlsPrefs();

  /// How the app reaches the server and what it trusts (see network/tls_settings.dart).
  TlsSettings tlsSettings = const TlsSettings();

  /// When on, commands are not sent while [isShowingCachedState] is true (the
  /// screen shows the saved copy, not the live state). STOP is never blocked.
  bool blockCommandsOnSavedData = false;

  /// When on (it is, until the person turns it off), PLAY shows what it is about to start and asks first.
  bool confirmPlay = true;

  /// Listen-only mode: the app shows the robots and their data but sends no command. Off by default. STOP (the global one and
  /// the per-robot one) and the safe-mode `disable` keep working, because refusing a stop would be the unsafe side; every other
  /// command is dropped here, whatever screen asked for it.
  bool listenOnly = false;

  /// The general switch and the servers that have their own: [listenOnly] is what holds for the server in use (either of them).
  bool _listenOnlyGeneral = false;
  Set<String> listenOnlyServers = <String>{};

  String? get _activeServerKey {
    final server = activeServer;
    return server == null ? null : ListenOnlyGate.serverKey(server.host, server.port);
  }

  /// Whether the server in use is read-only by its own switch.
  bool get listenOnlyThisServer {
    final key = _activeServerKey;
    return key != null && listenOnlyServers.contains(key);
  }

  void _refreshListenOnly({bool interrupt = true}) {
    final on = ListenOnlyGate.effective(_listenOnlyGeneral, listenOnlyServers, _activeServerKey);
    listenOnly = on;
    ListenOnlyGate.enabled = on;
    if (on && interrupt) deadMan.interrupt();
  }

  /// Switches listen-only mode, and keeps the choice. A jog that is held stops when it is switched on.
  Future<void> setListenOnly(bool value) async {
    _listenOnlyGeneral = value;
    _refreshListenOnly();
    notifyListeners();
    await _clientPrefs.saveListenOnly(value);
  }

  /// Switches listen-only mode for the server in use alone, and keeps the choice (nothing happens while no server is in use).
  Future<void> setListenOnlyThisServer(bool value) async {
    final key = _activeServerKey;
    if (key == null) return;
    listenOnlyServers = value ? {...listenOnlyServers, key} : ({...listenOnlyServers}..remove(key));
    _refreshListenOnly();
    notifyListeners();
    await _clientPrefs.saveListenOnlyServers(listenOnlyServers);
  }

  /// HOME/RESET switch (see util/home_reset.dart); off until the person turns it on, the default comes from the contract.
  bool homeResetEnabled = RobotCommandContract.homeResetEnabledByDefault;

  /// False once the server answered that it does not know `reset`; the button then explains instead of sending.
  bool homeResetServerSupports = true;

  /// The confirmation in steps of the reset; shared so the second step must follow the first.
  final HomeResetConfirmation homeResetConfirmation = HomeResetConfirmation(
    steps: RobotCommandContract.homeResetConfirmSteps,
    window: const Duration(milliseconds: RobotCommandContract.homeResetConfirmWindowMs),
  );

  HydraState state = HydraState();
  HydraApiClient? apiClient;
  HydraWebSocket? _ws;
  Timer? _metricsTimer;
  Timer? _stateCacheTimer;

  // Debounced write of state.raw to the cache (network/state_cache.dart): never on every notifyListeners(), which fires on every
  // broadcast and every optimistic change, several times a second during a held jog.
  void _scheduleCacheSave() {
    // Nothing is cached while signed out: the cache belongs to the session.
    if (!isLoggedIn) return;
    _stateCacheTimer?.cancel();
    _stateCacheTimer = Timer(const Duration(seconds: 1), () {
      unawaited(_stateCache.saveState(state.raw, scope: _cacheScope()));
    });
  }

  /// The account the offline copy belongs to (see network/state_cache.dart).
  String _cacheUser = '';

  String? _cacheScope() {
    final server = activeServer;
    if (server == null) return null;
    return StateCache.scopeOf(server.host, server.port, _cacheUser.isNotEmpty ? _cacheUser : server.username);
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    // A request still on the wire can finish after the model was disposed
    // (the app closing, a test ending): nothing is listening any more.
    if (_disposed) return;
    _scheduleCacheSave();
    super.notifyListeners();
    _publishSurfaces();
  }

  // The send of a command can be debounced (a dragged slider fires many times a second). The timers live in [commands], keyed by command name, so
  // debouncing 'speed' never delays or merges an unrelated command such as a jog or the STOP.

  // Per-robot generation counter for the rollback of _sendAtomicCommand(): several commands of one robot can be in flight at once (a held jog button
  // fires about every 150 ms, a request may take 5 s), and a command that fails after newer ones applied must not restore its older snapshot over them.
  final Map<dynamic, int> _commandGeneration = {};

  // Jog commands on the wire are counted per robot in [commands]: a held button repeats every 150 ms, and while one is in flight the
  // next tick is dropped, so a slow link never applies jogs after the button was released.

  // One session renewal at a time, however many requests and socket events notice the expired token together: the refresh token
  // is single-use, so a second parallel renewal would be refused and end a valid session.
  late final SessionManager _session = SessionManager(client: () => apiClient, renew: _attemptTokenRefresh);
  bool _handlingWsAuthFailure = false;

  // The sign-out in progress (revoking the refresh token, erasing the stored session): a sign-in that starts meanwhile waits for it.
  Future<void>? _pendingLogout;

  ServerInfo? activeServer;
  bool isLoggedIn = false;
  HydraError? lastError;
  String connectionStatus = 'disconnected';
  dynamic selectedRobotId;
  /// The last reading of the server's load, listened to by the one widget that shows it: a reading every few seconds
  /// must not rebuild every screen that watches the view model.
  final ValueNotifier<SystemMetrics?> metricsListenable = ValueNotifier<SystemMetrics?>(null);

  SystemMetrics? get metrics => metricsListenable.value;

  // True while the `state` on screen is the saved last-known tree (network/state_cache.dart) and not a live answer: set in init() when a cache is loaded,
  // cleared by the first live answer (the REST fetch in connect() or the WS settings message).
  bool isShowingCachedState = false;
  DateTime? cachedStateSavedAt;

  // The reply of the in-app assistant (ui/voice_assistant_dialog.dart). Kept apart from the robot state: a reply is never a
  // physical command and is never applied optimistically.
  AssistantReply? latestAssistantReply;
  bool voiceAssistantBusy = false;

  // Language chosen in Settings (null follows the language of the system); kept by LanguagePrefs and read by MaterialApp.locale.
  Locale? languageOverride;

  // Connection and command events for ui/telemetry_screen.dart: newest first, at most 50, in memory only (never persisted).
  final List<String> telemetryLog = [];

  // Does not notify: every caller notifies for the change the entry describes.
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

  // Face ID / Touch ID / Windows Hello gate on restoring a saved session (network/biometric_helper.dart). biometricAvailable is what the device can do
  // (checked once in init()); biometricEnabled is the person's opt-in (Settings, kept by AuthPrefs); needsBiometricUnlock is true while a restored
  // session waits for the prompt, and main.dart shows the biometric gate for as long as it is.
  bool biometricAvailable = false;
  bool biometricEnabled = false;
  // The strong mode (Settings, off by default): the saved session sits in a Keychain item the system opens only with Face ID or Touch ID.
  bool biometricStrong = false;
  bool needsBiometricUnlock = false;

  /// [purgeStaleKeychain] is true only for the real app start (main.dart): a
  /// fresh installation must not resume a session the previous installation
  /// left in the iOS Keychain (see AuthPrefs.purgeStaleKeychainOnFirstRun).
  Future<void> init({bool purgeStaleKeychain = false}) async {
    if (purgeStaleKeychain) await _authPrefs.purgeStaleKeychainOnFirstRun();
    languageOverride = await _languagePrefs.loadLocale();
    _listenToShortcuts();
    // The saved last-known state is shown at once; the live fetch of connect() replaces it (network/state_cache.dart).
    tlsSettings = await _tlsPrefs.load();
    TlsSettingsStore.current = tlsSettings;
    blockCommandsOnSavedData = await _clientPrefs.loadBlockCommandsOnSavedData();
    confirmPlay = await _clientPrefs.loadConfirmPlay();
    _listenOnlyGeneral = await _clientPrefs.loadListenOnly();
    listenOnlyServers = await _clientPrefs.loadListenOnlyServers();
    _refreshListenOnly(interrupt: false);
    homeResetEnabled = await _clientPrefs.loadHomeReset(RobotCommandContract.homeResetEnabledByDefault);
    deadMan.enabled = await _clientPrefs.loadFlag(ClientFlags.deadManJog, RobotCommandContract.deadManEnabledByDefault);
    deadMan.blockOnBadLink = await _clientPrefs.loadFlag(ClientFlags.linkBlockJog, RobotCommandContract.linkBlockJogOnBadLinkDefault);
    deadMan.indicator = await _clientPrefs.loadFlag(ClientFlags.linkIndicator, RobotCommandContract.linkIndicatorEnabledByDefault);
    pairingEnabled = await _clientPrefs.loadFlag(ClientFlags.pairing, RobotCommandContract.pairingEnabledByDefault);
    watchAlertsEnabled = await _clientPrefs.loadFlag(ClientFlags.watchAlerts, RobotCommandContract.watchAlertsEnabledByDefault);
    presenceRelayEnabled = await _clientPrefs.loadFlag(ClientFlags.presenceRelay, RobotCommandContract.presenceRelayEnabledByDefault);
    voiceConfirmRelayEnabled = await _clientPrefs.loadFlag(ClientFlags.voiceConfirmRelay, RobotCommandContract.voiceConfirmEnabledByDefault);
    // A pairing link that opened the app, or that arrives while it is open: the switches above are read already.
    _pairing.listen((link) => unawaited(receivePairing(link)));
    final pendingLink = await _pairing.takePending();
    if (pendingLink != null) await receivePairing(pendingLink);
    surfaces.restoreJobAlerts(await _clientPrefs.loadJobAlerts(JobAlertsContract.enabledByDefault));
    surfaces.restoreLiveActivity(await _clientPrefs.loadLiveActivity(LiveActivityContract.enabledByDefault));
    surfaces.restoreLiveActivityPush(await _clientPrefs.loadLiveActivityPush(LiveActivityContract.serverPushEnabledByDefault));
    surfaces.restoreWatch(await _clientPrefs.loadWatch(WatchCompanionContract.enabledByDefault));
    surfaces.registerActivityToken = _registerActivityToken;
    surfaces.forgetActivityToken = _forgetActivityToken;
    surfaces.listenForWatchStop(() => unawaited(stopAll()));
    surfaces.listenForWatchRelays(onPresence: relayPresence, onVoiceConfirm: relayVoiceConfirm);
    dictationEnabled = await _clientPrefs.loadDictation(VoiceContract.enabledByDefault);
    dictationOnline = await _clientPrefs.loadDictationOnline();
    pushNotifications = await _clientPrefs.loadPushNotifications();
    // The controller id of this installation: made once, kept, and adopted here.
    conditionalMode = ConditionalMode.fromKey(await _clientPrefs.loadConditionalMode());
    final storedControllerId = await _clientPrefs.loadControllerId();
    if (isValidControllerId(storedControllerId)) {
      HydraApiClient.controllerId = storedControllerId!;
    } else {
      await _clientPrefs.saveControllerId(HydraApiClient.controllerId);
    }
    final saved = await _authPrefs.loadConnection();
    _cacheUser = await _authPrefs.loadUsername() ?? '';
    final cached = await _stateCache.loadCachedState(
      scope: saved == null ? null : StateCache.scopeOf(saved.$1, saved.$2, _cacheUser),
    );
    if (cached != null) {
      state = HydraState(cached.raw);
      isShowingCachedState = true;
      cachedStateSavedAt = cached.savedAt;
    }
    final token = await _authPrefs.loadToken();
    biometricAvailable = await _biometricHelper.isAvailable();
    biometricEnabled = await _authPrefs.loadBiometricEnabled();
    biometricStrong = await _authPrefs.loadBiometricStrong();
    if (saved != null) {
      final (host, port) = saved;
      // The scheme this server was last seen on: a server that answered TLS is not probed over plain http again.
      final useTls = await _authPrefs.loadUseTls();
      final client = HydraApiClient(host, port, useTls: useTls);
      client.authToken = token;
      client.tokenRenewer = () => _renewedTokenOf(client);
      apiClient = client;
      activeServer = ServerInfo(host: host, port: port, useTls: useTls);
      _refreshListenOnly(interrupt: false);
      isLoggedIn = token != null;
    }
    // In the strong mode the Keychain read above already asked for the biometric, so the gate does not ask a second time.
    if (isLoggedIn && biometricEnabled && !biometricStrong) {
      if (biometricAvailable) {
        // No connect() until unlockWithBiometrics() succeeds: _RootGate reads needsBiometricUnlock before isLoggedIn and shows the gate.
        needsBiometricUnlock = true;
        notifyListeners();
        return;
      }
      // The gate is on but cannot be shown (Face ID permission withdrawn, fingerprints removed, a failing sensor): the lock fails
      // closed, the saved session is dropped and a full sign-in is required.
      isLoggedIn = false;
      apiClient?.authToken = null;
      await _authPrefs.clearToken();
      notifyListeners();
      return;
    }
    notifyListeners();
    // A restored session runs the same connect() as a sign-in (settings, socket, metrics poll).
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

  /// Keeps new security settings for the next connections. Returns what is
  /// wrong with them (and keeps nothing) or null when they were saved.
  Future<TlsProblem?> setTlsSettings(TlsSettings value) async {
    final problem = value.validate();
    if (problem != null) return problem;
    final clean = value.normalized();
    tlsSettings = clean;
    TlsSettingsStore.current = clean;
    await _tlsPrefs.save(clean);
    notifyListeners();
    return null;
  }

  Future<void> setBlockCommandsOnSavedData(bool value) async {
    blockCommandsOnSavedData = value;
    await _clientPrefs.saveBlockCommandsOnSavedData(value);
    notifyListeners();
  }

  // ---- Push notifications ----
  // The person turns them on in Settings (it needs their permission); the phone then registers its device token with the
  // server, which sends a notification when a job finishes or a global stop is issued. Off on the server by default.

  /// Whether the person wants push notifications from the server.
  bool pushNotifications = false;

  /// What became of the last attempt to register this phone with the server.
  PushState pushState = PushState.off;
  String? _pushToken;

  Future<void> setPushNotifications(bool value) async {
    pushNotifications = value;
    await _clientPrefs.savePushNotifications(value);
    if (value) {
      await syncPushRegistration();
    } else {
      final client = apiClient;
      final token = _pushToken;
      _pushToken = null;
      pushState = PushState.off;
      notifyListeners();
      if (client != null && token != null) {
        try {
          await client.deletePushDevice(token);
        } catch (_) {
          // The server forgets a dead token by itself.
        }
      }
      await _push.unregister();
    }
  }

  /// Registers this phone with the server when the person wants push notifications. Never raises an error on the
  /// screen: the outcome is left in [pushState].
  Future<void> syncPushRegistration() async {
    final client = apiClient;
    if (!pushNotifications || client == null || !isLoggedIn) return;
    pushState = PushState.registering;
    notifyListeners();
    try {
      if (!await _push.requestPermission()) {
        pushState = PushState.denied;
      } else {
        final token = await _push.deviceToken();
        if (token == null) {
          pushState = PushState.failed;
        } else {
          final language = (languageOverride ?? PlatformDispatcher.instance.locale).languageCode;
          await client.postPushDevice(token, language);
          _pushToken = token;
          pushState = PushState.registered;
        }
      }
    } on HydraApiException catch (e) {
      if (e.isNotFound) {
        pushState = PushState.serverOff;
      } else {
        pushState = PushState.failed;
        if (e.isSessionProblem) _forceLogout();
      }
    } catch (_) {
      pushState = PushState.failed;
    }
    notifyListeners();
  }

  // ---- Outside the app: notifications of a job, Live Activity, Apple Watch ----
  // Each one is off until the person turns it on (see state/external_surfaces.dart and docs/ios_feature_contract.json).

  /// Tells the surfaces outside the app what the state looks like now. Never raises: they are extras.
  void _publishSurfaces() {
    if (_disposed || !isLoggedIn) return;
    if (!surfaces.jobAlertsEnabled && !surfaces.liveActivityEnabled && !surfaces.watchEnabled) return;
    final robotsNow = [for (final r in robots) RobotSnapshot.of(r)];
    unawaited(surfaces.onState(robotsNow, connected: connectionStatus == 'connected').catchError((Object _) {}));
  }

  bool get jobAlertsEnabled => surfaces.jobAlertsEnabled;
  bool get liveActivityEnabled => surfaces.liveActivityEnabled;
  bool get liveActivityPushEnabled => surfaces.liveActivityPushEnabled;

  /// What became of the last token handed to the server; [LiveActivityPushState.off] while the option is off.
  LiveActivityPushState liveActivityPushState = LiveActivityPushState.off;
  bool get watchEnabled => surfaces.watchEnabled;

  /// Turns the local notifications on (asks the system for permission; they stay off when it is refused) or off.
  /// True when they are on afterwards.
  Future<bool> setJobAlerts(bool value) async {
    final on = await surfaces.setJobAlerts(value);
    await _clientPrefs.saveJobAlerts(on);
    notifyListeners();
    return on;
  }

  Future<void> setLiveActivity(bool value) async {
    await surfaces.setLiveActivity(value);
    await _clientPrefs.saveLiveActivity(value);
    notifyListeners();
  }

  /// Lets the server refresh the card of the Live Activity while the app is suspended (off by default). It needs the Live
  /// Activity option, and the server decides how much the card shows.
  Future<void> setLiveActivityPush(bool value) async {
    await surfaces.setLiveActivityPush(value);
    await _clientPrefs.saveLiveActivityPush(value);
    if (!value) liveActivityPushState = LiveActivityPushState.off;
    notifyListeners();
  }

  /// Hands the token of the activity to the server. True when it took it; a server without the route (404) leaves
  /// [LiveActivityPushState.serverOff], any other failure [LiveActivityPushState.failed]. Never raises.
  Future<bool> _registerActivityToken(String token, String robotId) async {
    final client = apiClient;
    if (client == null || !isLoggedIn) return false;
    try {
      await client.postLiveActivity(token, robotId);
      liveActivityPushState = LiveActivityPushState.registered;
      notifyListeners();
      return true;
    } on HydraApiException catch (e) {
      liveActivityPushState = e.isNotFound ? LiveActivityPushState.serverOff : LiveActivityPushState.failed;
      if (e.isSessionProblem) _forceLogout();
    } catch (_) {
      liveActivityPushState = LiveActivityPushState.failed;
    }
    notifyListeners();
    return false;
  }

  Future<void> _forgetActivityToken(String token) async {
    final client = apiClient;
    if (client == null) return;
    try {
      await client.deleteLiveActivity(token);
    } catch (_) {
      // The server forgets a dead token by itself.
    }
    if (liveActivityPushState == LiveActivityPushState.registered) {
      liveActivityPushState = LiveActivityPushState.off;
      notifyListeners();
    }
  }

  Future<void> setWatch(bool value) async {
    surfaces.setWatch(value);
    await _clientPrefs.saveWatch(value);
    notifyListeners();
  }

  // ---- Dictation for the assistant ----
  // Speech recognition fills the text box; the person reads it and sends it. It is never sent by itself.

  /// Whether the dictation button is shown in the assistant; off until the person turns it on.
  bool dictationEnabled = VoiceContract.enabledByDefault;

  /// Whether dictation may use the online recognition of Apple when the language has none on the device. Off by default.
  bool dictationOnline = false;

  Future<void> setDictation(bool value) async {
    dictationEnabled = value;
    await _clientPrefs.saveDictation(value);
    notifyListeners();
  }

  Future<void> setDictationOnline(bool value) async {
    dictationOnline = value;
    await _clientPrefs.saveDictationOnline(value);
    notifyListeners();
  }

  /// Listens once. The audio stays on the phone unless the person allowed the online recognition and the contract does
  /// not force the device alone.
  Future<SpeechOutcome> dictate() {
    final tag = languageOverride?.toLanguageTag() ?? PlatformDispatcher.instance.locale.toLanguageTag();
    return _speech.listen(
      languageTag: tag,
      onDeviceOnly: VoiceContract.onDeviceOnly && !dictationOnline,
      timeoutMs: VoiceContract.listenTimeoutMs,
    );
  }

  Future<void> cancelDictation() => _speech.cancel();

  // ---- Ecosystem tab ----

  EcosystemStatus ecosystem = EcosystemStatus.unavailable;
  bool ecosystemLoading = false;
  bool ecosystemLoaded = false;
  DateTime? _ecosystemAt;

  /// Reads GET /api/ecosystem/status. Called on entering the tab and by its refresh button, not polled; two reads are
  /// never closer than the minimum gap of the contract.
  Future<void> refreshEcosystem({DateTime? now}) async {
    if (apiClient == null || ecosystemLoading) return;
    final at = now ?? DateTime.now();
    final last = _ecosystemAt;
    if (last != null && at.difference(last).inMilliseconds < EcosystemContract.refreshMinIntervalMs) return;
    _ecosystemAt = at;
    ecosystemLoading = true;
    notifyListeners();
    try {
      ecosystem = await _authed((c) => c.getEcosystemStatus());
    } on HydraApiException catch (e) {
      ecosystem = EcosystemStatus.unavailable;
      if (e.isSessionProblem) _forceLogout();
    } catch (_) {
      ecosystem = EcosystemStatus.unavailable;
    } finally {
      ecosystemLoaded = true;
      ecosystemLoading = false;
      notifyListeners();
    }
  }


  // ---- Continuous jog with a dead-man, link health, pairing, alerts and relays of the watch, Work files ----
  // The numbers live in docs/robot_command_contract.json (identical in HYDRA-UMC-ANDROID-CONTROL). Every one of these starts
  // as the contract says: the continuous jog off, the link indicator and the block on a bad link on, the pairing off, the
  // alerts to the watch on (they still need the Apple Watch option), the two relays of the watch off.

  /// The continuous jog held by a dead-man and the health of the link to the server (see state/dead_man_jog_controller.dart).
  late final DeadManJogController deadMan = DeadManJogController(
    poster: _postCommand,
    pinger: _pingServer,
    situation: _deadManSituation,
    say: (error) {
      lastError = error;
      notifyListeners();
    },
    link: link,
  );

  /// False while the app is not on the screen (the socket is closed then and no jog may go on).
  bool _foreground = true;

  Future<int> _pingServer() {
    final client = apiClient;
    if (client == null) throw HydraApiException('Not connected');
    return client.pingRoundTripMs(const Duration(milliseconds: RobotCommandContract.linkProbeTimeoutMs));
  }

  bool _linkProbeActive() => connectionStatus == 'connected' && _foreground && isLoggedIn;

  DeadManSituation _deadManSituation(
    dynamic robotId, {
    required bool switchedOn,
    required bool alreadyRunning,
    required bool linkBlocks,
    required bool serverSupports,
  }) {
    final robot = state.robotById(robotId);
    return DeadManSituation(
      switchedOn: switchedOn,
      connected: apiClient != null && connectionStatus == 'connected',
      robotOnline: robot?.online == true,
      robotEnabled: robot?.isEnabled ?? true,
      robotPlaying: robot?.isPlaying == true,
      stopInProgress: stopAllInFlight || stopAllUnconfirmed,
      needsArming: jogNeedsArming(robotId),
      role: jwtRole(apiClient?.authToken),
      linkBlocks: linkBlocks,
      alreadyRunning: alreadyRunning,
      serverSupports: serverSupports,
    );
  }

  Future<void> setDeadManEnabled(bool value) async {
    deadMan.enabled = value;
    if (!value) deadMan.interrupt();
    deadMan.ensureProbe(_linkProbeActive);
    notifyListeners();
    await _clientPrefs.saveFlag(ClientFlags.deadManJog, value);
  }

  Future<void> setLinkBlockOnBadLink(bool value) async {
    deadMan.blockOnBadLink = value;
    notifyListeners();
    await _clientPrefs.saveFlag(ClientFlags.linkBlockJog, value);
  }

  Future<void> setLinkIndicator(bool value) async {
    deadMan.indicator = value;
    deadMan.ensureProbe(_linkProbeActive);
    notifyListeners();
    await _clientPrefs.saveFlag(ClientFlags.linkIndicator, value);
  }

  // ---- pairing by link ----

  /// Pairing by link: off until the person turns it on (see util/pairing_link.dart). [pairingOffer] waits for the answer.
  bool pairingEnabled = RobotCommandContract.pairingEnabledByDefault;
  PairingOffer? pairingOffer;

  /// The address the last accepted pairing gave, for the sign-in screen to show; [pairedStamp] changes with every one.
  String? pairedHost;
  int? pairedPort;
  int pairedStamp = 0;

  Future<void> setPairingEnabled(bool value) async {
    pairingEnabled = value;
    if (!value) pairingOffer = null;
    notifyListeners();
    await _clientPrefs.saveFlag(ClientFlags.pairing, value);
  }

  /// A text that may be a pairing link (the camera opened one, or the person pasted it). False when it is not a pairing link at
  /// all. While pairing is off nothing is read: the person is told. A valid offer is only SHOWN ([pairingOffer]); nothing is
  /// kept before [confirmPairing].
  Future<bool> receivePairing(String? text) async {
    if (!PairingLink.looksLikePairing(text)) return false;
    if (!pairingEnabled) {
      lastError = const HydraError(HydraErrorKind.pairingOff);
      notifyListeners();
      return true;
    }
    final result = PairingLink.parse(text);
    if (result.isOk) {
      pairingOffer = result.offer;
    } else {
      lastError = HydraError(HydraErrorKind.pairingProblem, {'problem': result.problem!.name});
    }
    notifyListeners();
    return true;
  }

  /// The text the person pasted: false (and a phrase on screen) when it is not a pairing link at all.
  Future<bool> readPastedPairing(String text) async {
    final taken = await receivePairing(text);
    if (!taken) report(HydraError(HydraErrorKind.pairingProblem, {'problem': PairingProblem.notAPairingLink.name}));
    return taken;
  }

  /// Puts a phrase on screen (the screens read [lastError]).
  void report(HydraError error) {
    lastError = error;
    notifyListeners();
  }

  /// The person accepted the offer on screen: the address is handed to the sign-in screen and the link always carries the fingerprint
  /// of the certificate, so the connection is set to require TLS and that certificate is pinned (replacing the one kept before).
  Future<void> confirmPairing() async {
    final offer = pairingOffer;
    if (offer == null) return;
    pairingOffer = null;
    await setTlsSettings(tlsSettings.copyWith(allowPlainHttp: false, allowPlainRemote: false, pinnedFingerprint: offer.fingerprint));
    pairedHost = offer.host;
    pairedPort = offer.port;
    pairedStamp++;
    notifyListeners();
  }

  void dismissPairing() {
    if (pairingOffer == null) return;
    pairingOffer = null;
    notifyListeners();
  }

  // ---- the watch: alerts and relays ----

  /// Alerts pushed to the paired watch (on by default, rationed; they need the Apple Watch option too); the relays of the
  /// presence and of the confirmation are off by default.
  bool watchAlertsEnabled = RobotCommandContract.watchAlertsEnabledByDefault;
  bool presenceRelayEnabled = RobotCommandContract.presenceRelayEnabledByDefault;
  bool voiceConfirmRelayEnabled = RobotCommandContract.voiceConfirmEnabledByDefault;

  final WatchAlertRules _watchAlertRules = WatchAlertRules();
  final WatchPresenceTracker _presenceTracker = WatchPresenceTracker();
  Timer? _watchAlertTimer;
  bool _presenceUnsupported = false;

  Future<void> setWatchAlertsEnabled(bool value) async {
    watchAlertsEnabled = value;
    if (value) {
      _ensureWatchAlertLoop();
    } else {
      _stopWatchAlertLoop();
    }
    notifyListeners();
    await _clientPrefs.saveFlag(ClientFlags.watchAlerts, value);
  }

  Future<void> setPresenceRelayEnabled(bool value) async {
    presenceRelayEnabled = value;
    if (!value) _presenceTracker.reset();
    notifyListeners();
    await _clientPrefs.saveFlag(ClientFlags.presenceRelay, value);
  }

  Future<void> setVoiceConfirmRelayEnabled(bool value) async {
    voiceConfirmRelayEnabled = value;
    notifyListeners();
    await _clientPrefs.saveFlag(ClientFlags.voiceConfirmRelay, value);
  }

  AppLocalizations _alertTexts() {
    final locale = languageOverride ?? PlatformDispatcher.instance.locale;
    try {
      return lookupAppLocalizations(locale);
    } catch (_) {
      return lookupAppLocalizations(const Locale('en'));
    }
  }

  /// The sentence of an alert, in the language of the app.
  String watchAlertText(WatchAlertEvent event) {
    final l10n = _alertTexts();
    final name = event.robotName ?? '';
    return switch (event.kind) {
      WatchAlertKind.connectionLost => l10n.watchAlertConnectionLost,
      WatchAlertKind.connectionRestored => l10n.watchAlertConnectionRestored,
      WatchAlertKind.robotOffline => l10n.watchAlertRobotOffline(name),
      WatchAlertKind.robotSafeMode => l10n.watchAlertRobotSafeMode(name),
      WatchAlertKind.stopNotConfirmed => l10n.watchAlertStopNotConfirmed,
      WatchAlertKind.stopConfirmed => l10n.watchAlertStopConfirmed,
    };
  }

  /// What the alert rules see of the plant right now.
  WatchAlertInput watchAlertInput() => WatchAlertInput(
        connected: connectionStatus == 'connected',
        robots: [
          for (final r in robots) WatchAlertRobot('${r.id}', r.name, r.online, r.isEnabled, r.isPlaying && !r.isPaused),
        ],
        stop: stopAllInFlight
            ? WatchAlertStop.sending
            : stopAllUnconfirmed
                ? WatchAlertStop.notConfirmed
                : stopAllResult != null
                    ? WatchAlertStop.done
                    : WatchAlertStop.none,
      );

  /// One look at the plant: the alerts that deserve the wrist are sent. A failure to deliver is not an error of the app.
  Future<void> watchAlertsTick() async {
    if (!watchAlertsEnabled || !surfaces.watchEnabled || !isLoggedIn) return;
    for (final event in _watchAlertRules.observe(watchAlertInput())) {
      await surfaces.sendWatchAlert(WatchAlert.of(event.severity, watchAlertText(event)).toMap());
    }
  }

  void _ensureWatchAlertLoop() {
    if (_watchAlertTimer != null || !watchAlertsEnabled || _disposed) return;
    _watchAlertTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      watchAlertsTick().catchError((Object e) {
        _logTelemetry('Watch alert failed: ${e.runtimeType}');
      });
    });
  }

  void _stopWatchAlertLoop() {
    _watchAlertTimer?.cancel();
    _watchAlertTimer = null;
    _watchAlertRules.reset();
  }

  /// The presence heartbeat of the watch, passed on to the server only while the operator switched the relay on. A heartbeat is
  /// never retried (the next one is the retry) and the server decides what a lost one means. A server without the route
  /// answers 404: the relay then stays quiet until the app starts again. PENDING in HYDRA-UMC-SERVER: the endpoint.
  Future<void> relayPresence(Map<dynamic, dynamic> message) async {
    if (!presenceRelayEnabled || apiClient == null) return;
    final WatchPresenceHeartbeat beat;
    try {
      beat = WatchPresenceHeartbeat.fromMap(message);
    } on ArgumentError {
      return;
    }
    final missed = _presenceTracker.onHeartbeat(beat);
    if (_presenceUnsupported) return;
    try {
      await _authed((c) => c.postPresence(beat.toServerJson(missed)));
    } on HydraApiException catch (e) {
      if (e.isNotFound) _presenceUnsupported = true;
      _logTelemetry('Presence relay refused: ${e.statusCode}');
    } catch (e) {
      _logTelemetry('Presence relay failed: ${e.runtimeType}');
    }
  }

  /// The second tap of a spoken order. Only when the operator switched the relay on, with a session; the server answers with an
  /// assistant reply for the new request id, which goes back to the watch. Nothing else can come out of the watch.
  /// PENDING in HYDRA-UMC-SERVER: the endpoint.
  Future<Map<String, Object?>?> relayVoiceConfirm(Map<dynamic, dynamic> message) async {
    final WatchVoiceConfirm confirm;
    try {
      confirm = WatchVoiceConfirm.fromMap(message);
    } on ArgumentError {
      return null;
    }
    final l10n = _alertTexts();
    Map<String, Object?> attention(String text, {bool speak = false, String? errorCode}) => {
          'requestId': confirm.requestId,
          'text': text,
          'level': 'ATTENTION',
          'speak': speak,
          'requiresConfirmation': false,
          'errorCode': ?errorCode,
        };
    if (!voiceConfirmRelayEnabled) return attention(l10n.watchConfirmRelayOff);
    if (apiClient == null) return attention(l10n.watchRelayConnectionUnavailable, speak: true, errorCode: 'connection_unavailable');
    try {
      final reply = await _authed((c) => c.postVoiceConfirm(confirm.toServerJson()));
      final token = reply['confirmationToken'];
      final validity = reply['confirmationValiditySeconds'];
      return {
        'requestId': '${reply['requestId'] ?? confirm.requestId}',
        'text': '${reply['text'] ?? ''}',
        'level': '${reply['level'] ?? 'INFO'}',
        'speak': reply['speak'] == true,
        'requiresConfirmation': reply['requiresConfirmation'] == true,
        // A token or validity the watch would refuse is dropped, not passed on: the reply itself still arrives.
        if (token is String && WatchVoiceConfirm.isValidToken(token)) 'confirmationToken': token,
        if (validity is num && validity >= 1 && validity <= RobotCommandContract.voiceConfirmValidityMaxSeconds)
          'confirmationValiditySeconds': validity.toInt(),
      };
    } catch (e) {
      _logTelemetry('Voice confirmation relay failed: ${e.runtimeType}');
      return attention(l10n.watchRelayConnectionUnavailable, speak: true, errorCode: 'connection_unavailable');
    }
  }

  // ---- Work files (trajectories) ----

  /// The work files of the selected robot's folder; null before the list was read.
  List<String>? workFiles;
  bool workBusy = false;

  /// False once the server answered that it does not know `trajectory`.
  bool workServerSupports = true;

  /// The folder of [robotId]'s work files on the server, or null when the configured folder is not a plain relative path.
  String? workFolderOf(dynamic robotId) {
    final robot = state.robotById(robotId);
    if (robot == null) return null;
    return WorkFiles.folderFor(state.raw['worksPaths'], robotId, robot.name);
  }

  WorkBlock workBlock(dynamic robotId, {bool tableMissing = false}) {
    final robot = robotId == null ? null : state.robotById(robotId);
    return WorkFiles.blockOf(WorkSituation(
      connected: apiClient != null,
      robotOnline: robot?.online == true,
      robotEnabled: robot?.isEnabled ?? true,
      robotPlaying: robot?.isPlaying == true,
      stopInProgress: stopAllInFlight || stopAllUnconfirmed,
      role: jwtRole(apiClient?.authToken),
      tableMissing: tableMissing,
      serverSupports: workServerSupports,
    ));
  }

  /// The work loaded in [robotId] (the name the server keeps in `selectedWorkFile`), or an empty text.
  String selectedWorkOf(dynamic robotId) {
    final value = state.robotById(robotId)?.raw['selectedWorkFile'];
    return value is String ? value : '';
  }

  /// Reads the names of the work files of [robotId]'s folder.
  Future<void> loadWorkList(dynamic robotId) async {
    if (apiClient == null) {
      lastError = const HydraError(HydraErrorKind.notConnected);
      notifyListeners();
      return;
    }
    final folder = workFolderOf(robotId);
    if (folder == null) {
      lastError = const HydraError(HydraErrorKind.workLoadFailed);
      notifyListeners();
      return;
    }
    workBusy = true;
    workFiles = null;
    notifyListeners();
    try {
      final body = await _authed((c) => c.getWorkIndexBody(folder));
      workFiles = WorkFiles.parseIndex(body) ?? const [];
    } on HydraApiException catch (e) {
      // A folder that does not exist yet is an empty list, not an error.
      if (e.isNotFound) {
        workFiles = const [];
      } else {
        lastError = const HydraError(HydraErrorKind.workLoadFailed);
      }
      if (e.isSessionProblem) _forceLogout();
    } catch (_) {
      lastError = const HydraError(HydraErrorKind.workLoadFailed);
    } finally {
      workBusy = false;
      notifyListeners();
    }
  }

  /// Loads the work file [file] into [robotId] with the `trajectory` command. It NEVER starts the playback. Nothing is read or
  /// sent when a rule refuses (the robot is playing, in safe mode...); the file is checked here the way the server will check
  /// it, so a bad file never goes out.
  Future<void> selectWork(dynamic robotId, String file) async {
    final client = apiClient;
    if (client == null) {
      lastError = const HydraError(HydraErrorKind.notConnected);
      notifyListeners();
      return;
    }
    final folder = workFolderOf(robotId);
    if (folder == null || !WorkFiles.isSafeFileName(file)) {
      lastError = const HydraError(HydraErrorKind.workLoadFailed);
      notifyListeners();
      return;
    }
    final early = workBlock(robotId);
    if (early != WorkBlock.none) {
      lastError = HydraError(HydraErrorKind.workBlocked, {'block': early.name});
      notifyListeners();
      return;
    }
    workBusy = true;
    notifyListeners();
    try {
      final loaded = WorkFiles.parsePoints(await _authed((c) => c.getWorkFileBody(folder, file)));
      if (!loaded.isOk) {
        lastError = HydraError(HydraErrorKind.workInvalidFile, {'file': file});
      } else {
        final block = workBlock(robotId, tableMissing: loaded.usesTable && state.robotById(robotId)?.hasXYTable != true);
        if (block != WorkBlock.none) {
          lastError = HydraError(HydraErrorKind.workBlocked, {'block': block.name});
        } else {
          await _sendAtomicCommand(
            RobotCommandContract.trajectory,
            params: WorkFiles.trajectoryParams(loaded.points!, file),
            robotIdOverride: robotId,
            localMutate: (r) => r.raw['selectedWorkFile'] = file,
          );
        }
      }
    } on HydraApiException catch (e) {
      lastError = const HydraError(HydraErrorKind.workLoadFailed);
      if (e.isSessionProblem) _forceLogout();
    } catch (_) {
      lastError = const HydraError(HydraErrorKind.workLoadFailed);
    } finally {
      workBusy = false;
      notifyListeners();
    }
  }

  // ---- Connection diagnostics ----

  /// The round-trip times towards the server, kept for the level of the link.
  final LinkHealth link = LinkHealth();

  /// Sends the probes of the contract (a few small reads of GET /api/hydra-info), feeds [link] with the answers and
  /// returns what the screen shows. Null before a server is chosen.
  Future<ConnectionDiagnostics?> runDiagnostics() async {
    final client = apiClient;
    final server = activeServer;
    if (client == null || server == null) return null;
    final latencies = <int?>[];
    int? api;
    String? app;
    for (var i = 0; i < DiagnosticsContract.probeCount; i++) {
      final probe = await client.probeInfo(timeout: const Duration(milliseconds: DiagnosticsContract.probeTimeoutMs));
      latencies.add(probe.rttMs);
      if (probe.rttMs != null) {
        link.record(probe.rttMs!);
        api = probe.remoteApiVersion ?? api;
        app = probe.serverAppVersion ?? app;
      } else {
        link.recordFailure();
      }
      if (i + 1 < DiagnosticsContract.probeCount) {
        await Future<void>.delayed(const Duration(milliseconds: DiagnosticsContract.probeGapMs));
      }
    }
    final scheme = client.usesTls ? 'https' : 'http';
    return ConnectionDiagnostics(
      scheme: scheme,
      host: server.host,
      port: server.port,
      trust: ConnectionDiagnostics.trustFor(
        scheme: scheme,
        pinnedFingerprint: tlsSettings.pinnedFingerprint,
        customCaPem: tlsSettings.customCaPem,
      ),
      pinnedFingerprint: tlsSettings.pinnedFingerprint,
      remoteApiVersion: api,
      serverAppVersion: app,
      clientVersion: kAppVersion,
      latenciesMs: latencies,
      level: link.level,
      websocket: connectionStatus,
      role: jwtRole(client.authToken),
      showingSavedData: isShowingCachedState,
    );
  }

  /// Chooses whether HOME/RESET is offered, and keeps the choice. Switching it off also drops a confirmation under way.
  Future<void> setHomeResetEnabled(bool value) async {
    homeResetEnabled = value;
    if (!value) homeResetConfirmation.cancel();
    notifyListeners();
    await _clientPrefs.saveHomeReset(value);
  }

  /// What stops HOME/RESET of [robotId] right now, from this app's view; [HomeResetBlock.none] when it may go on.
  HomeResetBlock homeResetBlock([dynamic robotId, DateTime? now]) {
    final id = robotId ?? selectedRobotId;
    final robot = id == null ? null : state.robotById(id);
    return homeResetBlockOf(HomeResetSituation(
      switchedOn: homeResetEnabled,
      connected: apiClient != null,
      robotOnline: robot?.online == true,
      robotEnabled: robot?.isEnabled ?? true,
      robotPlaying: robot?.isPlaying == true,
      jogInFlight: id != null && commands.hasJogInFlight(id),
      stopInProgress: stopAllInFlight || stopAllUnconfirmed,
      needsArming: id != null && jogNeedsArming(id, now),
      role: jwtRole(apiClient?.authToken),
      hasPose: robot?.raw['pos'] is Map,
      serverSupports: homeResetServerSupports,
    ));
  }

  /// Sends the reset (the selected robot to its zero position) once the confirmation in steps is complete. The
  /// screen calls it only after the last step; the checks run again here, so a robot that started moving between
  /// the steps is not reset. A refusal shows its own phrase and nothing goes out.
  void homeReset() {
    if (listenOnly) return;
    final id = selectedRobotId;
    if (id == null) return;
    final block = homeResetBlock(id);
    if (block != HomeResetBlock.none) {
      lastError = HydraError(HydraErrorKind.homeResetBlocked, {'block': block.name});
      notifyListeners();
      return;
    }
    // The pose is shown at zero at once; the server's answer (or a failure, which restores it) settles it.
    _sendAtomicCommand(RobotCommandContract.reset, params: {'target': 'robot'}, localMutate: (r) {
      for (final axis in const ['x', 'y', 'z', 'a', 'b', 'c']) {
        r.setPosAxis(axis, 0.0);
      }
    });
  }

  Future<void> setConfirmPlay(bool value) async {
    confirmPlay = value;
    await _clientPrefs.saveConfirmPlay(value);
    notifyListeners();
  }

  Future<void> setBiometricEnabled(bool value) async {
    biometricEnabled = value;
    await _authPrefs.saveBiometricEnabled(value);
    // The strong mode rests on the gate: switching the gate off ends it, and the session moves back to the normal store.
    if (!value && biometricStrong) await setBiometricStrong(false);
    notifyListeners();
  }

  /// Turns the strong mode on (only while the gate is on and the device has biometrics) or off. False when the device refused the
  /// protected Keychain item (no passcode or biometrics enrolled) or the person cancelled the prompt; the mode is then unchanged.
  Future<bool> setBiometricStrong(bool value) async {
    if (value && !(biometricEnabled && biometricAvailable)) return false;
    try {
      await _authPrefs.setBiometricStrong(value);
    } catch (e) {
      _logTelemetry('Strong biometric mode not changed: ${e.runtimeType}');
      return false;
    }
    biometricStrong = value;
    notifyListeners();
    return true;
  }

  Future<bool> login(ServerInfo server) async {
    _myUsername = null;
    // A sign-out still erasing the previous session must finish first.
    await _pendingLogout;
    // The client of the previous session is closed before it is replaced: each one owns its connection pool.
    apiClient?.close();
    final client = HydraApiClient(server.host, server.port);
    client.tokenRenewer = () => _renewedTokenOf(client);
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
      // The client resolves the scheme itself (HydraApiClient._resolveScheme): the server is stored with the scheme it answers on.
      activeServer = server.copyWith(useTls: client.usesTls);
      _refreshListenOnly(interrupt: false);
      await _authPrefs.saveConnection(server.host, server.port);
      await _authPrefs.saveUseTls(client.usesTls);
      // POST /api/login also returns an opaque refreshToken (an older server omits it). A sign-in always REPLACES the stored one,
      // so the refresh token of a previous account is never used for this session.
      final refreshToken = resp['refreshToken'] as String?;
      await _authPrefs.saveToken(token, server.username, refreshToken: refreshToken, replaceRefreshToken: true);
      _cacheUser = server.username;
      lastError = null;
      _logTelemetry('Login successful');
      notifyListeners();
      await connect();
      return true;
    } catch (e) {
      lastError = isTlsFailure(e)
          ? const HydraError(HydraErrorKind.tlsFailed)
          : HydraError(HydraErrorKind.loginError, {'error': '$e'});
      _logTelemetry('Login error: $e');
      notifyListeners();
      return false;
    }
  }

  void logout() {
    // The robots this installation holds are released with the session, not left reserved until they expire.
    final held = [
      for (final claim in claims)
        if (claimStanding(claim, _myUsername ?? activeServer?.username ?? '', controllerId) == ClaimStanding.mineHere) claim.robotId,
    ];
    _myUsername = null;
    claims = const [];
    safetyByRobot.clear();
    jogArmedUntil.clear();
    deadMan.interrupt();
    deadMan.stopProbe();
    _stopWatchAlertLoop();
    workFiles = null;
    isLoggedIn = false;
    unawaited(surfaces.onSessionEnd());
    ecosystem = EcosystemStatus.unavailable;
    ecosystemLoaded = false;
    link.reset();
    _ws?.disconnect();
    _bleClient?.disconnect();
    if (isBleScanning) unawaited(_bleScanner.stop());
    _metricsTimer?.cancel();
    _stateCacheTimer?.cancel();
    // A debounced command still waiting (a speed change) is dropped: it would go out without a token.
    commands.reset();
    stopAllResult = null;
    stopAllUnconfirmed = false;
    // The bearer token is cleared from the live client as well as from storage.
    final client = apiClient;
    if (client != null) {
      for (final id in held) {
        unawaited(client.postRelease(id).catchError((Object _) => <String, dynamic>{}));
      }
    }
    final pushToken = _pushToken;
    _pushToken = null;
    pushState = PushState.off;
    if (client != null && pushToken != null) {
      // Before the bearer token is cleared: this phone must not keep receiving what this account is told.
      unawaited(client.deletePushDevice(pushToken).catchError((Object _) {}));
    }
    client?.authToken = null;
    _pendingLogout = _finishLogout(client);
    notifyListeners();
  }

  // In order: read the refresh token, revoke it on the server (best effort), then erase the stored session and the offline copy of
  // the robot state (it can hold camera credentials).
  Future<void> _finishLogout(HydraApiClient? client) async {
    try {
      final refreshToken = await _authPrefs.loadRefreshToken();
      if (client != null && refreshToken != null) await client.logoutRemote(refreshToken);
    } finally {
      await _authPrefs.clearToken();
      await _stateCache.clear();
    }
  }

  // The session is over (the token is dead and could not be renewed): the user is told and everything is closed (socket, metrics
  // poll, timers, stored tokens).
  void _forceLogout() {
    if (!isLoggedIn) return;
    lastError = const HydraError(HydraErrorKind.wsAuthRejected);
    connectionStatus = 'disconnected';
    logout();
  }

  /// Tries to recover a WebSocket 1008 (auth) close by exchanging the stored refresh token for a new access token before the session
  /// is declared dead. The app never stores a password, so there is no re-login to replay. Fails closed where a real sign-in is
  /// still correct: no refresh token on file, or a refusal (401) because the refresh token expired or the account was revoked.
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

  // Renewal and the repeat of a request after an expired token belong to the SessionManager; these are the entry points to it.
  Future<bool> _renewSession() => _session.renewSession();

  // Called by the interceptor of the http client (network/renewing_client.dart) when a request is answered with an expired
  // session. It is the same single renewal; a client that is no longer the live one is not renewed.
  Future<String?> _renewedTokenOf(HydraApiClient client) async {
    if (!identical(client, apiClient)) return null;
    return await _renewSession() ? client.authToken : null;
  }

  Future<T> _authed<T>(Future<T> Function(HydraApiClient client) call) => _session.authed(call);

  // The server closed the socket (or said it would) because the token is dead. The error frame and the 1008 close after it are one
  // event: renew once and reopen the socket; only a failed renewal signs out.
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
    _foreground = true;
    if (!isLoggedIn || needsBiometricUnlock) return;
    if (connectionStatus == 'connected' || connectionStatus == 'connecting') return;
    unawaited(connect());
  }

  /// Called when the app is backgrounded (AppLifecycleState.paused, not the transient `inactive` of a system alert or the app
  /// switcher). It closes the socket and stops the metrics poll at once instead of leaving them to a connection the system may
  /// suspend. Safe while signed out or already disconnected; `connect()` (through `reconnectIfNeeded()` on resume) restores both.
  void pauseForBackground() {
    _foreground = false;
    // Leaving the screen ends a held continuous jog.
    deadMan.interrupt();
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
      // Through _authed(): a token that expired while the app was closed is renewed with the refresh token.
      final settings = await _authed((c) => c.getSettings());
      state = HydraState(settings);
      isShowingCachedState = false;
      _ensureSelectedRobot();
      if (client.usesTls) unawaited(_authPrefs.saveUseTls(true));
      _logTelemetry('Initial state synchronized via REST');
      notifyListeners();
    } catch (e) {
      lastError = isTlsFailure(e)
          ? const HydraError(HydraErrorKind.tlsFailed)
          : HydraError(HydraErrorKind.fetchFailed, {'error': '$e'});
      connectionStatus = 'error';
      _logTelemetry('REST sync error: $e');
      if (e is HydraApiException && e.isSessionProblem) {
        // The token is dead and could not be renewed: sign out and stop here, without opening the socket or the metrics poll.
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
        if (status == WsStatus.connected) {
          deadMan.ensureProbe(_linkProbeActive);
          _ensureWatchAlertLoop();
        } else if (status == WsStatus.disconnected) {
          // A held jog must not outlive the connection: its axis is stopped (the server also stops it by itself).
          deadMan.interrupt();
          deadMan.stopProbe();
        }
        notifyListeners();
      },
      onSettings: (payload) {
        state = HydraState(payload);
        isShowingCachedState = false;
        _ensureSelectedRobot();
        notifyListeners();
      },
      onDelta: _applyRobotDelta,
      onClaims: _applyClaimsPush,
      onError: (error) {
        lastError = error;
        _logTelemetry('WebSocket error: ${error.params['message'] ?? error.params['error'] ?? error.kind.name}');
        // The "Access denied" frame and the 1008 close (wsAuthRejected) both mean the token is dead. A connection failure
        // (wsConnectionLost, wsConnectFailed) is about connectivity, never about the session.
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
    unawaited(syncPushRegistration());
    _listenToShortcuts();
    unawaited(_flushShortcutStop());
    _metricsTimer?.cancel();
    _metricsTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        // Carries the bearer token: a server with HYDRA_UMC_INFO_AUTH=required answers 401 to an open read.
        final m = await client.getSystemMetrics();
        metricsListenable.value = SystemMetrics(
          cpuLoad: _asInt(m['cpu_load']),
          memoryUsage: _asInt(m['memory_usage']),
          temp: m['temp'] is num ? (m['temp'] as num).toDouble() : 0.0,
          uptime: _asInt(m['uptime']),
          tempIsReal: m['temp_is_real'] != false,
        );
      } catch (_) {
        // Best effort: a missed poll keeps the last reading.
      }
    });
  }

  /// Sends a typed or recognised transcript of the in-app assistant through POST /api/voice/turn. A reply carries only text and
  /// status: it never calls sendAtomicCommand and never changes the robot state.
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

  /// Applies one {controllerId, robotId, patch, cameraId?, cameraPatch?} delta in place on the maps of state.raw (RobotView and
  /// ControllerView read through to them, so every screen sees it at once).
  ///
  /// The robot is looked up by controllerId and robotId, because a delta may target a robot of a controller that is not the active
  /// one. When the robot does not exist locally the delta is discarded and a full reload is forced: a partial patch never creates
  /// a robot.
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

  /// Applies [command] and [params] to [robotId] (the selected robot by default) and, when [propagateToCombined] is true, to its
  /// combinedWith robots: locally at once through [localMutate], then through the atomic endpoint. A failure restores the previous
  /// values (see the contract in the header of this file).
  Future<void> _sendAtomicCommand(
    String command, {
    Map<String, dynamic>? params,
    bool propagateToCombined = false,
    dynamic robotIdOverride,
    Duration debounce = Duration.zero,
    required void Function(RobotView) localMutate,
  }) async {
    if (listenOnly && command != RobotCommandContract.stop && command != RobotCommandContract.disable) return;
    final robotId = robotIdOverride ?? selectedRobotId;
    if (robotId == null) return;
    // A stop (or safe mode) of the robot ends a continuous jog that is held.
    if (command == RobotCommandContract.stop || command == RobotCommandContract.disable) deadMan.interrupt();
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
      // Nothing was changed yet, so there is nothing to roll back; the person is told there is no connection.
      lastError = const HydraError(HydraErrorKind.notConnected);
      notifyListeners();
      return;
    }

    // A jog the server requires to be armed and that is not, or one above the
    // limit it holds for this robot's model, is not sent at all (the server
    // checks both again). Checked before the optimistic change, like the client above.
    if (command == 'jog' || command == 'table') {
      if (jogNeedsArming(robotId)) {
        lastError = const HydraError(HydraErrorKind.jogNotArmed);
        notifyListeners();
        return;
      }
      final amount = params?['amount'];
      // A table move is checked as a whole, and a relative one also by where it ends.
      final double? exceeded;
      if (command == 'table') {
        final xy = target.xyTablePos;
        exceeded = params == null
            ? null
            : tableLimitExceeded(
                params,
                safetyByRobot[robotId]?.jog,
                currentX: (xy['x'] as num?)?.toDouble() ?? 0.0,
                currentY: (xy['y'] as num?)?.toDouble() ?? 0.0,
              );
      } else {
        exceeded = jogLimitExceeded(
          amount is num ? amount.toDouble() : 0.0,
          safetyByRobot[robotId]?.jog,
          absolute: params?['absolute'] == true,
        );
      }
      if (exceeded != null) {
        lastError = HydraError(HydraErrorKind.jogOverLimit, {'limit': formatLimit(exceeded)});
        notifyListeners();
        return;
      }
    }

    final affectedIds = <dynamic>[robotId];
    if (propagateToCombined) affectedIds.addAll(target.combinedWith);

    // Deep-copy snapshot of every affected robot's raw state before mutating (localMutate() edits the nested maps in place, so a shallow copy could not
    // undo anything). The local change is applied at once even when `debounce` delays the send: only the request is coalesced, not the feedback.
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
        // A newer command of the same robot has started since this snapshot (see _commandGeneration): this failure is stale and
        // must not overwrite what the newer command applied.
        if (_commandGeneration[entry.key] != myGeneration[entry.key]) continue;
        final r = state.robotById(entry.key);
        if (r != null) {
          r.raw
            ..clear()
            ..addAll(entry.value);
        }
      }
    }

    final isStop = command == RobotCommandContract.stop;
    final isJog = command == RobotCommandContract.jog || command == RobotCommandContract.table;

    Future<void> send() async {
      if (isJog) commands.jogStarted(robotId);
      try {
        final answer = await commands.send(robotId, command, payload, _postCommand);
        final warnings = RobotCommandRepository.warningsOf(answer);
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
        // Any failure, not only HydraApiException (a timeout, a refused connection or a DNS failure is none): roll back to the snapshot and report it,
        // so the screen never shows a command that did not reach the robot.
        rollback();
        lastError = _commandError(command, e);
        // An older server does not have `reset`: remember it, so the button explains instead of sending again.
        if (command == RobotCommandContract.reset && e is HydraApiException && isUnknownCommandAnswer(e.statusCode, e.code, e.serverMessage)) {
          homeResetServerSupports = false;
        }
        if (command == RobotCommandContract.trajectory && e is HydraApiException && isUnknownCommandAnswer(e.statusCode, e.code, e.serverMessage)) {
          workServerSupports = false;
        }
        // The robot changed since this app read it: read it again so the screen shows what it is now.
        if (e is HydraApiException && e.isRevisionMismatch) unawaited(_refreshRobot(robotId));
        // The arming ended (it times out, or a stop cleared it): the screen offers to arm again.
        if (e is HydraApiException && e.isJogNotArmed) jogArmedUntil.remove(robotId);
        _logTelemetry('TX error [$command]: $e');
        if (e is HydraApiException && e.isSessionProblem) {
          // The renewal inside _authed() already failed: the session is over.
          _forceLogout();
        }
        notifyListeners();
      } finally {
        if (isJog) commands.jogEnded(robotId);
      }
    }

    // Debounce: a send still pending for this command name is cancelled and a new one is scheduled after `debounce`, so a burst
    // (every frame of a slider drag) becomes one POST once it settles.
    await commands.debounce(command, debounce, send);
  }

  /// How one command reaches the server: through [_authed], so an expired session is renewed once and the write repeated.
  /// A stop goes out with short timeouts.
  Future<Map<String, dynamic>> _postCommand(
    dynamic robotId,
    Map<String, dynamic> payload, {
    required bool urgent,
    String? ifMatch,
  }) async {
    final command = payload['command'];
    if (listenOnly && command != RobotCommandContract.stop && command != RobotCommandContract.disable) {
      throw StateError('listen only');
    }
    return _postCommandUnguarded(robotId, payload, urgent: urgent, ifMatch: ifMatch);
  }

  Future<Map<String, dynamic>> _postCommandUnguarded(
    dynamic robotId,
    Map<String, dynamic> payload, {
    required bool urgent,
    String? ifMatch,
  }) =>
      _authed(
        (c) => c.postRobotCommand(
          robotId,
          payload,
          timeout: urgent ? const Duration(seconds: 2) : const Duration(seconds: 5),
          ifMatch: ifMatch,
        ),
      );

  // Conditional writes (contract v2, block 2): every write carries the revision of the robot this app last saw
  // (If-Match), and the server refuses it with 412 when the robot changed in between.

  /// Which writes are checked (chosen in the list of reservations); the standard mode by default.
  ConditionalMode conditionalMode = ConditionalMode.standard;

  /// Sends every robot command: revisions, retry of a stop, `table` fallback, jogs on the wire, debounce and timings.
  late final RobotCommandRepository commands = RobotCommandRepository(conditionalMode: () => conditionalMode);

  /// The last revision seen of each robot.
  RevisionTracker get revisions => commands.revisions;

  /// When the server last pushed the reservations (this device's clock); null before the first push.
  DateTime? claimsPushedAt;

  /// Chooses which writes are checked, and keeps the choice.
  Future<void> setConditionalMode(ConditionalMode mode) async {
    conditionalMode = mode;
    notifyListeners();
    await _clientPrefs.saveConditionalMode(mode.key);
  }

  /// The id of the controller that holds [robotId] in the settings tree, or null.
  String? _controllerIdOf(dynamic robotId) {
    final controllers = state.raw['controllers'];
    if (controllers is! List) return null;
    for (final c in controllers) {
      if (c is! Map) continue;
      final robots = c['robots'];
      if (robots is! List) continue;
      for (final r in robots) {
        if (r is Map && r['id'] == robotId) return c['id'] is String ? c['id'] as String : null;
      }
    }
    return null;
  }

  /// Reads one robot again (GET /api/robot/:id, which also gives the revision to use next) and puts it on screen.
  /// Called after a 412: the robot changed under this app, and what is shown may be behind. Never raises an error.
  Future<void> _refreshRobot(dynamic robotId) async {
    if (apiClient == null) return;
    try {
      final read = await _authed((c) => c.getRobot(robotId));
      if (read == null) return;
      revisions.learn(robotId, read.revision);
      final controllerId = _controllerIdOf(robotId);
      if (controllerId == null) return;
      _applyRobotDelta({'controllerId': controllerId, 'robotId': robotId, 'patch': read.robot});
    } catch (e) {
      if (e is HydraApiException && e.isSessionProblem) _forceLogout();
    }
  }

  /// The reservations the server pushed (WebSocket message `claims`): replaces the list and the arming of this app's own reservations.
  void _applyClaimsPush(Map<String, dynamic> msg) {
    final list = ClaimInfo.listFromJson(msg);
    claims = list;
    final now = DateTime.now();
    claimsPushedAt = now;
    for (final claim in list) {
      if (claim.controllerId != controllerId) continue;
      final until = claim.jogArmedUntil;
      final ttl = safetyByRobot[claim.robotId]?.armTtlMs ?? 60000;
      // The server clock and this device clock may differ: the arming is shown as ending no later than its length allows.
      if (until != null && until > now.millisecondsSinceEpoch) {
        final byServer = DateTime.fromMillisecondsSinceEpoch(until);
        final byLength = now.add(Duration(milliseconds: ttl));
        jogArmedUntil[claim.robotId] = byServer.isBefore(byLength) ? byServer : byLength;
      } else {
        jogArmedUntil.remove(claim.robotId);
      }
    }
    notifyListeners();
  }

  /// Whether the server pushed the reservations recently, so the poll of GET /api/claims can rest.
  bool claimsArePushed([DateTime? now, Duration within = const Duration(seconds: 30)]) {
    final at = claimsPushedAt;
    return at != null && (now ?? DateTime.now()).difference(at) < within;
  }

  // The user-facing error for a command that failed, by what the server said.
  HydraError _commandError(String command, Object e) {
    if (e is HydraApiException) {
      if (command == RobotCommandContract.reset && isUnknownCommandAnswer(e.statusCode, e.code, e.serverMessage)) {
        return HydraError(HydraErrorKind.homeResetBlocked, {'block': HomeResetBlock.notSupported.name});
      }
      if (command == RobotCommandContract.reset && e.isPermissionDenied) {
        return HydraError(HydraErrorKind.homeResetBlocked, {'block': HomeResetBlock.role.name});
      }
      if (e.isStaleSequence) return HydraError(HydraErrorKind.staleSequence, {'command': command});
      if (e.isHomeRejected) return HydraError(HydraErrorKind.homeRejected, {'command': command});
      if (e.isRevisionMismatch) return HydraError(HydraErrorKind.revisionChanged, {'command': command});
      if (e.isJogNotArmed) return const HydraError(HydraErrorKind.jogNotArmed);
      final readOnlyKind = HydraErrorKind.values.asNameMap()['serverReadOnly'];
      if (readOnlyKind != null && e.code == 'server-read-only') return HydraError(readOnlyKind, {'command': command});
      if (e.isRobotDisabled) return HydraError(HydraErrorKind.robotDisabled, {'command': command});
      if (e.isEnableNotAllowed) return const HydraError(HydraErrorKind.enableNotAllowed);
      if (e.isAdminRequired) return const HydraError(HydraErrorKind.adminRequired);
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
        // Sent as an explicit desired state, computed once from the selected robot and applied to its whole combined group, so a
        // pair never drifts in opposite directions.
        final paused = !(selectedRobot?.isPaused ?? false);
        _sendAtomicCommand(command, params: {'paused': paused}, propagateToCombined: true, localMutate: (r) => r.setPaused(paused));
      case 'stop':
        _sendAtomicCommand(command, propagateToCombined: true, localMutate: (r) => r.stop());
      // Safe mode of the selected robot (only this robot, never its combined group). `disable` stops it and the server
      // then refuses everything but STOP; `enable` brings it back, is off by default on the server and only for an
      // administrator, so the server may answer 403.
      case 'disable':
        _sendAtomicCommand(command, localMutate: (r) {
          r.stop();
          r.setEnabled(false);
        });
      case 'enable':
        _sendAtomicCommand(command, localMutate: (r) => r.setEnabled(true));
      default:
        lastError = HydraError(HydraErrorKind.unknownCommand, {'command': command});
        notifyListeners();
    }
  }

  // ---- Global STOP -------------------------------------------------------
  //
  // One tap, no confirmation, every robot: POST /api/stop-all. It waits for no roster refresh and a reservation held by another
  // account never blocks it.

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

  // ---- The global stop asked for by a system shortcut ----
  // The Shortcuts app, Siri, the Action button and the quick action of the icon leave a request (ios/Runner/
  // GlobalStopShortcut.swift). It is served with the very same stopAll() the STOP button uses; one that cannot go out yet
  // (not signed in, waiting for the biometric prompt) waits one minute for the session and is dropped after that.
  DateTime? _pendingShortcutStopAt;
  bool _shortcutListening = false;

  /// How long a request of a shortcut waits for a session.
  static const Duration shortcutStopMaxAge = Duration(seconds: 60);

  void _listenToShortcuts() {
    if (_shortcutListening) return;
    _shortcutListening = true;
    _shortcuts.onGlobalStopRequested(() => unawaited(serveShortcutStop()));
    unawaited(serveShortcutStop());
  }

  /// Picks up the request of a shortcut, if one is waiting, and serves it or keeps it for the session.
  Future<void> serveShortcutStop() async {
    if (await _shortcuts.takeGlobalStop()) _pendingShortcutStopAt = DateTime.now();
    await _flushShortcutStop();
  }

  Future<void> _flushShortcutStop() async {
    final at = _pendingShortcutStopAt;
    if (at == null) return;
    if (DateTime.now().difference(at) > shortcutStopMaxAge) {
      _pendingShortcutStopAt = null;
      return;
    }
    if (!isLoggedIn || apiClient == null || needsBiometricUnlock) return;
    _pendingShortcutStopAt = null;
    await stopAll();
  }

  /// Stops every robot at once. Never throws.
  Future<void> stopAll() async {
    // The global STOP ends any continuous jog first: its own stop goes out before and together with this one.
    deadMan.interrupt();
    _stopAllInFlight++;
    notifyListeners();
    try {
      StopAllResult? result;
      Object? failure;
      try {
        result = StopAllResult.fromJson(await _postStopAllWithRetry());
      } on HydraApiException catch (e) {
        if (e.isRateLimited || e.isNotFound) {
          // Over the rate limit of the global route, or a server without it: the robots are stopped one by one.
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

  // Reads the state again after a STOP (the socket usually delivered it first); a failure is ignored.
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
  // Reservations are optional: a robot nobody reserved is commanded as before. The controller id (HydraApiClient.controllerId) goes
  // with every reserve, release, jog-arm and command, so a reservation belongs to the account and to this installation.

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

  // The account name of this session; a restored session has no username on the server entry, so the saved one is read once.
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
  Future<void> refreshAccess({bool fromPoll = false}) async {
    if (apiClient == null) return;
    final robotId = selectedRobotId;
    if (_myUsername == null) {
      final named = activeServer?.username ?? '';
      _myUsername = named.isNotEmpty ? named : await _authPrefs.loadUsername();
    }
    // The server pushes the reservations when they change: while a push is fresh the poll does not ask for them.
    if (!(fromPoll && claimsArePushed())) {
      try {
        claims = await _authed((c) => c.getClaims());
      } catch (e) {
        if (e is HydraApiException && e.isSessionProblem) _forceLogout();
      }
    }
    if (robotId != null) {
      try {
        final safety = await _authed((c) => c.getRobotSafety(robotId));
        if (safety != null) {
          safetyByRobot[robotId] = safety;
          final until = safety.jogArmedUntil;
          final now = DateTime.now();
          // The clocks may differ: the arming is shown as ending no later than its length allows.
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
    if (robotId != null) unawaited(_renewOwnClaim(robotId));
  }

  bool _renewingClaim = false;

  /// Keeps a reservation this installation holds alive while the Control screen is open (it polls this): asks for it again
  /// when it is about to end, so a long session does not lose the robot in the middle of a move. Silent: a failure here
  /// is shown by the next refresh as a reservation that ended, never as an error on the screen.
  Future<void> _renewOwnClaim(dynamic robotId) async {
    if (_renewingClaim || accessBusy || apiClient == null) return;
    final claim = claimOf(robotId);
    if (!claimNeedsRenewal(claim, claimStandingOf(robotId), DateTime.now().millisecondsSinceEpoch)) return;
    _renewingClaim = true;
    try {
      await _authed((c) => commands.withRevision(robotId, 'claim', (ifMatch) => c.postClaim(robotId, ifMatch: ifMatch)));
      claims = await _authed((c) => c.getClaims());
      _logTelemetry('Reservation of robot $robotId renewed');
      notifyListeners();
    } catch (_) {
      // the next poll shows where the reservation stands
    } finally {
      _renewingClaim = false;
    }
  }

  /// Reserves the selected robot for this account on this installation.
  Future<void> claimSelectedRobot() =>
      _runAccessRequest('claim', (c, id) => commands.withRevision(id, 'claim', (ifMatch) => c.postClaim(id, ifMatch: ifMatch)));

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
        final answer = await commands.withRevision(id, 'release', (ifMatch) => c.postRelease(id, ifMatch: ifMatch));
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
      if (e is HydraApiException && e.isRevisionMismatch) unawaited(_refreshRobot(robotId));
      if (e is HydraApiException && e.isSessionProblem) _forceLogout();
    } finally {
      accessBusy = false;
    }
    notifyListeners();
    await refreshAccess();
  }

  // The audit record (contract v2, block 4), for administrators.
  AuditRead? auditRead;

  /// The chain check of the lines in [auditRead] (only after the operator asked to verify); null before.
  ChainCheck? auditChain;
  bool auditBusy = false;
  AuditFailure? auditFailure;

  /// Reads the audit record (administrators only): the newest lines for a filter, and with [verify] the server
  /// checks the whole record while this app checks the chain of the lines it was given. Never raises an error on
  /// the screen: the reason is left in [auditFailure].
  Future<void> refreshAudit({bool verify = false, String? type, dynamic robotId, int limit = 100}) async {
    if (apiClient == null) {
      auditFailure = AuditFailure.network;
      notifyListeners();
      return;
    }
    auditBusy = true;
    notifyListeners();
    try {
      final body = await _authed((c) => c.getAuditBody(AuditRecord.query(limit: limit, type: type, robotId: robotId, verify: verify)));
      final read = AuditRecord.parse(body);
      auditRead = read;
      auditChain = verify ? AuditRecord.checkChain(read.lines) : null;
      auditFailure = null;
    } catch (e) {
      auditRead = null;
      auditChain = null;
      if (e is HydraApiException) {
        auditFailure = e.isSessionProblem
            ? AuditFailure.session
            : e.statusCode == 403
                ? AuditFailure.forbidden
                : e.isNotFound
                    ? AuditFailure.unavailable
                    : e.statusCode == null
                        ? AuditFailure.network
                        : AuditFailure.other;
        if (e.isSessionProblem) _forceLogout();
      } else {
        auditFailure = AuditFailure.network;
      }
    } finally {
      auditBusy = false;
    }
    notifyListeners();
  }

  /// The lines of the audit record as the server stores them (`.jsonl`), for sharing; null when they could not be read.
  Future<String?> exportAudit({String? type, dynamic robotId, int limit = 100}) async {
    if (apiClient == null) return null;
    try {
      return await _authed((c) => c.getAuditBody(AuditRecord.query(limit: limit, type: type, robotId: robotId, format: 'jsonl')));
    } catch (_) {
      return null;
    }
  }

  // ---- Bluetooth LE (experimental) ----
  // The state of a HYDRA-UMC device read over Bluetooth LE, as the Android app does. Tested against a fake link only.
  List<BleDevice> discoveredBleDevices = const [];
  bool isBleScanning = false;

  /// True when the list also holds devices that do not advertise the HYDRA service.
  bool bleShowAll = false;

  /// The last Bluetooth problem, for the sentence the screen shows; null when there is none.
  BleError? bleError;
  HydraBleClient? _bleClient;

  /// How long one scan lasts.
  static const Duration bleScanDuration = Duration(seconds: 5);

  void setBleShowAll(bool value) {
    bleShowAll = value;
    notifyListeners();
  }

  /// Looks for devices for [bleScanDuration]; a problem is left in [bleError], never raised on the screen.
  Future<void> scanBle() async {
    if (isBleScanning) return;
    bleError = null;
    discoveredBleDevices = const [];
    isBleScanning = true;
    notifyListeners();
    try {
      await _bleScanner.scan(
        timeout: bleScanDuration,
        showAll: bleShowAll,
        onFound: (device) {
          discoveredBleDevices = upsertBleDevice(discoveredBleDevices, device);
          notifyListeners();
        },
      );
      await Future<void>.delayed(bleScanDuration);
    } on BleException catch (e) {
      bleError = e.error;
    } catch (_) {
      bleError = const BleError(BleErrorKind.scanFailed);
    } finally {
      await _bleScanner.stop();
      isBleScanning = false;
    }
    notifyListeners();
  }

  /// Connects to a device over Bluetooth LE. Like the Android app it replaces the Wi-Fi link: the state comes from the
  /// device and this phone does not talk to the server meanwhile.
  void connectBle(BleDevice device) {
    if (isBleScanning) unawaited(_bleScanner.stop());
    isBleScanning = false;
    _ws?.disconnect();
    _bleClient?.disconnect();
    apiClient = null;
    lastError = null;
    bleError = null;
    connectionStatus = 'connecting';
    notifyListeners();
    _bleClient = HydraBleClient(
      connector: _bleConnector,
      deviceId: device.id,
      onStatus: (status) {
        connectionStatus = switch (status) {
          BleStatus.connecting => 'connecting',
          BleStatus.connected => 'connected',
          BleStatus.disconnected => 'disconnected',
        };
        notifyListeners();
      },
      onSettings: (payload) {
        try {
          final decoded = jsonDecode(payload);
          if (decoded is! Map<String, dynamic>) throw const FormatException('not an object');
          state = HydraState(decoded);
          isShowingCachedState = false;
          _ensureSelectedRobot();
        } catch (e) {
          bleError = const BleError(BleErrorKind.malformedFrame);
        }
        notifyListeners();
      },
      onError: (error) {
        bleError = error;
        notifyListeners();
      },
    )..connect();
  }

  void disconnectBle() {
    _bleClient?.disconnect();
    _bleClient = null;
  }

  // Who connects to the server (the list of clients and the latest sign-ins), for every signed-in account.
  List<ConnectionClient>? connectionClients;
  List<ConnectionEvent>? connectionEvents;
  bool connectionsBusy = false;
  ConnectionsFailure? connectionsFailure;

  /// How many lines of the history of sign-ins the screen asks for.
  static const int connectionEventsShown = 30;

  /// Reads the list of clients and the latest sign-ins; never raises an error on the screen: the reason is left in
  /// [connectionsFailure].
  Future<void> refreshConnections() async {
    if (apiClient == null) {
      connectionsFailure = ConnectionsFailure.network;
      notifyListeners();
      return;
    }
    connectionsBusy = true;
    notifyListeners();
    try {
      final clients = ConnectionHistory.parseClients(await _authed((c) => c.getConnectionClientsBody()));
      final events = ConnectionHistory.parseEvents(await _authed((c) => c.getConnectionEventsBody(connectionEventsShown)));
      connectionClients = clients;
      connectionEvents = events;
      connectionsFailure = null;
    } catch (e) {
      connectionClients = null;
      connectionEvents = null;
      if (e is HydraApiException) {
        connectionsFailure = e.isSessionProblem
            ? ConnectionsFailure.session
            : e.isNotFound
                ? ConnectionsFailure.unavailable
                : e.statusCode == null
                    ? ConnectionsFailure.network
                    : ConnectionsFailure.other;
        if (e.isSessionProblem) _forceLogout();
      } else {
        connectionsFailure = ConnectionsFailure.network;
      }
    } finally {
      connectionsBusy = false;
    }
    notifyListeners();
  }

  // The access options of the server (administrators only).
  ServerSecurityOptions? serverOptions;
  bool serverOptionsBusy = false;
  ServerOptionsFailure? serverOptionsFailure;
  bool serverOptionsSaved = false;

  ServerOptionsFailure _serverOptionsFailureOf(Object e) {
    if (e is! HydraApiException) return ServerOptionsFailure.network;
    if (e.isSessionProblem) return ServerOptionsFailure.session;
    if (e.statusCode == 403) return ServerOptionsFailure.forbidden;
    if (e.isNotFound) return ServerOptionsFailure.unavailable;
    if (e.statusCode == null) return ServerOptionsFailure.network;
    return ServerOptionsFailure.other;
  }

  /// Reads the access options of the server; the reason it could not is left in [serverOptionsFailure], never raised
  /// on the screen.
  Future<void> refreshServerOptions() async {
    if (apiClient == null) {
      serverOptionsFailure = ServerOptionsFailure.network;
      notifyListeners();
      return;
    }
    serverOptionsBusy = true;
    serverOptionsSaved = false;
    notifyListeners();
    try {
      final options = ServerSecurity.parse(await _authed((c) => c.getServerConfigBody()));
      serverOptions = options;
      serverOptionsFailure = options == null ? ServerOptionsFailure.other : null;
    } catch (e) {
      serverOptions = null;
      serverOptionsFailure = _serverOptionsFailureOf(e);
      if (e is HydraApiException && e.isSessionProblem) _forceLogout();
    } finally {
      serverOptionsBusy = false;
    }
    notifyListeners();
  }

  /// Saves what changed in [values] (the screen has already asked about every change that lowers the protection) and
  /// shows the options as the server now holds them.
  Future<void> saveServerOptions(ServerSecurityValues values) async {
    final current = serverOptions;
    if (apiClient == null || current == null) return;
    final body = ServerSecurity.patch(current, values);
    if (body == null) return;
    serverOptionsBusy = true;
    serverOptionsSaved = false;
    notifyListeners();
    try {
      final answer = await _authed((c) => c.putServerConfigBody(jsonEncode(body)));
      serverOptions = ServerSecurity.parse(answer) ?? current;
      serverOptionsFailure = null;
      serverOptionsSaved = true;
    } catch (e) {
      serverOptionsFailure = _serverOptionsFailureOf(e);
      if (e is HydraApiException && e.isSessionProblem) _forceLogout();
    } finally {
      serverOptionsBusy = false;
    }
    notifyListeners();
  }

  /// True while a jog should not be sent: the previous tick is still on the
  /// wire, or the robot is running a trajectory (the server's playback and a
  /// jog would both write the same setpoint).
  bool jogBlocked([dynamic robotId]) {
    final id = robotId ?? selectedRobotId;
    if (id == null) return true;
    if (commands.hasJogInFlight(id)) return true;
    final robot = state.robotById(id);
    if (robot == null) return true;
    return robot.isPlaying && !robot.isPaused;
  }

  /// One tick of a held jog button: up to three axes in one go, dropped as a
  /// whole while the previous tick is still on the wire.
  void jogXYZ(String target, int dx, int dy, int dz, double step) {
    if (jogBlocked()) return;
    final robot = selectedRobot;
    if (target == 'robot' && robot != null && robot.model == parol6ModelName) {
      // A Parol6 is jogged the way the studio does it: the combined move is resolved ONCE against the real kinematics
      // of the arm and every axis command carries the same joints, instead of the generic formula of the server.
      final x = robot.posAxis('x') + dx * step;
      final y = robot.posAxis('y') + dy * step;
      final z = robot.posAxis('z') + dz * step;
      final joints = parol6CartesianToJointsOrNull(
        x,
        y,
        z,
        robot.posAxis('a'),
        robot.posAxis('b'),
        robot.posAxis('c'),
      );
      if (joints == null) {
        // Out of reach: sending clamped joints next to a position that does not match them would store an incoherent
        // pose on the server, so the jog is refused instead.
        lastError = const HydraError(HydraErrorKind.jogOutOfReach);
        notifyListeners();
        return;
      }
      final jointsParam = {for (var i = 0; i < _jointNames.length; i++) _jointNames[i]: joints[i]};
      for (final (axis, amount, value) in [('x', dx * step, x), ('y', dy * step, y), ('z', dz * step, z)]) {
        if (amount == 0.0) continue;
        _sendAtomicCommand(
          'jog',
          params: {'axis': axis, 'amount': amount, 'target': target, 'joints': jointsParam},
          localMutate: (r) {
            r.setPosAxis(axis, value);
            for (var i = 0; i < _jointNames.length; i++) {
              r.setJoint(_jointNames[i], joints[i]);
            }
          },
        );
      }
      return;
    }
    if (dx != 0) jog(target, 'x', dx * step);
    if (dy != 0) jog(target, 'y', dy * step);
    if (dz != 0) jog('robot', 'z', dz * step);
  }

  static const List<String> _jointNames = ['j1', 'j2', 'j3', 'j4', 'j5', 'j6'];

  /// Rotates the base (J1) alone by one step in [direction] (+1 or -1). Pure joint space, so it needs no inverse
  /// kinematics and works for every model; the limits are the real ones of a Parol6 and a generic [-180, 180] for the
  /// others.
  void jogJ1(int direction, double step) {
    if (jogBlocked()) return;
    final robot = selectedRobot;
    if (robot == null) return;
    final (lo, hi) = robot.model == parol6ModelName ? parol6JointLimitsDeg['j1']! : (-180.0, 180.0);
    final current = robot.joint('j1');
    final next = (current + direction * step).clamp(lo, hi).toDouble();
    if (next == current) return; // already at a real limit: nothing is sent
    final jointsParam = {for (final name in _jointNames) name: name == 'j1' ? next : robot.joint(name)};
    // axis x with amount 0 changes nothing of the position: the desired state is the joints override.
    _sendAtomicCommand(
      'jog',
      params: {'axis': 'x', 'amount': 0.0, 'target': 'robot', 'joints': jointsParam},
      localMutate: (r) => r.setJoint('j1', next),
    );
  }

  void jog(String target, String axis, double amount) {
    if (target == 'xytable' && (axis == 'x' || axis == 'y')) {
      // One atomic "table" move relative to where the table is now: the server checks the whole move against the
      // limits of the model and applies all of it or none of it.
      final move = tableParams(axis == 'x' ? amount : 0.0, axis == 'y' ? amount : 0.0, 'relative');
      if (move == null) return;
      _sendAtomicCommand(
        'table',
        params: move,
        localMutate: (r) => r.setXyTableAxis(axis, (r.xyTablePos[axis] ?? 0.0) + amount),
      );
      return;
    }
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
    _sendAtomicCommand(RobotCommandContract.valve, params: {'index': index, 'state': newState}, localMutate: (r) => r.setValve(index, newState));
  }

  void togglePump(int index) {
    final r = selectedRobot;
    if (r == null) return;
    final newState = !((r.pumps[index] ?? false) as bool);
    _sendAtomicCommand(RobotCommandContract.pump, params: {'index': index, 'state': newState}, localMutate: (r) => r.setPump(index, newState));
  }

  /// Debounced (300 ms): the slider of the Control screen fires many times a second while dragged.
  /// Sets the jog step of the robot on the server, so every client that shows it uses the same one (the `jogStep` command).
  void setJogStep(double step) {
    if (!step.isFinite || step <= 0 || step > 1000) return;
    _sendAtomicCommand(
      'jogStep',
      params: {'value': step},
      debounce: const Duration(milliseconds: 300),
      localMutate: (r) => r.raw['jogStep'] = step,
    );
  }

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

  /// Switches the vision system of a robot from the Camera screen (the `vision` command). It takes the robot id because the
  /// camera being browsed is not necessarily the selected robot.
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
    _bleClient?.disconnect();
    if (isBleScanning) unawaited(_bleScanner.stop());
    _metricsTimer?.cancel();
    _stateCacheTimer?.cancel();
    _watchAlertTimer?.cancel();
    deadMan.dispose();
    surfaces.dispose();
    commands.cancelAllPending();
    metricsListenable.dispose();
    apiClient?.close();
    super.dispose();
  }
}
