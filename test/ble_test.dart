// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/ble_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The Bluetooth LE contract, the framing, the commands and the client state
// machine against a fake link (experimental: never run against a real device).
// =============================================================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hydra_umc_control/network/ble_commands.dart';
import 'package:hydra_umc_control/network/ble_contract.dart';
import 'package:hydra_umc_control/network/ble_gatt.dart';
import 'package:hydra_umc_control/network/ble_gatt_fbp.dart';
import 'package:hydra_umc_control/network/hydra_ble_client.dart';

import 'ble_fake.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('framing', () {
    test('a short message is one frame with both flags and a long one round-trips', () {
      final one = BleFraming.encode(_bytes('hi'), 64);
      expect(one, hasLength(1));
      expect(one[0][0], 0x03);
      final text = 'x' * 1000;
      final frames = BleFraming.encode(_bytes(text), 23);
      expect(frames.length, greaterThan(40));
      final r = BleReassembler();
      BleReassembly? out;
      for (final f in frames) {
        out = r.push(f);
      }
      expect(out, isA<BleMessage>());
      expect(utf8.decode((out as BleMessage).bytes), text);
    });

    test('empty and too large messages give no frames', () {
      expect(BleFraming.encode(Uint8List(0), 64), isEmpty);
      expect(BleFraming.encode(Uint8List(BleContract.maxMessageBytes + 1), 64), isEmpty);
    });

    test('a frame out of order drops the partial message', () {
      final frames = BleFraming.encode(_bytes('y' * 200), 23);
      final r = BleReassembler();
      expect(r.push(frames[0]), isA<BlePending>());
      expect(r.push(frames[2]), isA<BleMalformed>());
      expect(r.push(Uint8List(0)), isA<BleMalformed>());
    });

    test('the sequence wraps after 16 frames', () {
      final frames = BleFraming.encode(_bytes('z' * 400), 10);
      expect(frames.length, greaterThan(16));
      final r = BleReassembler();
      BleReassembly? out;
      for (final f in frames) {
        out = r.push(f);
      }
      expect(out, isA<BleMessage>());
    });

    test('the reconnect delay doubles up to the cap', () {
      const p = BleReconnectPolicy();
      expect(p.delayFor(1), const Duration(seconds: 1));
      expect(p.delayFor(3), const Duration(seconds: 4));
      expect(p.delayFor(20), const Duration(seconds: 16));
      expect(p.shouldRetry(4), isTrue);
      expect(p.shouldRetry(5), isFalse);
    });
  });

  group('commands', () {
    test('a command carries the id, the robot and the token, and an ack is read back', () {
      final msg = BleCommands.encode('c1', const BleCommandRequest(robotId: 2, command: 'stop', token: 'tok', controllerId: 'ctl'));
      final json = jsonDecode(utf8.decode(msg)) as Map<String, dynamic>;
      expect(json['id'], 'c1');
      expect(json['robotId'], 2);
      expect(json['command'], 'stop');
      expect(json['token'], 'tok');
      expect(json['controllerId'], 'ctl');
      final ack = BleCommands.parseAck(_bytes('{"id":"c1","ok":true,"status":200,"code":"ok"}'))!;
      expect(ack.ok, isTrue);
      expect(ack.status, 200);
      expect(BleCommands.parseAck(_bytes('not json')), isNull);
      expect(BleCommands.parseAck(_bytes('{"id":"c1"}')), isNull);
    });
  });

  group('client', () {
    late FakeConnector connector;
    late List<BleStatus> statuses;
    late List<String> states;
    late List<BleError> errors;

    HydraBleClient make({BleReconnectPolicy? policy, Duration ackTimeout = const Duration(milliseconds: 50)}) {
      return HydraBleClient(
        connector: connector,
        deviceId: 'dev-1',
        onStatus: statuses.add,
        onSettings: states.add,
        onError: errors.add,
        reconnectPolicy: policy ?? const BleReconnectPolicy(baseDelay: Duration(milliseconds: 5), maxDelay: Duration(milliseconds: 10)),
        ackTimeout: ackTimeout,
      );
    }

    setUp(() {
      connector = FakeConnector();
      statuses = [];
      states = [];
      errors = [];
    });

    test('it connects, reports the state and can take commands', () async {
      final client = make()..connect();
      final link = connector.links.single;
      link.bringUp();
      await settle();
      expect(statuses, [BleStatus.connecting, BleStatus.connected]);
      expect(client.isReady, isTrue);
      expect(client.canSendCommands, isTrue);
      link.notifyState('{"controllers":[]}');
      await settle();
      expect(states.single, '{"controllers":[]}');
    });

    test('a device without the HYDRA service is refused for good', () async {
      final client = make()..connect();
      final link = connector.links.single..lookup = BleContractLookup.noService;
      link.events.onConnectionState(true, 0);
      link.events.onMtu(64, 0);
      link.events.onServicesDiscovered(0);
      await settle();
      expect(errors.single.kind, BleErrorKind.notAHydraDevice);
      expect(statuses.last, BleStatus.disconnected);
      expect(client.isReady, isFalse);
      expect(link.closed, isTrue);
    });

    test('a link that drops is retried and then given up', () async {
      final client = make(policy: const BleReconnectPolicy(maxAttempts: 2, baseDelay: Duration(milliseconds: 5), maxDelay: Duration(milliseconds: 5)))
        ..connect();
      for (var i = 0; i < 3; i++) {
        await settle();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (connector.links.length > i) connector.links[i].events.onConnectionState(false, 8);
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(connector.links.length, 3);
      expect(errors.last.kind, BleErrorKind.reconnectGaveUp);
      expect(statuses.last, BleStatus.disconnected);
      expect(client.isReady, isFalse);
    });

    test('a command is acknowledged only by the answer of the device', () async {
      final client = make()..connect();
      final link = connector.links.single..bringUp();
      await settle();
      BleCommandOutcome? outcome;
      client.sendCommand(const BleCommandRequest(robotId: 1, command: 'stop', token: 't'), (o) => outcome = o);
      link.events.onWriteDone(0);
      await settle();
      final sent = link.lastCommand()!;
      expect(sent['command'], 'stop');
      expect(outcome, isNull, reason: 'a write response proves nothing');
      link.notifyAck({'id': sent['id'], 'ok': true, 'status': 200, 'code': 'ok'});
      await settle();
      expect(outcome, isA<BleAcknowledged>());
      expect((outcome as BleAcknowledged).ack.ok, isTrue);
    });

    test('a command nobody answers counts as not delivered', () async {
      final client = make(ackTimeout: const Duration(milliseconds: 20))..connect();
      connector.links.single.bringUp();
      await settle();
      BleCommandOutcome? outcome;
      client.sendCommand(const BleCommandRequest(robotId: 1, command: 'stop', token: 't'), (o) => outcome = o);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(outcome, isA<BleNoAnswer>());
    });

    test('a command on a device without acknowledgements is not available, and a link that drops fails the pending ones', () async {
      final client = make()..connect();
      final link = connector.links.single..hasAck = false;
      link.bringUp();
      await settle();
      BleCommandOutcome? outcome;
      client.sendCommand(const BleCommandRequest(robotId: 1, command: 'stop', token: 't'), (o) => outcome = o);
      expect(outcome, isA<BleNotAvailable>());

      final c2 = make()..connect();
      final l2 = connector.links.last..bringUp();
      await settle();
      BleCommandOutcome? o2;
      c2.sendCommand(const BleCommandRequest(robotId: 1, command: 'jog', token: 't'), (o) => o2 = o);
      c2.disconnect();
      expect(o2, isA<BleNoAnswer>());
      expect(l2.closed, isTrue);
    });

    test('a damaged state frame is reported and a refused write too', () async {
      final client = make()..connect();
      final link = connector.links.single..bringUp();
      await settle();
      link.events.onStateFrame(Uint8List.fromList([0x10, 1]));
      await settle();
      expect(errors.last.kind, BleErrorKind.malformedFrame);
      link.refuseWrite = true;
      expect(client.send('{"a":1}'), isTrue);
      expect(errors.last.kind, BleErrorKind.writeFailed);
    });

    test('events of an older link are dropped and a start that cannot be made is permanent', () async {
      connector.failWith = const BleException(BleError(BleErrorKind.bluetoothOff));
      final client = make()..connect();
      await settle();
      expect(errors.single.kind, BleErrorKind.bluetoothOff);
      expect(client.isReady, isFalse);
      connector.failWith = null;
      client.connect();
      final old = connector.links.single;
      client.disconnect();
      old.events.onConnectionState(true, 0);
      await settle();
      expect(client.isReady, isFalse);
    });
  });

  test('the list keeps the strongest first and remembers a name', () {
    var list = <BleDevice>[];
    list = upsertBleDevice(list, const BleDevice(null, 'a', -80));
    list = upsertBleDevice(list, const BleDevice('Robot', 'b', -50));
    list = upsertBleDevice(list, const BleDevice('Named', 'a', -40));
    list = upsertBleDevice(list, const BleDevice(null, 'a', -45));
    expect(list.map((d) => d.id), ['a', 'b']);
    expect(list.first.name, 'Named');
  });
}
