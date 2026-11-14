// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/push_bridge_channel_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The Dart side of the push notifications of the system: asking for permission,
// the device token (already known, asked for, or waited for) and unregistering.
// The native half is replaced by a mock of the platform channel, and the token
// the system sends later is delivered the way the system does it.
// =============================================================================

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydra_umc_control/network/push_bridge.dart';

const MethodChannel _channel = MethodChannel('hydra_umc/push');

void _native(Future<Object?>? Function(MethodCall call)? handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, handler);
}

/// The system sends the device token to the app.
Future<void> _systemSends(Object? token) async {
  const codec = StandardMethodCodec();
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
    'hydra_umc/push',
    codec.encodeMethodCall(MethodCall('token', token)),
    (_) {},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => _native(null));

  group('permission', () {
    test('it is true only when the system says yes', () async {
      final bridge = MethodChannelPushBridge();
      for (final answer in <Object?>[true, false, null]) {
        _native((call) async => call.method == 'requestPermission' ? answer : null);
        expect(await bridge.requestPermission(), answer == true, reason: 'answer $answer');
      }
    });

    test('an error of the platform or no platform at all is a no', () async {
      final bridge = MethodChannelPushBridge();
      _native((call) async => throw PlatformException(code: 'denied'));
      expect(await bridge.requestPermission(), isFalse);
      _native((call) async => throw MissingPluginException());
      expect(await bridge.requestPermission(), isFalse);
      _native((call) async => throw StateError('anything else'));
      expect(await bridge.requestPermission(), isFalse);
      _native(null);
      expect(await bridge.requestPermission(), isFalse, reason: 'outside iOS nobody answers the channel');
    });
  });

  group('device token', () {
    test('a token the system already holds is returned without waiting', () async {
      final bridge = MethodChannelPushBridge();
      final asked = <String>[];
      _native((call) async {
        asked.add(call.method);
        return call.method == 'currentToken' ? 'ab12cd34' : null;
      });
      expect(await bridge.deviceToken(timeout: const Duration(milliseconds: 50)), 'ab12cd34');
      expect(asked, ['currentToken']);
    });

    test('a token that arrives later is waited for and then remembered', () async {
      final bridge = MethodChannelPushBridge();
      var asked = 0;
      _native((call) async {
        if (call.method == 'currentToken') {
          asked++;
          return ''; // the system has none yet
        }
        return null;
      });
      final waiting = bridge.deviceToken(timeout: const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await _systemSends('feed0001');
      expect(await waiting, 'feed0001');
      // Asking again does not ask the system again: the last token is known.
      expect(await bridge.deviceToken(timeout: const Duration(milliseconds: 50)), 'feed0001');
      expect(asked, 1);
    });

    test('a token that never comes is null after the wait', () async {
      final bridge = MethodChannelPushBridge();
      _native((call) async => null);
      expect(await bridge.deviceToken(timeout: const Duration(milliseconds: 50)), isNull);
    });

    test('with no platform behind the channel there is no token', () async {
      final bridge = MethodChannelPushBridge();
      _native((call) async => throw MissingPluginException());
      expect(await bridge.deviceToken(timeout: const Duration(milliseconds: 50)), isNull);
      _native((call) async => throw PlatformException(code: 'unavailable'));
      expect(await bridge.deviceToken(timeout: const Duration(milliseconds: 50)), isNull);
      _native((call) async => throw StateError('anything else'));
      expect(await bridge.deviceToken(timeout: const Duration(milliseconds: 50)), isNull);
    });

    test('a token that is not text is ignored', () async {
      final bridge = MethodChannelPushBridge();
      _native((call) async => call.method == 'requestPermission' ? true : null);
      expect(await bridge.requestPermission(), isTrue);
      await _systemSends(12345);
      await _systemSends(null);
      expect(await bridge.deviceToken(timeout: const Duration(milliseconds: 50)), isNull);
    });
  });

  group('unregister', () {
    test('it tells the system and forgets the token', () async {
      final bridge = MethodChannelPushBridge();
      final asked = <String>[];
      _native((call) async {
        asked.add(call.method);
        return null;
      });
      await bridge.requestPermission();
      await _systemSends('0badc0de');
      expect(await bridge.deviceToken(timeout: const Duration(milliseconds: 50)), '0badc0de');
      await bridge.unregister();
      expect(asked.last, 'unregister');
      // The old token is gone: the system is asked again and has none.
      asked.clear();
      expect(await bridge.deviceToken(timeout: const Duration(milliseconds: 50)), isNull);
      expect(asked, ['currentToken']);
    });

    test('a platform that fails or is missing does not stop it', () async {
      final bridge = MethodChannelPushBridge();
      _native((call) async => throw PlatformException(code: 'failed'));
      await bridge.unregister();
      _native((call) async => throw MissingPluginException());
      await bridge.unregister();
    });
  });
}
