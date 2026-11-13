// Parity of the eight language files.
//
// The eight ARB files must say the same things: the same keys, the same
// placeholders and no empty text. They are read from the files of the
// repository, so a change to one language only is caught here.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _languages = ['en', 'es', 'de', 'fr', 'it', 'ja', 'zh', 'pt'];

Map<String, dynamic> _arb(String code) {
  final text = File('lib/l10n/app_$code.arb').readAsStringSync();
  return json.decode(text) as Map<String, dynamic>;
}

Set<String> _keys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

Set<String> _placeholders(String text) =>
    RegExp(r'\{(\w+)').allMatches(text).map((m) => m.group(1)!).toSet();

void main() {
  final english = _arb('en');
  final englishKeys = _keys(english);

  test('There is one ARB file per language of the ecosystem', () {
    for (final code in _languages) {
      expect(File('lib/l10n/app_$code.arb').existsSync(), isTrue, reason: code);
    }
  });

  for (final code in _languages.where((c) => c != 'en')) {
    group('Language $code', () {
      final arb = _arb(code);

      test('has exactly the keys of the English file', () {
        final keys = _keys(arb);
        expect(englishKeys.difference(keys), isEmpty, reason: 'missing in $code');
        expect(keys.difference(englishKeys), isEmpty, reason: 'extra in $code');
      });

      test('has no empty text', () {
        for (final key in _keys(arb)) {
          final value = arb[key];
          expect(value, isA<String>(), reason: '$code/$key');
          expect((value as String).trim(), isNotEmpty, reason: '$code/$key');
        }
      });

      test('keeps the placeholders of the English text', () {
        for (final key in englishKeys) {
          final value = arb[key];
          if (value is! String) continue;
          expect(_placeholders(value), _placeholders(english[key] as String),
              reason: '$code/$key');
        }
      });

      test('declares its own locale', () {
        expect(arb['@@locale'], code);
      });
    });
  }
}
