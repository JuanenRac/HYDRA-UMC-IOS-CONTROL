// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - network/ble_contract.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The Bluetooth LE contract between this app and a HYDRA-UMC device, the same
// one the Android app speaks: one GATT service with a STATE characteristic
// (read, notify: the robot state as UTF-8 JSON, the tree the WebSocket carries),
// a COMMAND characteristic (write: one UTF-8 JSON command per message) and an
// optional ACK characteristic (notify: one acknowledgement per command). A
// message is larger than one ATT payload, so both directions cut it into
// frames. EXPERIMENTAL: tested against a fake link, not against a real device.
// =============================================================================

import 'dart:typed_data';

class BleContract {
  BleContract._();

  /// Primary service a HYDRA-UMC device advertises.
  static const String serviceUuid = '48594452-0001-4000-8000-554d43000001';

  /// Robot state, notified by the device.
  static const String stateCharUuid = '48594452-0002-4000-8000-554d43000001';

  /// Commands written by the app.
  static const String commandCharUuid = '48594452-0003-4000-8000-554d43000001';

  /// Acknowledgements of the commands, notified by the device (absent on a device that takes no commands).
  static const String ackCharUuid = '48594452-0004-4000-8000-554d43000001';

  /// MTU of a link nobody negotiated.
  static const int defaultMtu = 23;

  /// MTU the app asks for; the device may grant less.
  static const int preferredMtu = 247;

  /// ATT header bytes inside an MTU.
  static const int attOverhead = 3;

  /// Largest message accepted in either direction.
  static const int maxMessageBytes = 64 * 1024;
}

/// What went wrong, without text: the app turns it into a message in the language of the phone.
enum BleErrorKind {
  bluetoothUnavailable,
  bluetoothOff,
  permissionDenied,
  invalidAddress,
  scanFailed,
  connectFailed,
  serviceDiscoveryFailed,

  /// The device answers but has no HYDRA service: it is not a HYDRA-UMC device.
  notAHydraDevice,

  /// The service exists but a characteristic is missing or lacks the needed property.
  characteristicMissing,
  notificationsFailed,
  writeFailed,
  notConnected,
  messageTooLarge,
  malformedFrame,
  reconnectGaveUp,
}

/// An error plus the platform status code, when there was one.
class BleError {
  final BleErrorKind kind;
  final int? status;
  const BleError(this.kind, [this.status]);

  @override
  String toString() => 'BleError($kind${status == null ? '' : ', $status'})';
}

/// Thrown by a link opener when a link cannot even be started.
class BleException implements Exception {
  final BleError error;
  const BleException(this.error);
  @override
  String toString() => 'BleException($error)';
}

/// Framing of a message over a link whose payload is MTU - 3 bytes.
///
/// Every frame starts with one header byte: bit 0 = first frame, bit 1 = last frame, bits 4-7 = sequence number (0 on
/// the first frame, +1 per frame, modulo 16). A message of one frame has both bits set. The rest of the frame is a slice
/// of the UTF-8 message.
class BleFraming {
  BleFraming._();

  static const int first = 0x01;
  static const int last = 0x02;

  /// Bytes of message that fit in one frame for this [mtu].
  static int chunkSize(int mtu) {
    final size = mtu - BleContract.attOverhead - 1;
    return size < 1 ? 1 : size;
  }

  /// Cuts [message] into frames; an empty or too large message gives an empty list.
  static List<Uint8List> encode(Uint8List message, int mtu) {
    if (message.isEmpty || message.length > BleContract.maxMessageBytes) return const [];
    final chunk = chunkSize(mtu);
    final count = (message.length + chunk - 1) ~/ chunk;
    return List.generate(count, (i) {
      final from = i * chunk;
      final to = from + chunk < message.length ? from + chunk : message.length;
      var header = (i & 0x0F) << 4;
      if (i == 0) header |= first;
      if (i == count - 1) header |= last;
      final frame = Uint8List(1 + to - from);
      frame[0] = header;
      frame.setRange(1, frame.length, message, from);
      return frame;
    });
  }
}

/// The result of feeding one frame to a [BleReassembler].
sealed class BleReassembly {
  const BleReassembly();
}

/// The message is not complete yet.
class BlePending extends BleReassembly {
  const BlePending();
}

/// The message is complete.
class BleMessage extends BleReassembly {
  final Uint8List bytes;
  const BleMessage(this.bytes);
}

/// The frame did not fit; the partial message was dropped.
class BleMalformed extends BleReassembly {
  const BleMalformed();
}

/// Puts frames back together; one instance per link.
class BleReassembler {
  BytesBuilder? _buffer;
  int _nextSeq = 0;

  /// Forgets a partial message (call when the link drops).
  void reset() {
    _buffer = null;
    _nextSeq = 0;
  }

  BleReassembly push(List<int> frame) {
    if (frame.isEmpty) return const BleMalformed();
    final header = frame[0] & 0xFF;
    final isFirst = header & BleFraming.first != 0;
    final isLast = header & BleFraming.last != 0;
    final seq = header >> 4;
    if (isFirst) {
      _buffer = BytesBuilder(copy: false);
      _nextSeq = 0;
    }
    final out = _buffer;
    if (out == null || seq != _nextSeq) {
      reset();
      return const BleMalformed();
    }
    if (out.length + frame.length - 1 > BleContract.maxMessageBytes) {
      reset();
      return const BleMalformed();
    }
    out.add(frame.sublist(1));
    _nextSeq = (_nextSeq + 1) & 0x0F;
    if (!isLast) return const BlePending();
    final bytes = out.toBytes();
    reset();
    return BleMessage(bytes);
  }
}

/// How a dropped link is retried: a growing delay, then give up. The values belong to the settings of the app.
class BleReconnectPolicy {
  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;
  const BleReconnectPolicy({
    this.maxAttempts = 5,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 16),
  });

  /// True while one more attempt is allowed after [attemptsDone].
  bool shouldRetry(int attemptsDone) => attemptsDone < maxAttempts;

  /// Delay before attempt number [attempt] (1 = the first retry): base, 2x, 4x... up to the cap.
  Duration delayFor(int attempt) {
    final shift = (attempt - 1).clamp(0, 30);
    final ms = baseDelay.inMilliseconds << shift;
    final cap = maxDelay.inMilliseconds;
    return Duration(milliseconds: ms > cap ? cap : ms);
  }
}
