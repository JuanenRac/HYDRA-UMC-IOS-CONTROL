// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/mjpeg_lifecycle_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The camera stream is closed while the app is in the background and opened
// again when it comes back, so a backgrounded app does not keep downloading
// video.
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:hydra_umc_control/l10n/app_localizations.dart';
import 'package:hydra_umc_control/ui/widgets/mjpeg_view.dart';

class _CountingClient extends http.BaseClient {
  int opened = 0;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    opened++;
    // A stream that never ends, as a live camera does.
    return http.StreamedResponse(StreamController<List<int>>().stream, 200);
  }

  @override
  void close() => closed = true;
}

void main() {
  testWidgets('the stream closes in the background and reopens on resume', (tester) async {
    final clients = <_CountingClient>[];
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MjpegView(
        url: 'http://127.0.0.1:1/api/camera/1/stream',
        clientFactory: () {
          final c = _CountingClient();
          clients.add(c);
          return c;
        },
      ),
    ));
    await tester.pump();
    expect(clients, hasLength(1));
    expect(clients.single.closed, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(clients.single.closed, isFalse, reason: 'inactive (control centre, a call banner) keeps the picture');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(clients.single.closed, isTrue, reason: 'in the background the stream is closed');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(clients, hasLength(2), reason: 'coming back opens one new connection');
    expect(clients.last.opened, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(clients, hasLength(2), reason: 'a second resume does not open another');
  });
}
