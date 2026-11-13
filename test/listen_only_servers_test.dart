// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/listen_only_servers_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
// =============================================================================
// Listen only for one server: the list is empty by default, it applies to the server in use alone, a damaged list is cleaned, and the choice is kept.
import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_umc_control/network/client_prefs.dart';
import 'package:hydra_umc_control/network/listen_only_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('a server is named by its host and port', () {
    expect(ListenOnlyGate.serverKey('10.0.0.5', 3000), '10.0.0.5:3000');
  });

  test('nothing is read-only by default', () {
    expect(ListenOnlyGate.effective(false, <String>{}, '10.0.0.5:3000'), isFalse);
    expect(ListenOnlyGate.effective(false, <String>{}, null), isFalse);
  });

  test('the listed server is read-only and another is not', () {
    final servers = {'10.0.0.5:3000'};
    expect(ListenOnlyGate.effective(false, servers, '10.0.0.5:3000'), isTrue);
    expect(ListenOnlyGate.effective(false, servers, '10.0.0.6:3000'), isFalse);
    expect(ListenOnlyGate.effective(false, servers, null), isFalse);
  });

  test('the general switch covers every server', () {
    expect(ListenOnlyGate.effective(true, <String>{}, '10.0.0.6:3000'), isTrue);
    expect(ListenOnlyGate.effective(true, <String>{}, null), isTrue);
  });

  test('a stored list is cleaned and bounded', () {
    final stored = ['ok:1', '', ' x', 'y' * 201, 'ok:1', for (var i = 0; i < 80; i++) 'h$i:1'];
    final clean = ListenOnlyGate.cleanServers(stored);
    expect(clean, contains('ok:1'));
    expect(clean, isNot(contains('')));
    expect(clean, isNot(contains(' x')));
    expect(clean.length, lessThanOrEqualTo(ListenOnlyGate.maxServers));
    expect(clean.every((s) => s.length <= 200 && s.trim() == s), isTrue);
  });

  test('the stop and the disable still go out to a read-only server', () {
    expect(ListenOnlyGate.allows('POST', '/api/robot/1/command', '{"command":"stop"}'), isTrue);
    expect(ListenOnlyGate.allows('POST', '/api/robot/1/command', '{"command":"disable"}'), isTrue);
    expect(ListenOnlyGate.allows('POST', '/api/robot/1/command', '{"command":"jog"}'), isFalse);
  });

  test('the list is kept and read back, off by default', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = ClientPrefs();
    expect(await prefs.loadListenOnlyServers(), isEmpty);
    await prefs.saveListenOnlyServers({'a:1', 'b:2'});
    expect(await prefs.loadListenOnlyServers(), {'a:1', 'b:2'});
    await prefs.saveListenOnlyServers(<String>{});
    expect(await prefs.loadListenOnlyServers(), isEmpty);
  });
}
