// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - network/ble_gatt_fbp.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The real Bluetooth link: ble_gatt.dart over the flutter_blue_plus package
// (1.x, BSD-3-Clause). The platform answers asynchronously; each answer is
// turned into the matching event of [BleGattEvents]. EXPERIMENTAL: compiled and
// built in CI, but never run against a real HYDRA-UMC device.
// =============================================================================

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_contract.dart';
import 'ble_gatt.dart';

/// A device found while scanning. On iOS the id is a UUID made by the system, not a hardware address.
class BleDevice {
  final String? name;
  final String id;
  final int rssi;
  const BleDevice(this.name, this.id, this.rssi);
}

/// The list the Bluetooth section shows: adds a device or refreshes the entry with the same id (signal, and the name
/// once it is known); strongest first.
List<BleDevice> upsertBleDevice(List<BleDevice> current, BleDevice found) {
  final previous = current.where((d) => d.id == found.id).firstOrNull;
  final merged = BleDevice(found.name ?? previous?.name, found.id, found.rssi);
  return [...current.where((d) => d.id != found.id), merged]..sort((a, b) => b.rssi.compareTo(a.rssi));
}

/// Looks for devices; the real one uses flutter_blue_plus, a test plugs in its own.
abstract class BleScanner {
  /// Scans for [timeout], calling [onFound] for each advertisement. Only devices advertising the HYDRA service unless
  /// [showAll]. Throws a [BleException] when the scan cannot start.
  Future<void> scan({required Duration timeout, required bool showAll, required void Function(BleDevice) onFound});

  Future<void> stop();
}

class FbpBleScanner implements BleScanner {
  StreamSubscription<List<ScanResult>>? _sub;

  @override
  Future<void> scan({required Duration timeout, required bool showAll, required void Function(BleDevice) onFound}) async {
    if (!await FlutterBluePlus.isSupported) throw const BleException(BleError(BleErrorKind.bluetoothUnavailable));
    final state = await FlutterBluePlus.adapterState.first;
    if (state == BluetoothAdapterState.unauthorized) throw const BleException(BleError(BleErrorKind.permissionDenied));
    if (state != BluetoothAdapterState.on) throw const BleException(BleError(BleErrorKind.bluetoothOff));
    await _sub?.cancel();
    _sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name = r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.platformName;
        onFound(BleDevice(name.isEmpty ? null : name, r.device.remoteId.str, r.rssi));
      }
    });
    try {
      await FlutterBluePlus.startScan(
        withServices: showAll ? const [] : [Guid(BleContract.serviceUuid)],
        timeout: timeout,
      );
    } catch (e) {
      await _sub?.cancel();
      _sub = null;
      throw const BleException(BleError(BleErrorKind.scanFailed));
    }
  }

  @override
  Future<void> stop() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {
      // The scan may already be over.
    }
    await _sub?.cancel();
    _sub = null;
  }
}

class FbpBleGattConnector implements BleGattConnector {
  const FbpBleGattConnector();

  @override
  BleGattLink open(String deviceId, BleGattEvents events) {
    if (deviceId.isEmpty) throw const BleException(BleError(BleErrorKind.invalidAddress));
    final state = FlutterBluePlus.adapterStateNow;
    if (state == BluetoothAdapterState.unauthorized) throw const BleException(BleError(BleErrorKind.permissionDenied));
    if (state != BluetoothAdapterState.on) throw const BleException(BleError(BleErrorKind.bluetoothOff));
    return _FbpLink(BluetoothDevice.fromId(deviceId), events)..start();
  }
}

class _FbpLink implements BleGattLink {
  final BluetoothDevice _device;
  final BleGattEvents _events;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _stateSub;
  StreamSubscription<List<int>>? _ackSub;
  BluetoothCharacteristic? _state;
  BluetoothCharacteristic? _command;
  BluetoothCharacteristic? _ack;
  bool _closed = false;

  _FbpLink(this._device, this._events);

  void start() {
    _connSub = _device.connectionState.listen((s) {
      if (_closed) return;
      if (s == BluetoothConnectionState.disconnected) _events.onConnectionState(false, 0);
    });
    // The MTU is negotiated by the system on iOS; it is read once connected.
    _device.connect(mtu: null).then((_) {
      if (!_closed) _events.onConnectionState(true, 0);
    }).catchError((Object e) {
      if (!_closed) _events.onConnectionState(false, 1);
    });
  }

  @override
  bool requestMtu(int mtu) {
    if (_closed) return false;
    Future<void>(() async {
      try {
        // Android lets the app ask; iOS does not, and reports what the system granted.
        final granted = _device.mtuNow;
        _events.onMtu(granted, 0);
      } catch (_) {
        _events.onMtu(BleContract.defaultMtu, 1);
      }
    });
    return true;
  }

  @override
  bool discoverServices() {
    if (_closed) return false;
    _device.discoverServices().then((services) {
      if (_closed) return;
      for (final s in services) {
        if (s.uuid != Guid(BleContract.serviceUuid)) continue;
        for (final c in s.characteristics) {
          if (c.uuid == Guid(BleContract.stateCharUuid)) _state = c;
          if (c.uuid == Guid(BleContract.commandCharUuid)) _command = c;
          if (c.uuid == Guid(BleContract.ackCharUuid)) _ack = c;
        }
      }
      _events.onServicesDiscovered(0);
    }).catchError((Object e) {
      if (!_closed) _events.onServicesDiscovered(1);
    });
    return true;
  }

  @override
  BleContractLookup findContract() {
    final services = _device.servicesList;
    final has = services.any((s) => s.uuid == Guid(BleContract.serviceUuid));
    if (!has) return BleContractLookup.noService;
    final stateOk = _state != null && (_state!.properties.notify || _state!.properties.indicate);
    final commandOk = _command != null;
    return stateOk && commandOk ? BleContractLookup.found : BleContractLookup.characteristicMissing;
  }

  @override
  bool enableStateNotifications() {
    final c = _state;
    if (c == null || _closed) return false;
    _stateSub = c.onValueReceived.listen((v) => _events.onStateFrame(Uint8List.fromList(v)));
    c.setNotifyValue(true).then((ok) {
      if (!_closed) _events.onNotificationsEnabled(ok ? 0 : 1);
    }).catchError((Object e) {
      if (!_closed) _events.onNotificationsEnabled(1);
    });
    return true;
  }

  @override
  bool hasAckCharacteristic() => _ack != null;

  @override
  bool enableAckNotifications() {
    final c = _ack;
    if (c == null || _closed) return false;
    _ackSub = c.onValueReceived.listen((v) => _events.onAckFrame(Uint8List.fromList(v)));
    c.setNotifyValue(true).then((ok) {
      if (!_closed) _events.onAckNotificationsEnabled(ok ? 0 : 1);
    }).catchError((Object e) {
      if (!_closed) _events.onAckNotificationsEnabled(1);
    });
    return true;
  }

  @override
  bool writeCommand(Uint8List frame) {
    final c = _command;
    if (c == null || _closed) return false;
    c.write(frame, withoutResponse: false).then((_) {
      if (!_closed) _events.onWriteDone(0);
    }).catchError((Object e) {
      if (!_closed) _events.onWriteDone(1);
    });
    return true;
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _connSub?.cancel();
    _stateSub?.cancel();
    _ackSub?.cancel();
    _device.disconnect().catchError((Object e) {});
  }
}
