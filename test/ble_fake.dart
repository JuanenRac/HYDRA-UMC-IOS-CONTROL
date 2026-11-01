// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/ble_fake.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// A fake Bluetooth link for the tests: a device that follows the contract,
// driven by hand, with the writes it received kept for inspection.
// =============================================================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:hydra_umc_control/network/ble_contract.dart';
import 'package:hydra_umc_control/network/ble_gatt.dart';
import 'package:hydra_umc_control/network/ble_gatt_fbp.dart';

class FakeLink implements BleGattLink {
  final BleGattEvents events;
  FakeLink(this.events);

  bool hasAck = true;
  BleContractLookup lookup = BleContractLookup.found;
  bool closed = false;
  final List<Uint8List> writes = [];
  bool refuseWrite = false;

  @override
  bool requestMtu(int mtu) => true;
  @override
  bool discoverServices() => true;
  @override
  BleContractLookup findContract() => lookup;
  @override
  bool enableStateNotifications() => true;
  @override
  bool hasAckCharacteristic() => hasAck;
  @override
  bool enableAckNotifications() => true;
  @override
  bool writeCommand(Uint8List frame) {
    if (refuseWrite) return false;
    writes.add(frame);
    return true;
  }

  @override
  void close() => closed = true;

  /// Walks the link up the way a healthy device does.
  void bringUp({int mtu = 64}) {
    events.onConnectionState(true, 0);
    events.onMtu(mtu, 0);
    events.onServicesDiscovered(0);
    events.onNotificationsEnabled(0);
    if (hasAck) events.onAckNotificationsEnabled(0);
  }

  /// A message the device notifies on the STATE characteristic, framed for [mtu].
  void notifyState(String json, {int mtu = 64}) {
    for (final f in BleFraming.encode(Uint8List.fromList(utf8.encode(json)), mtu)) {
      events.onStateFrame(f);
    }
  }

  void notifyAck(Map<String, dynamic> ack, {int mtu = 64}) {
    for (final f in BleFraming.encode(Uint8List.fromList(utf8.encode(jsonEncode(ack))), mtu)) {
      events.onAckFrame(f);
    }
  }

  /// The command message the app wrote, put back together.
  Map<String, dynamic>? lastCommand() {
    final r = BleReassembler();
    BleReassembly? out;
    for (final w in writes) {
      out = r.push(w);
    }
    return out is BleMessage ? jsonDecode(utf8.decode(out.bytes)) as Map<String, dynamic> : null;
  }
}

class FakeConnector implements BleGattConnector {
  final List<FakeLink> links = [];
  BleException? failWith;
  @override
  BleGattLink open(String deviceId, BleGattEvents events) {
    if (failWith != null) throw failWith!;
    final link = FakeLink(events);
    links.add(link);
    return link;
  }
}

class FakeScanner implements BleScanner {
  List<BleDevice> devices = const [];
  BleException? failWith;
  bool lastShowAll = false;
  @override
  Future<void> scan({required Duration timeout, required bool showAll, required void Function(BleDevice) onFound}) async {
    lastShowAll = showAll;
    if (failWith != null) throw failWith!;
    devices.forEach(onFound);
  }

  @override
  Future<void> stop() async {}
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 5));
