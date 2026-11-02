// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - network/native_bridges.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The Dart side of the native halves that reach out of the app: local notifications, speech recognition, the Live
// Activity and the Apple Watch. Each one is an interface (the tests plug their own) and a MethodChannel
// implementation; on a system that does not answer (a test, a desktop, an iPhone without the feature) every call ends
// in the harmless answer: no permission, nothing shown. The Swift halves are in ios/Runner (AlertsBridge.swift,
// SpeechBridge.swift, LiveActivityBridge.swift, WatchBridge.swift). Nothing here sends a command to a robot.
// =============================================================================

import 'dart:async';

import 'package:flutter/services.dart';

Future<T?> _call<T>(MethodChannel channel, String method, [Object? arguments]) async {
  try {
    return await channel.invokeMethod<T>(method, arguments);
  } on MissingPluginException {
    return null; // not running on iOS (tests, desktop)
  } on PlatformException {
    return null;
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Local notifications
// ---------------------------------------------------------------------------------------------------------------------

abstract class AlertsBridge {
  /// Asks the person for permission to show notifications; false when they said no.
  Future<bool> requestPermission();

  /// Shows one notification. [id] replaces a notification with the same id.
  Future<void> show({required String id, required String title, required String body});
}

class MethodChannelAlertsBridge implements AlertsBridge {
  static const MethodChannel _channel = MethodChannel('hydra_umc/alerts');

  @override
  Future<bool> requestPermission() async => await _call<bool>(_channel, 'requestPermission') ?? false;

  @override
  Future<void> show({required String id, required String title, required String body}) async {
    await _call<void>(_channel, 'show', {'id': id, 'title': title, 'body': body});
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Speech recognition
// ---------------------------------------------------------------------------------------------------------------------

enum SpeechStatus {
  /// The person spoke and [SpeechOutcome.text] holds what was understood.
  ok,

  /// The person refused the microphone or the speech recognition permission.
  denied,

  /// The system has no recognizer for this language, or it is not available now.
  unavailable,

  /// Recognition on the device alone was asked for and this language needs the online one of Apple.
  needsOnline,

  /// Nothing was understood before the time ran out.
  empty,

  /// Anything else that went wrong.
  failed,
}

class SpeechOutcome {
  final SpeechStatus status;
  final String text;
  const SpeechOutcome(this.status, [this.text = '']);
}

abstract class SpeechBridge {
  /// Listens once and returns what was understood. [onDeviceOnly]: the audio never leaves the phone; when the language
  /// has no on-device recognizer the answer is [SpeechStatus.needsOnline] and nothing is listened to.
  Future<SpeechOutcome> listen({required String languageTag, required bool onDeviceOnly, required int timeoutMs});

  /// Stops listening; a pending [listen] ends with what it has.
  Future<void> cancel();
}

class MethodChannelSpeechBridge implements SpeechBridge {
  static const MethodChannel _channel = MethodChannel('hydra_umc/speech');

  @override
  Future<SpeechOutcome> listen({required String languageTag, required bool onDeviceOnly, required int timeoutMs}) async {
    final raw = await _call<Map<Object?, Object?>>(
      _channel,
      'listen',
      {'language': languageTag, 'onDeviceOnly': onDeviceOnly, 'timeoutMs': timeoutMs},
    );
    if (raw == null) return const SpeechOutcome(SpeechStatus.unavailable);
    final name = raw['status'];
    final status = SpeechStatus.values.firstWhere((s) => s.name == name, orElse: () => SpeechStatus.failed);
    final text = raw['text'];
    return SpeechOutcome(status, text is String ? text : '');
  }

  @override
  Future<void> cancel() async {
    await _call<void>(_channel, 'cancel');
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Live Activity
// ---------------------------------------------------------------------------------------------------------------------

abstract class LiveActivityBridge {
  /// True when the phone can show a Live Activity and the person did not turn them off in the settings of the system.
  Future<bool> isAvailable();

  Future<bool> start(Map<String, Object> content);
  Future<void> update(Map<String, Object> content);

  /// Ends the activity; the system keeps its last content on the lock screen for [dismissAfterSeconds].
  Future<void> end(Map<String, Object> content, {int dismissAfterSeconds = 0});
}

class MethodChannelLiveActivityBridge implements LiveActivityBridge {
  static const MethodChannel _channel = MethodChannel('hydra_umc/live_activity');

  @override
  Future<bool> isAvailable() async => await _call<bool>(_channel, 'isAvailable') ?? false;

  @override
  Future<bool> start(Map<String, Object> content) async => await _call<bool>(_channel, 'start', content) ?? false;

  @override
  Future<void> update(Map<String, Object> content) async {
    await _call<void>(_channel, 'update', content);
  }

  @override
  Future<void> end(Map<String, Object> content, {int dismissAfterSeconds = 0}) async {
    await _call<void>(_channel, 'end', {...content, 'dismissAfterSeconds': dismissAfterSeconds});
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Apple Watch
// ---------------------------------------------------------------------------------------------------------------------

abstract class WatchBridge {
  /// True when a watch is paired and has the app installed.
  Future<bool> isReachable();

  /// Hands the status to the watch (the system delivers the latest one when the watch wakes).
  Future<void> sendStatus(Map<String, Object> status);

  /// The watch asked for the global stop; [requestedAt] is when the person pressed it. [onStop] answers whether the request
  /// was accepted (the option is on and the request is fresh); the answer goes back to the watch.
  void listenForStop(bool Function(DateTime requestedAt) onStop);

  /// Pushes an alert (see util/watch_alerts.dart) to the watch as a message. A message is not stored: when the watch is not
  /// reachable it is simply not delivered (false), and nothing is queued for later, because an old alert on the wrist is
  /// worse than none.
  Future<bool> sendAlert(Map<String, Object> alert);

  /// The watch passes the presence of the operator and the second tap of a spoken order to the phone, which passes them on to
  /// the server only behind their own switches (both off). [onVoiceConfirm] returns the assistant reply for the watch.
  void listenForRelays({
    required Future<void> Function(Map<dynamic, dynamic> heartbeat) onPresence,
    required Future<Map<String, Object?>?> Function(Map<dynamic, dynamic> confirm) onVoiceConfirm,
  });
}

class MethodChannelWatchBridge implements WatchBridge {
  static const MethodChannel _channel = MethodChannel('hydra_umc/watch');
  bool Function(DateTime requestedAt)? _onStop;
  Future<void> Function(Map<dynamic, dynamic> heartbeat)? _onPresence;
  Future<Map<String, Object?>?> Function(Map<dynamic, dynamic> confirm)? _onVoiceConfirm;
  bool _listening = false;

  void _listen() {
    if (_listening) return;
    _listening = true;
    try {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'stopRequested') {
          final at = call.arguments is num
              ? DateTime.fromMillisecondsSinceEpoch((call.arguments as num).toInt())
              : DateTime.now();
          return _onStop?.call(at) ?? false;
        }
        if (call.method == 'presence' && call.arguments is Map) {
          await _onPresence?.call(call.arguments as Map<dynamic, dynamic>);
          return null;
        }
        if (call.method == 'voiceConfirm' && call.arguments is Map) {
          return _onVoiceConfirm?.call(call.arguments as Map<dynamic, dynamic>);
        }
        return null;
      });
    } catch (_) {
      _listening = false; // no bindings (a test): there is no watch to talk to
    }
  }

  @override
  Future<bool> isReachable() async {
    _listen();
    return await _call<bool>(_channel, 'isReachable') ?? false;
  }

  @override
  Future<void> sendStatus(Map<String, Object> status) async {
    _listen();
    await _call<void>(_channel, 'sendStatus', status);
  }

  @override
  void listenForStop(bool Function(DateTime requestedAt) onStop) {
    _onStop = onStop;
    _listen();
  }
  @override
  Future<bool> sendAlert(Map<String, Object> alert) async {
    _listen();
    return await _call<bool>(_channel, 'sendAlert', alert) ?? false;
  }

  @override
  void listenForRelays({
    required Future<void> Function(Map<dynamic, dynamic> heartbeat) onPresence,
    required Future<Map<String, Object?>?> Function(Map<dynamic, dynamic> confirm) onVoiceConfirm,
  }) {
    _onPresence = onPresence;
    _onVoiceConfirm = onVoiceConfirm;
    _listen();
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Pairing links
// ---------------------------------------------------------------------------------------------------------------------

/// Receives the pairing link (hydra-umc://pair?...) that the camera of the phone opened with this app. The link is only
/// handed over as text; whether it is read at all (the switch is off by default) and what it says is up to the Dart side.
abstract class PairingBridge {
  /// The link that opened the app and was not taken yet, or null.
  Future<String?> takePending();

  /// [onLink] runs for every link that arrives while the app is open.
  void listen(void Function(String link) onLink);
}

class MethodChannelPairingBridge implements PairingBridge {
  static const MethodChannel _channel = MethodChannel('hydra_umc/pairing');
  void Function(String link)? _onLink;
  bool _listening = false;

  void _listen() {
    if (_listening) return;
    _listening = true;
    try {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'pairingLink' && call.arguments is String) _onLink?.call(call.arguments as String);
        return null;
      });
    } catch (_) {
      _listening = false; // no bindings (a test)
    }
  }

  @override
  Future<String?> takePending() async {
    _listen();
    try {
      return await _call<String>(_channel, 'takePending');
    } catch (_) {
      return null; // no bindings yet (a test, a desktop build): there is no link waiting
    }
  }

  @override
  void listen(void Function(String link) onLink) {
    _onLink = onLink;
    _listen();
  }
}
