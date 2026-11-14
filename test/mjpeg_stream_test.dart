// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/mjpeg_stream_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// What the camera view does with the bytes of a stream: it shows the newest
// complete JPEG, puts together a frame that arrives in pieces, starts over when
// the pending bytes pass the cap, shows an answer other than 200 as its status
// and sends the headers it was given. The connections are fake.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:hydra_umc_control/l10n/app_localizations.dart';
import 'package:hydra_umc_control/ui/widgets/mjpeg_view.dart';

// Two real 8x8 JPEG pictures (red and blue), so the view decodes what it is given.
final Uint8List redJpeg = base64Decode(
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDABALDA4MChAODQ4SERATGCgaGBYWGDEjJR0oOjM9PDkz'
    'ODdASFxOQERXRTc4UG1RV19iZ2hnPk1xeXBkeFxlZ2P/2wBDARESEhgVGC8aGi9jQjhCY2NjY2Nj'
    'Y2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2P/wAARCAAIAAgDASIA'
    'AhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQA'
    'AAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3'
    'ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWm'
    'p6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEA'
    'AwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSEx'
    'BhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElK'
    'U1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3'
    'uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDFooor'
    'yz7w/9k=',
);

final Uint8List blueJpeg = base64Decode(
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDABALDA4MChAODQ4SERATGCgaGBYWGDEjJR0oOjM9PDkz'
    'ODdASFxOQERXRTc4UG1RV19iZ2hnPk1xeXBkeFxlZ2P/2wBDARESEhgVGC8aGi9jQjhCY2NjY2Nj'
    'Y2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2P/wAARCAAIAAgDASIA'
    'AhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQA'
    'AAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3'
    'ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWm'
    'p6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEA'
    'AwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSEx'
    'BhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElK'
    'U1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3'
    'uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDjaKKK'
    '+8OU/9k=',
);

/// A fake connection whose stream the test feeds by hand.
class _LiveClient extends http.BaseClient {
  _LiveClient({this.status = 200});
  final int status;
  final StreamController<List<int>> body = StreamController<List<int>>();
  final List<http.BaseRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return http.StreamedResponse(body.stream, status);
  }
}

Widget _app(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

Future<_LiveClient> _open(WidgetTester tester, {int status = 200, Map<String, String>? headers}) async {
  final client = _LiveClient(status: status);
  await tester.pumpWidget(_app(MjpegView(
    url: 'http://127.0.0.1:1/api/camera/1/stream',
    headers: headers,
    clientFactory: () => client,
  )));
  await tester.pump();
  return client;
}

Uint8List _shown(WidgetTester tester) {
  final image = tester.widget<Image>(find.byType(Image)).image;
  return (image as MemoryImage).bytes;
}

Uint8List _join(List<List<int>> parts) => Uint8List.fromList([for (final p in parts) ...p]);

/// Hands bytes to the view and lets the screen catch up (two turns: the bytes, then the picture).
Future<void> _feed(WidgetTester tester, _LiveClient client, List<int> bytes) async {
  client.body.add(bytes);
  await tester.pump();
  await tester.pump();
}

Future<void> _leave(WidgetTester tester, _LiveClient client) async {
  await tester.pumpWidget(const SizedBox());
  unawaited(client.body.close());
}

void main() {
  testWidgets('a picture is waited for with a progress ring until the first frame', (tester) async {
    final client = await _open(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    await _leave(tester, client);
  });

  testWidgets('a complete frame is shown, and the multipart framing around it does not matter', (tester) async {
    final client = await _open(tester);
    await _feed(tester, client, _join([
      utf8.encode('--frame\r\nContent-Type: image/jpeg\r\nContent-Length: ${redJpeg.length}\r\n\r\n'),
      redJpeg,
      utf8.encode('\r\n'),
    ]));
    expect(find.byType(Image), findsOneWidget);
    expect(_shown(tester), redJpeg);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await _leave(tester, client);
  });

  testWidgets('when two frames arrive together the newest one is shown', (tester) async {
    final client = await _open(tester);
    await _feed(tester, client, _join([redJpeg, utf8.encode('\r\n--frame\r\n\r\n'), blueJpeg]));
    expect(_shown(tester), blueJpeg);
    await _leave(tester, client);
  });

  testWidgets('a frame that arrives in pieces is put together and the next one replaces it', (tester) async {
    final client = await _open(tester);
    final half = redJpeg.length ~/ 2;
    await _feed(tester, client, redJpeg.sublist(0, half));
    expect(find.byType(Image), findsNothing, reason: 'half a frame is not a picture');
    await _feed(tester, client, redJpeg.sublist(half));
    expect(_shown(tester), redJpeg);

    await _feed(tester, client, blueJpeg.sublist(0, 40));
    expect(_shown(tester), redJpeg, reason: 'the old picture stays until the next one is complete');
    await _feed(tester, client, blueJpeg.sublist(40));
    expect(_shown(tester), blueJpeg);
    await _leave(tester, client);
  });

  testWidgets('bytes that never end a frame are dropped at the cap and the next frame still shows', (tester) async {
    final client = await _open(tester);
    // An error page or a corrupt stream: more than the cap, with no frame end in it.
    await _feed(tester, client, Uint8List(mjpegMaxBufferBytes + 1024)..fillRange(0, mjpegMaxBufferBytes + 1024, 0x41));
    expect(find.byType(Image), findsNothing);
    await _feed(tester, client, blueJpeg);
    expect(_shown(tester), blueJpeg);
    await _leave(tester, client);
  });

  testWidgets('the headers that were given go with the request', (tester) async {
    final client = await _open(tester, headers: {'Authorization': 'Bearer sample', 'X-Hydra-Client': 'test'});
    expect(client.requests, hasLength(1));
    expect(client.requests.single.method, 'GET');
    expect(client.requests.single.url.path, '/api/camera/1/stream');
    expect(client.requests.single.headers['Authorization'], 'Bearer sample');
    expect(client.requests.single.headers['X-Hydra-Client'], 'test');
    await _leave(tester, client);
  });

  testWidgets('an answer other than 200 is shown as its status and never parsed as video', (tester) async {
    final client = await _open(tester, status: 401);
    // Even a body that holds a whole JPEG is not a picture when the answer was a refusal.
    await _feed(tester, client, redJpeg);
    expect(find.textContaining('401'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    await _leave(tester, client);
  });

  testWidgets('the picture stays on the screen when the stream stops', (tester) async {
    final client = await _open(tester);
    await _feed(tester, client, redJpeg);
    unawaited(client.body.close());
    await tester.pump();
    expect(_shown(tester), redJpeg, reason: 'the last frame is kept');
    await tester.pumpWidget(const SizedBox());
  });
}
