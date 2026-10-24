import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The permission prompts of iOS (local network, Face ID) are read from InfoPlist.strings of the language of the
// device; without one per language the prompt would be in English whatever the app offers.
void main() {
  final plist = File('ios/Runner/Info.plist').readAsStringSync();
  final project = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
  final listed = RegExp(r'<key>CFBundleLocalizations</key>\s*<array>([\s\S]*?)</array>')
      .firstMatch(plist)!
      .group(1)!;
  final languages = RegExp(r'<string>([^<]+)</string>').allMatches(listed).map((m) => m.group(1)!).toList();

  test('the app declares the eight languages', () {
    expect(languages.toSet(), {'en', 'es', 'de', 'fr', 'it', 'ja', 'zh-Hans', 'pt-PT'});
  });

  for (final language in languages) {
    test('$language has both permission texts, filled in, and is part of the project', () {
      final file = File('ios/Runner/$language.lproj/InfoPlist.strings');
      expect(file.existsSync(), isTrue, reason: 'ios/Runner/$language.lproj/InfoPlist.strings');
      final text = file.readAsStringSync();
      for (final key in ['NSLocalNetworkUsageDescription', 'NSFaceIDUsageDescription']) {
        final match = RegExp('"$key" = "(.+)";').firstMatch(text);
        expect(match, isNotNull, reason: key);
        expect(match!.group(1)!.trim(), isNotEmpty);
      }
      expect(project.contains('path = $language.lproj/InfoPlist.strings'), isTrue);
      expect(project.contains(language.contains('-') ? '"$language",' : '$language,'), isTrue, reason: 'knownRegions');
    });
  }

  test('the texts differ from English in every other language', () {
    final english = File('ios/Runner/en.lproj/InfoPlist.strings').readAsStringSync();
    for (final language in languages.where((l) => l != 'en')) {
      expect(File('ios/Runner/$language.lproj/InfoPlist.strings').readAsStringSync(), isNot(english), reason: language);
    }
  });
}
