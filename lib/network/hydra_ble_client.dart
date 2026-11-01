// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - network/hydra_ble_client.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Talks to one HYDRA-UMC device over the BLE contract (ble_contract.dart):
// connect, ask for a bigger MTU, discover and check the service, turn on state
// notifications, reassemble the notified state and write framed commands one at
// a time. A link that drops by itself is retried with a growing delay
// ([BleReconnectPolicy]); [disconnect] stops that. EXPERIMENTAL.
//
// All platform access goes through [connector], so the whole state machine runs
// in unit tests against a fake GATT.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'ble_commands.dart';
import 'ble_contract.dart';
import 'ble_gatt.dart';

enum BleStatus { connecting, connected, disconnected }

class _Pending {
  final void Function(BleCommandOutcome) onResult;
  Timer? timeout;
  _Pending(this.onResult);
}

class HydraBleClient {
  final BleGattConnector connector;
  final String deviceId;
  final void Function(BleStatus) onStatus;
  final void Function(String) onSettings;
  final void Function(BleError) onError;
  final BleReconnectPolicy reconnectPolicy;
  final int preferredMtu;
  final Duration ackTimeout;

  HydraBleClient({
    required this.connector,
    required this.deviceId,
    required this.onStatus,
    required this.onSettings,
    this.onError = _ignoreError,
    this.reconnectPolicy = const BleReconnectPolicy(),
    this.preferredMtu = BleContract.preferredMtu,
    this.ackTimeout = BleCommands.defaultAckTimeout,
  });

  static void _ignoreError(BleError _) {}

  BleGattLink? _link;

  /// Changes with every link: events of an older link are dropped.
  int _generation = 0;
  bool _userClosed = true;
  bool _ready = false;
  int _mtu = BleContract.defaultMtu;
  int _attempts = 0;
  Timer? _reconnect;
  final BleReassembler _reassembler = BleReassembler();
  final BleReassembler _ackReassembler = BleReassembler();
  bool _ackReady = false;
  int _commandCounter = 0;
  final Map<String, _Pending> _pending = {};
  final List<Uint8List> _writeQueue = [];
  bool _writeInFlight = false;

  /// True once the service is checked and state notifications are on.
  bool get isReady => _ready;

  /// True when commands can be sent and acknowledged over this link.
  bool get canSendCommands => _ready && _ackReady;

  /// Starts the connection; a second call while one is running does nothing.
  void connect() {
    if (!_userClosed) return;
    _userClosed = false;
    _attempts = 0;
    _openLink();
  }

  /// Closes the link and stops any retry.
  void disconnect() {
    _userClosed = true;
    _reconnect?.cancel();
    _reconnect = null;
    _generation++;
    _releaseLink();
    onStatus(BleStatus.disconnected);
  }

  /// Sends [payload] (a JSON command) as framed writes. False when the link is not ready or the message is empty or
  /// too large; true only means "queued": a refused write is reported through [onError] later.
  bool send(String payload) {
    if (!_ready) {
      onError(const BleError(BleErrorKind.notConnected));
      return false;
    }
    final bytes = Uint8List.fromList(utf8.encode(payload));
    final frames = BleFraming.encode(bytes, _mtu);
    if (frames.isEmpty) {
      if (bytes.isNotEmpty) onError(const BleError(BleErrorKind.messageTooLarge));
      return false;
    }
    _writeQueue.addAll(frames);
    _pumpWrites();
    return true;
  }

  /// Sends one robot command and reports what became of it: [BleAcknowledged] only after the peripheral answered (and
  /// `ack.ok` says whether the server applied it), [BleNoAnswer] when nothing answered within the timeout or the link
  /// dropped (the command counts as NOT delivered: a STOP nobody confirmed must not look confirmed), [BleNotAvailable] or
  /// [BleTooLarge] when nothing was sent. The BLE write response only proves that the radio delivered a frame, so it is
  /// never taken as an acknowledgement.
  void sendCommand(BleCommandRequest request, void Function(BleCommandOutcome) onResult) {
    if (!canSendCommands) {
      onResult(const BleNotAvailable());
      return;
    }
    var id = 'i-${++_commandCounter}-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    if (id.length > BleCommands.maxIdChars) id = id.substring(0, BleCommands.maxIdChars);
    final frames = BleFraming.encode(BleCommands.encode(id, request), _mtu);
    if (frames.isEmpty) {
      onResult(const BleTooLarge());
      return;
    }
    final pending = _Pending(onResult);
    _pending[id] = pending;
    pending.timeout = Timer(ackTimeout, () {
      _pending.remove(id)?.onResult(const BleNoAnswer());
    });
    _writeQueue.addAll(frames);
    _pumpWrites();
  }

  void _failPendingCommands() {
    if (_pending.isEmpty) return;
    final all = _pending.values.toList();
    _pending.clear();
    for (final p in all) {
      p.timeout?.cancel();
      p.onResult(const BleNoAnswer());
    }
  }

  void _markConnected() {
    _ready = true;
    _attempts = 0;
    onStatus(BleStatus.connected);
  }

  void _openLink() {
    final gen = ++_generation;
    onStatus(BleStatus.connecting);
    try {
      _link = connector.open(deviceId, _LinkEvents(this, gen));
    } on BleException catch (e) {
      _link = null;
      _failPermanently(e.error);
    }
  }

