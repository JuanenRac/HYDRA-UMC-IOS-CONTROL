// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/robot_view_model_ble_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The Bluetooth section of the view model against a fake scanner and a fake
// link: the list, the problems in their own words, the state read over the link.
// =============================================================================

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydra_umc_control/l10n/app_localizations.dart';
import 'package:hydra_umc_control/network/ble_contract.dart';
import 'package:hydra_umc_control/network/ble_gatt_fbp.dart';
import 'package:hydra_umc_control/state/robot_view_model.dart';
import 'package:hydra_umc_control/ui/widgets/ble_dialog.dart';

import 'ble_fake.dart';

void main() {
  late FakeScanner scanner;
  late FakeConnector connector;
  late RobotViewModel vm;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    scanner = FakeScanner();
    connector = FakeConnector();
    vm = RobotViewModel(bleScanner: scanner, bleConnector: connector);
  });
  tearDown(() => vm.dispose());

  test('a scan lists what it found, strongest first, and passes the show-all choice', () async {
    scanner.devices = const [BleDevice('Far', 'a', -90), BleDevice('Near', 'b', -40)];
    vm.setBleShowAll(true);
    await vm.scanBle();
    expect(vm.discoveredBleDevices.map((d) => d.id), ['b', 'a']);
    expect(scanner.lastShowAll, isTrue);
    expect(vm.isBleScanning, isFalse);
    expect(vm.bleError, isNull);
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('a scan that cannot start leaves the reason', () async {
    scanner.failWith = const BleException(BleError(BleErrorKind.permissionDenied));
    await vm.scanBle();
    expect(vm.bleError!.kind, BleErrorKind.permissionDenied);
    expect(vm.isBleScanning, isFalse);
  });

  test('the state read over the link replaces the state and the link drives the status', () async {
    vm.connectBle(const BleDevice('Robot', 'dev-1', -50));
    expect(vm.connectionStatus, 'connecting');
    final link = connector.links.single..bringUp();
    await settle();
    expect(vm.connectionStatus, 'connected');
    link.notifyState('{"activeControllerId":"c1","controllers":[{"id":"c1","robots":[{"id":7,"online":true}]}]}');
    await settle();
    expect(vm.robots.single.id, 7);
    link.notifyState('[1,2]');
    await settle();
    expect(vm.bleError!.kind, BleErrorKind.malformedFrame);
    vm.disconnectBle();
    expect(vm.connectionStatus, 'disconnected');
    expect(link.closed, isTrue);
  });

  test('every Bluetooth problem reads in every language', () async {
    for (final code in ['en', 'es', 'de', 'fr', 'it', 'ja', 'zh', 'pt']) {
      final l10n = await AppLocalizations.delegate.load(Locale(code));
      for (final kind in BleErrorKind.values) {
        final text = bleErrorText(l10n, BleError(kind, 133));
        expect(text.trim(), isNotEmpty, reason: '$kind $code');
        expect(text, contains('133'), reason: '$kind $code');
      }
    }
  });
}
