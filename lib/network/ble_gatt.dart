// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - network/ble_gatt.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// A GATT abstraction so the BLE logic runs without a phone: the client talks to
// these interfaces, the app plugs in the real link (ble_gatt_fbp.dart) and the
// tests plug in a fake one.
// =============================================================================

import 'dart:typed_data';

import 'ble_contract.dart';

/// What the contract lookup found on a discovered device.
enum BleContractLookup { found, noService, characteristicMissing }

/// Events of one GATT link, in the order the platform delivers them.
abstract class BleGattEvents {
  void onConnectionState(bool connected, int status);
  void onMtu(int mtu, int status);
  void onServicesDiscovered(int status);
  void onNotificationsEnabled(int status);

  /// Outcome of turning on the notifications of the ACK characteristic.
  void onAckNotificationsEnabled(int status);

  /// One frame notified on the STATE characteristic.
  void onStateFrame(Uint8List frame);

  /// One frame notified on the ACK characteristic.
  void onAckFrame(Uint8List frame);

  /// Outcome of the last COMMAND write.
  void onWriteDone(int status);
}

/// One GATT client. Each method returns false when the platform refused to start the operation.
abstract class BleGattLink {
  bool requestMtu(int mtu);
  bool discoverServices();
  BleContractLookup findContract();
  bool enableStateNotifications();

  /// Whether the device has the optional ACK characteristic (it can take commands).
  bool hasAckCharacteristic();
  bool enableAckNotifications();
  bool writeCommand(Uint8List frame);

  /// Disconnects and releases the GATT client. Safe to call twice.
  void close();
}

/// Opens links.
abstract class BleGattConnector {
  /// Throws a [BleException] when the link cannot be started (no adapter, Bluetooth off, no permission, bad id).
  BleGattLink open(String deviceId, BleGattEvents events);
}
