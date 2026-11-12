// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - l10n/language_prefs.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Persists the language chosen in Settings across launches (shared_preferences). The language is resolved in this order: the saved
// choice, then the language of the system when it is one of the supported ones, then English.
// =============================================================================

import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_localizations.dart';

class LanguagePrefs {
  static const _keyLanguage = 'hydra_language';

  Future<void> saveLanguage(String? languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    if (languageCode == null) {
      await prefs.remove(_keyLanguage);
    } else {
      await prefs.setString(_keyLanguage, languageCode);
    }
  }

  /// Null means "no explicit override" - MaterialApp's own `locale` stays
  /// null too in that case, so Flutter resolves the OS locale itself
  /// against `supportedLocales` (falling back to English when the device
  /// locale isn't one of the 7 this app ships).
  Future<Locale?> loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_keyLanguage);
    if (code == null) return null;
    for (final locale in AppLocalizations.supportedLocales) {
      if (locale.languageCode == code) return locale;
    }
    return null;
  }
}
