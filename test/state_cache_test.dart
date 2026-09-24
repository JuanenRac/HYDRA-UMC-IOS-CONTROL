// Real save/load round-trip coverage for network/state_cache.dart, backed
// by shared_preferences' own mock store (no real disk I/O needed).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydra_umc_control/network/state_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('loadState returns null when nothing was ever saved', () async {
    final cache = StateCache();
    expect(await cache.loadState(), isNull);
  });

  test('saveState then loadState round-trips the exact same tree', () async {
    final cache = StateCache();
    final raw = {
      'activeControllerId': 'c1',
      'controllers': [
        {
          'id': 'c1',
          'robots': [
            {'id': 1, 'name': 'ARM-1', 'online': true},
          ],
        },
      ],
    };

    await cache.saveState(raw);
    final loaded = await cache.loadState();

    expect(loaded, raw);
  });

  test('a corrupt cached value is treated as no cache, not a crash', () async {
    SharedPreferences.setMockInitialValues({'hydra_last_state': 'not valid json{{{'});
    final cache = StateCache();
    expect(await cache.loadState(), isNull);
  });

  test('a cached JSON value that is not an object is treated as no cache', () async {
    SharedPreferences.setMockInitialValues({'hydra_last_state': '[1, 2, 3]'});
    final cache = StateCache();
    expect(await cache.loadState(), isNull);
  });

  // loadCachedState is the real fix - a plain "visual cache" with
  // no way to know its own age. These prove that link is real.
  group('loadCachedState', () {
    test('returns null when nothing was ever saved', () async {
      final cache = StateCache();
      expect(await cache.loadCachedState(), isNull);
    });

    test('records the real save instant alongside the cached tree', () async {
      final cache = StateCache();
      await cache.saveState({'activeControllerId': 'c1'});
      final after = DateTime.now();

      final cached = await cache.loadCachedState();
      expect(cached, isNotNull);
      expect(cached!.raw, {'activeControllerId': 'c1'});
      // Millisecond-truncated but genuinely "just now" - allow a small,
      // real clock-skew/rounding tolerance rather than an exact match.
      expect(after.difference(cached.savedAt).inSeconds, lessThan(5));
      expect(cached.savedAt.year, greaterThan(2000));
    });

    test('age() reports how long ago the state was saved, relative to a given "now"', () async {
      final cache = StateCache();
      await cache.saveState({'x': 1});
      final cached = await cache.loadCachedState();
      final laterNow = cached!.savedAt.add(const Duration(minutes: 5));
      expect(cached.age(now: laterNow), const Duration(minutes: 5));
    });

    test('age() never goes negative even if "now" is before the save instant', () async {
      final cache = StateCache();
      await cache.saveState({'x': 1});
      final cached = await cache.loadCachedState();
      final earlierNow = cached!.savedAt.subtract(const Duration(minutes: 1));
      expect(cached.age(now: earlierNow), Duration.zero);
    });

    test('a cache saved before the timestamp field existed reports the epoch, not "just now"', () async {
      // Simulates an in-place app update: hydra_last_state present (an
      // older build wrote it), hydra_last_state_saved_at_ms never set.
      SharedPreferences.setMockInitialValues({'hydra_last_state': jsonEncode({'x': 1})});
      final cache = StateCache();
      final cached = await cache.loadCachedState();
      expect(cached, isNotNull);
      expect(cached!.savedAt, DateTime.fromMillisecondsSinceEpoch(0));
      // An unknown-age cache must read as maximally stale, not fresh.
      expect(cached.age().inDays, greaterThan(365));
    });
  });
}
