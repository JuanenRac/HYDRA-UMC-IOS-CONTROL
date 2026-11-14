// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/mjpeg_reconnect_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The camera view opens a stream again after the wait of MjpegReconnectPolicy
// (the same schedule as the Android player): one second doubling to fifteen,
// back to the start when a frame arrives. The schedule is tested on its own
// and the view is tested with fake connections that are refused or end.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:hydra_umc_control/l10n/app_localizations.dart';
import 'package:hydra_umc_control/ui/widgets/mjpeg_view.dart';

/// A fake connection: answers with [status]; a 200 gives a stream that ends at
/// once, or throws before any answer ([sendThrows]).
class _FakeClient extends http.BaseClient {
  _FakeClient(this.status, {this.sendThrows = false});
  final int status;
  final bool sendThrows;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (sendThrows) throw const FormatException('no route to the camera');
    if (status != 200) return http.StreamedResponse(const Stream<List<int>>.empty(), status);
    return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
  }

  @override
  void close() => closed = true;
}

Widget _app(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

void main() {
  group('MjpegReconnectPolicy', () {
    test('the first wait is one second and the schedule doubles up to the ceiling', () {
      final waits = [for (var i = 0; i <= 8; i++) MjpegReconnectPolicy.delayFor(i).inMilliseconds];
      expect(waits, [1000, 2000, 4000, 8000, 15000, 15000, 15000, 15000, 15000]);
    });

    test('the schedule never shrinks while nothing arrives and never passes the ceiling', () {
      var failures = 0;
      var last = Duration.zero;
      for (var i = 0; i < 40; i++) {
        failures = MjpegReconnectPolicy.failuresAfter(failures, gotFrame: false);
        final wait = MjpegReconnectPolicy.delayFor(failures);
        expect(wait >= last, isTrue);
        expect(wait <= MjpegReconnectPolicy.maxDelay, isTrue);
        last = wait;
      }
    });

    test('a frame sends the schedule back to the first wait', () {
      var failures = 0;
      for (var i = 0; i < 6; i++) {
        failures = MjpegReconnectPolicy.failuresAfter(failures, gotFrame: false);
      }
      expect(MjpegReconnectPolicy.delayFor(failures), MjpegReconnectPolicy.maxDelay);
      failures = MjpegReconnectPolicy.failuresAfter(failures, gotFrame: true);
      expect(failures, 0);
      expect(MjpegReconnectPolicy.delayFor(failures), MjpegReconnectPolicy.baseDelay);
    });

    test('a negative count is no failure and a huge one does not overflow', () {
      expect(MjpegReconnectPolicy.delayFor(-3), MjpegReconnectPolicy.baseDelay);
      expect(MjpegReconnectPolicy.failuresAfter(-5, gotFrame: false), 1);
      expect(MjpegReconnectPolicy.delayFor(1 << 62), MjpegReconnectPolicy.maxDelay);
      expect(MjpegReconnectPolicy.failuresAfter(1 << 62, gotFrame: false), 1001);
    });
  });

  group('MjpegView reconnects', () {
    testWidgets('a refused connection is tried again after two seconds, then four, and says why', (tester) async {
      final clients = <_FakeClient>[];
      await tester.pumpWidget(_app(MjpegView(
        url: 'http://127.0.0.1:1/api/camera/1/stream',
        clientFactory: () {
          final c = _FakeClient(503);
          clients.add(c);
          return c;
        },
      )));
      await tester.pump();
      expect(clients, hasLength(1));
      expect(find.textContaining('503'), findsOneWidget, reason: 'the refusal is shown with its status');
      expect(clients.single.closed, isTrue, reason: 'a refused connection is closed');

      await tester.pump(const Duration(milliseconds: 1900));
      expect(clients, hasLength(1), reason: 'the first failure waits two seconds');
      await tester.pump(const Duration(milliseconds: 200));
      expect(clients, hasLength(2));

      await tester.pump(const Duration(milliseconds: 3800));
      expect(clients, hasLength(2), reason: 'the second failure waits four seconds');
      await tester.pump(const Duration(milliseconds: 200));
      expect(clients, hasLength(3));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 60));
      expect(clients, hasLength(3), reason: 'a view that was taken off the screen opens nothing');
    });

    testWidgets('a stream that ends is opened again and one that cannot be reached too', (tester) async {
      var made = 0;
      final clients = <_FakeClient>[];
      await tester.pumpWidget(_app(MjpegView(
        url: 'http://127.0.0.1:1/api/camera/1/stream',
        clientFactory: () {
          made++;
          final c = made == 1 ? _FakeClient(200) : _FakeClient(200, sendThrows: true);
          clients.add(c);
          return c;
        },
      )));
      await tester.pump();
      expect(clients, hasLength(1));
      await tester.pump(const Duration(milliseconds: 2100));
      expect(clients, hasLength(2), reason: 'the ended stream is opened again');
      await tester.pump(const Duration(milliseconds: 4100));
      expect(clients, hasLength(3), reason: 'so is a connection that threw');
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(Text), findsOneWidget, reason: 'the view says the camera is unavailable');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('going to the background stops the wait and coming back opens one connection at once', (tester) async {
      final clients = <_FakeClient>[];
      await tester.pumpWidget(_app(MjpegView(
        url: 'http://127.0.0.1:1/api/camera/1/stream',
        clientFactory: () {
          final c = _FakeClient(503);
          clients.add(c);
          return c;
        },
      )));
      await tester.pump();
      expect(clients, hasLength(1));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 30));
      expect(clients, hasLength(1), reason: 'nothing is opened while the app is in the background');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(clients, hasLength(2), reason: 'coming back does not wait for the old schedule');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(clients, hasLength(2), reason: 'a second resume opens nothing more');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a new address starts the schedule again from the first connection', (tester) async {
      final clients = <_FakeClient>[];
      http.Client make() {
        final c = _FakeClient(503);
        clients.add(c);
        return c;
      }

      await tester.pumpWidget(_app(MjpegView(url: 'http://127.0.0.1:1/api/camera/1/stream', clientFactory: make)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2100));
      expect(clients, hasLength(2));

      await tester.pumpWidget(_app(MjpegView(url: 'http://127.0.0.1:1/api/camera/2/stream', clientFactory: make)));
      await tester.pump();
      expect(clients, hasLength(3), reason: 'the new address is opened at once');
      await tester.pump(const Duration(milliseconds: 1900));
      expect(clients, hasLength(3), reason: 'and its first failure waits two seconds again');
      await tester.pump(const Duration(milliseconds: 200));
      expect(clients, hasLength(4));
      await tester.pumpWidget(const SizedBox());
    });
  });
}
