// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - network/push_bridge.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The bridge to the push notifications of the system (APNs): asking the person
// for permission, registering the app with the system and receiving the device
// token. The native half lives in ios/Runner/AppDelegate.swift; this is its Dart
// side, behind an interface so the tests plug in their own.
// =============================================================================

import 'dart:async';

import 'package:flutter/services.dart';

abstract class PushBridge {
  /// Asks the person for permission to show notifications and, when granted, registers the app with the system.
  /// False when the person said no.
  Future<bool> requestPermission();

  /// The device token (hexadecimal) once the system has given one, waiting up to [timeout]; null when it never came.
  Future<String?> deviceToken({Duration timeout = const Duration(seconds: 10)});

  /// Tells the system the app no longer wants notifications.
  Future<void> unregister();
}

class MethodChannelPushBridge implements PushBridge {
  static const MethodChannel _channel = MethodChannel('hydra_umc/push');
  final StreamController<String> _tokens = StreamController<String>.broadcast();
  String? _last;

  bool _listening = false;

  // Listening starts on first use, not in the constructor: the channel needs the Flutter bindings, which a plain unit test
  // does not start.
  void _listen() {
    if (_listening) return;
    _listening = true;
    try {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'token' && call.arguments is String) {
          _last = call.arguments as String;
          _tokens.add(_last!);
        }
      });
    } catch (_) {
      _listening = false; // no bindings (a test): there is no system to talk to
    }
  }

  @override
  Future<bool> requestPermission() async {
    _listen();
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on MissingPluginException {
      return false; // not running on iOS (tests, desktop)
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> deviceToken({Duration timeout = const Duration(seconds: 10)}) async {
    _listen();
    try {
      final known = _last ?? await _channel.invokeMethod<String>('currentToken');
      if (known != null && known.isNotEmpty) return known;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
    try {
      return await _tokens.stream.first.timeout(timeout);
    } on TimeoutException {
      return null;
    }
  }

  @override
  Future<void> unregister() async {
    try {
      await _channel.invokeMethod<void>('unregister');
    } on MissingPluginException {
      // nothing to do outside iOS
    } on PlatformException {
      // the system will drop the registration by itself
    }
    _last = null;
  }
}
