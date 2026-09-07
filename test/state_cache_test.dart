// Real save/load round-trip coverage for network/state_cache.dart, backed
// by shared_preferences' own mock store (no real disk I/O needed).

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
}
