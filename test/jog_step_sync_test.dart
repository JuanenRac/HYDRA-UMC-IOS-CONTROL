import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_umc_control/models/hydra_state.dart';

void main() {
  const steps = [0.1, 1.0, 5.0, 10.0, 25.0, 50.0, 90.0, 100.0];

  test('the jog step is the one the server keeps, snapped to a step the screen offers', () {
    expect(RobotView({'id': 1, 'jogStep': 25}).jogStep, 25.0);
    expect(RobotView({'id': 1, 'jogStep': 25}).jogStepOr(10, steps), 25.0);
    expect(RobotView({'id': 1, 'jogStep': 30}).jogStepOr(10, steps), 25.0);
    expect(RobotView({'id': 1, 'jogStep': 0.3}).jogStepOr(10, steps), 0.1);
    expect(RobotView({'id': 1, 'jogStep': 400}).jogStepOr(10, steps), 100.0);
  });

  test('a robot with no usable step falls back', () {
    for (final raw in [<String, dynamic>{'id': 1}, {'id': 1, 'jogStep': 0}, {'id': 1, 'jogStep': -5}, {'id': 1, 'jogStep': 'x'}, {'id': 1, 'jogStep': double.nan}]) {
      expect(RobotView(raw).jogStep, isNull);
      expect(RobotView(raw).jogStepOr(10, steps), 10.0);
    }
  });
}