  void _releaseLink() {
    final old = _link;
    _link = null;
    _ready = false;
    _ackReady = false;
    _mtu = BleContract.defaultMtu;
    _writeQueue.clear();
    _writeInFlight = false;
    _reassembler.reset();
    _ackReassembler.reset();
    _failPendingCommands();
    old?.close();
  }

  /// An error no retry can fix: report it and stay disconnected.
  void _failPermanently(BleError error) {
    _userClosed = true;
    _generation++;
    _releaseLink();
    onStatus(BleStatus.disconnected);
    onError(error);
  }

  /// The link is gone (device out of range, powered off, failed to connect): retry or give up.
  void _linkLost(BleError error) {
    _releaseLink();
    if (_userClosed) return;
    if (reconnectPolicy.shouldRetry(_attempts)) {
      _attempts++;
      onStatus(BleStatus.connecting);
      _reconnect = Timer(reconnectPolicy.delayFor(_attempts), () {
        if (!_userClosed) _openLink();
      });
    } else {
      _userClosed = true;
      onStatus(BleStatus.disconnected);
      onError(BleError(BleErrorKind.reconnectGaveUp, error.status));
    }
  }

  void _pumpWrites() {
    if (_writeInFlight || _writeQueue.isEmpty) return;
    final frame = _writeQueue.removeAt(0);
    final started = _link?.writeCommand(frame) == true;
    if (started) {
      _writeInFlight = true;
    } else {
      _writeQueue.clear();
      onError(const BleError(BleErrorKind.writeFailed));
    }
  }

  void _startDiscovery() {
    if (_link?.discoverServices() != true) _linkLost(const BleError(BleErrorKind.serviceDiscoveryFailed));
  }
}

class _LinkEvents implements BleGattEvents {
  final HydraBleClient c;
  final int gen;
  _LinkEvents(this.c, this.gen);

  void _post(void Function() block) {
    // Delivered on the next turn of the event loop, like a callback from the platform, and only for the current link.
    scheduleMicrotask(() {
      if (gen == c._generation) block();
    });
  }

  @override
  void onConnectionState(bool connected, int status) => _post(() {
        if (!connected) {
          c._linkLost(BleError(BleErrorKind.connectFailed, status == 0 ? null : status));
        } else if (c._link?.requestMtu(c.preferredMtu) != true) {
          c._startDiscovery();
        }
      });

  @override
  void onMtu(int mtu, int status) => _post(() {
        if (status == 0 && mtu > BleContract.attOverhead + 1) c._mtu = mtu;
        c._startDiscovery();
      });

  @override
  void onServicesDiscovered(int status) => _post(() {
        if (status != 0) {
          c._linkLost(BleError(BleErrorKind.serviceDiscoveryFailed, status));
          return;
        }
        switch (c._link?.findContract()) {
          case BleContractLookup.found:
            if (c._link?.enableStateNotifications() != true) {
              c._failPermanently(const BleError(BleErrorKind.notificationsFailed));
            }
          case BleContractLookup.noService:
            c._failPermanently(const BleError(BleErrorKind.notAHydraDevice));
          default:
            c._failPermanently(const BleError(BleErrorKind.characteristicMissing));
        }
      });

  @override
  void onNotificationsEnabled(int status) => _post(() {
        if (status != 0) {
          c._failPermanently(BleError(BleErrorKind.notificationsFailed, status));
        } else if (c._link?.hasAckCharacteristic() == true && c._link?.enableAckNotifications() == true) {
          // The state is on. The device also takes commands: its acknowledgements are turned on before the link is
          // reported connected (one descriptor write at a time).
        } else {
          c._markConnected();
        }
      });

  @override
  void onAckNotificationsEnabled(int status) => _post(() {
        // A device whose acknowledgements cannot be turned on still shows its state; it just cannot take commands.
        c._ackReady = status == 0;
        c._markConnected();
      });

  @override
  void onAckFrame(Uint8List frame) => _post(() {
        final result = c._ackReassembler.push(frame);
        switch (result) {
          case BleMessage():
            final ack = BleCommands.parseAck(result.bytes);
            final id = ack?.id;
            if (ack == null || id == null) return;
            final pending = c._pending.remove(id);
            if (pending == null) return;
            pending.timeout?.cancel();
            pending.onResult(BleAcknowledged(ack));
          case BleMalformed():
            c.onError(const BleError(BleErrorKind.malformedFrame));
          case BlePending():
            break;
        }
      });

  @override
  void onStateFrame(Uint8List frame) => _post(() {
        final result = c._reassembler.push(frame);
        switch (result) {
          case BleMessage():
            c.onSettings(utf8.decode(result.bytes, allowMalformed: true));
          case BleMalformed():
            c.onError(const BleError(BleErrorKind.malformedFrame));
          case BlePending():
            break;
        }
      });

  @override
  void onWriteDone(int status) => _post(() {
        c._writeInFlight = false;
        if (status != 0) {
          // The rest of a message whose frame failed is useless to the device.
          c._writeQueue.clear();
          c.onError(BleError(BleErrorKind.writeFailed, status));
        } else {
          c._pumpWrites();
        }
      });
}
