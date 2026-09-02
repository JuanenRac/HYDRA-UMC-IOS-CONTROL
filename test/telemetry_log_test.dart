// Real coverage for state/robot_view_model.dart's telemetry log
// (ui/telemetry_screen.dart's own data source): grows on a real command
// round-trip, stays capped at 50 entries, and clearTelemetryLog() actually
// empties it.
//
// Exercised via sendCommand('play') rather than login() - login() always
// constructs its own real HydraApiClient(host, port) internally (no way
// to inject a mock into it), while sendCommand()'s underlying
// _sendAtomicCommand() reuses whatever apiClient is already set, which a
// test can inject directly (see robot_view_model_test.dart's own sibling
// coverage in HYDRA-UMC-DSI for the same pattern).

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydra_umc_control/models/hydra_state.dart';
import 'package:hydra_umc_control/network/hydra_api_client.dart';
import 'package:hydra_umc_control/state/robot_view_model.dart';

Map<String, dynamic> _rawStateWithOneRobot() => {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('a real command round-trip adds real log entries', () async {
    final vm = RobotViewModel();
    vm.state = HydraState(_rawStateWithOneRobot());
    vm.selectedRobotId = 1;
    vm.apiClient = HydraApiClient(
      'testhost',
      3000,
      client: MockClient((request) async => http.Response('{"success": true}', 200)),
    );
    expect(vm.telemetryLog, isEmpty);

    vm.sendCommand('play');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(vm.telemetryLog, isNotEmpty);
    expect(vm.telemetryLog.first, contains('TX OK [play]'));
  });

  test('the log never grows past 50 entries', () async {
    final vm = RobotViewModel();
    vm.state = HydraState(_rawStateWithOneRobot());
    vm.selectedRobotId = 1;
    vm.apiClient = HydraApiClient(
      'testhost',
      3000,
      client: MockClient((request) async => http.Response('{"success": true}', 200)),
    );

    for (var i = 0; i < 60; i++) {
      vm.sendCommand('play');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }

    expect(vm.telemetryLog.length, 50);
  });

  test('clearTelemetryLog empties the log', () async {
    final vm = RobotViewModel();
    vm.state = HydraState(_rawStateWithOneRobot());
    vm.selectedRobotId = 1;
    vm.apiClient = HydraApiClient(
      'testhost',
      3000,
      client: MockClient((request) async => http.Response('{"success": true}', 200)),
    );
    vm.sendCommand('play');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(vm.telemetryLog, isNotEmpty);

    vm.clearTelemetryLog();

    expect(vm.telemetryLog, isEmpty);
  });
}
