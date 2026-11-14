// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/mjpeg_stall_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// A camera connection that stays silent (it never answers, or it stops sending
// bytes) is given up after MjpegReconnectPolicy.stallTimeout and opened again,
// like the read timeout of the Android player. Any bytes at all count as life.
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:hydra_umc_control/l10n/app_localizations.dart';
import 'package:hydra_umc_control/ui/widgets/mjpeg_view.dart';

/// A connection the test keeps open: it answers 200 at once and sends what the
/// test gives it, or (with [answers] false) never answers at all.
class _SilentClient extends http.BaseClient {
  _SilentClient({this.answers = true});
  final bool answers;
  final StreamController<List<int>> body = StreamController<List<int>>();
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!answers) return Completer<http.StreamedResponse>().future;
    return Future.value(http.StreamedResponse(body.stream, 200));
  }

  @override
  void close() => closed = true;
}

Widget _app(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

Future<List<_SilentClient>> _open(WidgetTester tester, bool Function(int index) answers) async {
  final clients = <_SilentClient>[];
  await tester.pumpWidget(_app(MjpegView(
    url: 'http://127.0.0.1:1/api/camera/1/stream',
    clientFactory: () {
      final c = _SilentClient(answers: answers(clients.length));
      clients.add(c);
      return c;
    },
  )));
  await tester.pump();
  return clients;
}

void main() {
  test('the silence that is given up is thirty seconds, like the Android read timeout', () {
    expect(MjpegReconnectPolicy.stallTimeout, const Duration(seconds: 30));
  });

  testWidgets('a connection that never answers is closed after thirty seconds and tried again', (tester) async {
    final clients = await _open(tester, (_) => false);
    expect(clients, hasLength(1));
    await tester.pump(const Duration(seconds: 29));
    expect(clients.single.closed, isFalse);
    await tester.pump(const Duration(seconds: 2));
    expect(clients.single.closed, isTrue, reason: 'thirty seconds of silence end the attempt');
    expect(find.byType(Text), findsOneWidget, reason: 'the view says the camera is unavailable');
    expect(clients, hasLength(1));
    await tester.pump(const Duration(milliseconds: 2100));
    expect(clients, hasLength(2), reason: 'the usual wait of a failed attempt, then a new connection');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('bytes keep the connection alive and the silence is counted from the last ones', (tester) async {
    final clients = await _open(tester, (_) => true);
    await tester.pump(const Duration(seconds: 20));
    clients.single.body.add([1, 2, 3]); // not a frame, but the camera is alive
    await tester.pump();
    await tester.pump(const Duration(seconds: 25));
    expect(clients.single.closed, isFalse, reason: '45 s since the start but only 25 s since the last bytes');
    await tester.pump(const Duration(seconds: 6));
    expect(clients.single.closed, isTrue, reason: '31 s without bytes');
    await tester.pumpWidget(const SizedBox());
    unawaited(clients.single.body.close());
  });

  testWidgets('a view that left the screen or went to the background does not wake up later', (tester) async {
    final clients = await _open(tester, (_) => false);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 2));
    expect(clients, hasLength(1), reason: 'in the background nothing is counted and nothing is opened');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(clients, hasLength(2));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
    expect(clients, hasLength(2), reason: 'a view that was taken off the screen opens nothing');
  });
}
