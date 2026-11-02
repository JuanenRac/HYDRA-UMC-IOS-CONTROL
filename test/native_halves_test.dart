// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/native_halves_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The Swift halves cannot be built here (no Xcode), so this reads them as text and holds them to the Dart side:
//   - every channel of lib/network/native_bridges.dart has its Swift half, registered in AppDelegate and in the project;
//   - the statuses the Dart side sends are the ones the Live Activity and the watch know, in the eight languages;
//   - the texts of the Live Activity and of the watch are filled in, in the eight languages, with the same placeholders;
//   - the permission texts and the Live Activity switch are in Info.plist;
//   - what is not built yet (the widget extension and the watch app) is not in the project.
// =============================================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:hydra_umc_control/util/live_activity_model.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  final dart = _read('lib/network/native_bridges.dart');
  final delegate = _read('ios/Runner/AppDelegate.swift');
  final project = _read('ios/Runner.xcodeproj/project.pbxproj');

  const halves = {
    'hydra_umc/alerts': 'AlertsBridge.swift',
    'hydra_umc/speech': 'SpeechBridge.swift',
    'hydra_umc/live_activity': 'LiveActivityBridge.swift',
    'hydra_umc/watch': 'WatchBridge.swift',
  };

  for (final entry in halves.entries) {
    test('${entry.key} has its Swift half, registered and part of the project', () {
      expect(dart, contains("MethodChannel('${entry.key}')"));
      final swift = _read('ios/Runner/${entry.value}');
      expect(swift, contains('"${entry.key}"'));
      expect(project, contains('${entry.value} in Sources'));
      final registrar = RegExp(r'(\w+Channel)\.register\(messenger: messenger\)').allMatches(delegate).map((m) => m.group(1)).toSet();
      final declared = RegExp(r'final class (\w+Channel)').firstMatch(swift)!.group(1);
      expect(registrar, contains(declared));
    });
  }

  test('every method the Dart side calls is handled by the Swift half', () {
    const methods = {
      'AlertsBridge.swift': ['requestPermission', 'show'],
      'SpeechBridge.swift': ['listen', 'cancel'],
      'LiveActivityBridge.swift': ['isAvailable', 'start', 'update', 'end'],
      'WatchBridge.swift': ['isReachable', 'sendStatus', 'stopRequested'],
    };
    for (final entry in methods.entries) {
      final swift = _read('ios/Runner/${entry.key}');
      for (final method in entry.value) {
        expect(swift, contains('"$method"'), reason: '${entry.key} $method');
      }
    }
  });

  test('the speech outcome names of the Dart side are the ones the Swift half answers', () {
    final swift = _read('ios/Runner/SpeechBridge.swift');
    for (final status in ['ok', 'denied', 'unavailable', 'needsOnline', 'empty', 'failed']) {
      expect(swift, contains('"$status"'), reason: status);
    }
  });

  test('the Live Activity shares the attributes with the Runner and knows every status', () {
    final attributes = _read('ios/Runner/HydraJobAttributes.swift');
    expect(project, contains('HydraJobAttributes.swift in Sources'));
    for (final field in ['robotName', 'status', 'step', 'total']) {
      expect(attributes, contains('var $field'));
    }
    final widget = _read('ios/HydraLiveActivity/HydraLiveActivity.swift');
    for (final status in SurfaceStatus.values) {
      final key = 'status.${status.name}';
      for (final language in _languages) {
        expect(_strings(language), contains(key), reason: '$language $key');
      }
    }
    expect(widget, contains('HydraJobAttributes'));
    expect(widget, isNot(contains('Button')), reason: 'a Live Activity only shows a status');
  });

  test('the watch app asks the phone for the stop and holds no session of its own', () {
    final watch = _read('ios/HydraWatch/HydraWatchApp.swift');
    expect(watch, contains('stopRequestedAt'));
    expect(watch, isNot(contains('URLSession')));
    expect(watch, isNot(contains('Authorization')));
    expect(_read('ios/Runner/WatchBridge.swift'), contains('stopRequestedAt'));
  });

  test('the extension targets are not in the project yet, and the files that wait for them exist', () {
    expect(project, isNot(contains('HydraLiveActivity')));
    expect(project, isNot(contains('HydraWatch')));
    for (final file in ['ios/HydraLiveActivity/HydraLiveActivity.swift', 'ios/HydraWatch/HydraWatchApp.swift', 'ios/HydraWatch/ContentView.swift']) {
      expect(File(file).existsSync(), isTrue, reason: file);
    }
  });

  for (final language in _languages) {
    test('$language: the texts of the Live Activity and the watch are filled in with the placeholders of English', () {
      final own = _strings(language);
      final english = _strings('en');
      expect(own.keys.toSet(), english.keys.toSet());
      final placeholder = RegExp(r'%\d\$d');
      for (final key in english.keys) {
        expect(own[key]!.trim(), isNotEmpty, reason: key);
        expect(placeholder.allMatches(own[key]!).map((m) => m.group(0)).toList()..sort(),
            placeholder.allMatches(english[key]!).map((m) => m.group(0)).toList()..sort(), reason: '$language $key');
      }
      if (language != 'en') {
        expect(own['status.running'], isNot(english['status.running']));
        expect(own['watch.waiting'], isNot(english['watch.waiting']));
      }
    });
  }

  test('Info.plist asks for the microphone and speech texts and allows the Live Activity', () {
    final plist = _read('ios/Runner/Info.plist');
    for (final key in ['NSMicrophoneUsageDescription', 'NSSpeechRecognitionUsageDescription', 'NSSupportsLiveActivities']) {
      expect(plist, contains('<key>$key</key>'));
    }
  });
}

const _languages = ['en', 'es', 'de', 'fr', 'it', 'ja', 'zh-Hans', 'pt-PT'];

Map<String, String> _strings(String language) {
  final text = _read('ios/HydraExtensions/$language.lproj/Localizable.strings');
  return {for (final m in RegExp(r'^"([^"]+)" = "(.*)";$', multiLine: true).allMatches(text)) m.group(1)!: m.group(2)!};
}
