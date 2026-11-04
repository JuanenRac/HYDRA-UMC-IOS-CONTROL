import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_umc_control/util/viewer_lifecycle.dart';

void main() {
  test('the viewer stops when the app is really in the background', () {
    expect(ViewerLifecycle.mustStop(AppLifecycleState.paused), isTrue);
    expect(ViewerLifecycle.mustStop(AppLifecycleState.hidden), isTrue);
    expect(ViewerLifecycle.mustStop(AppLifecycleState.detached), isTrue);
  });

  test('the viewer keeps running while the app is in front or only momentarily inactive', () {
    expect(ViewerLifecycle.mustStop(AppLifecycleState.resumed), isFalse);
    expect(ViewerLifecycle.mustStop(AppLifecycleState.inactive), isFalse);
  });
}
