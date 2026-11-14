// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/widgets/mjpeg_view.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Live MJPEG picture from HYDRA-UMC-SERVER's GET /api/camera/:id/stream (a
// multipart/x-mixed-replace stream of JPEG frames). The frames are found by
// scanning for the JPEG start/end markers, which works whatever the exact
// multipart framing is.
//
//  - [headers] carry the client identity and the bearer token: a server run
//    with HYDRA_UMC_CAMERA_AUTH=required refuses the picture without them.
//  - Only an HTTP 200 is a stream; any other answer is shown as "unavailable"
//    with its reason instead of being parsed as if it were video.
//  - When frames arrive faster than they are drawn the NEWEST complete frame
//    is shown, not the oldest, so the picture never lags further behind.
//  - The pending bytes are capped, so a stream that never produces a frame
//    end (corrupt, or an error page) cannot grow the buffer without limit.
//  - The stream is closed when the app leaves the foreground and opened again
//    when it returns, so a backgrounded app does not keep downloading video.
//  - Every connection attempt carries a generation number: the answer of an
//    attempt that was replaced (the address changed, the widget was disposed)
//    is dropped instead of leaving a second stream running.
//  - A stream that ends, fails or is refused is opened again after the wait of
//    [MjpegReconnectPolicy] (the same schedule as the Android player), for as
//    long as the view is shown and the app is in the foreground.
//  - A connection that stays silent (no answer, or no bytes) for
//    [MjpegReconnectPolicy.stallTimeout] counts as ended, like the read timeout
//    of the Android player, so a stalled camera is opened again too.
// =============================================================================

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../l10n/app_localizations.dart';
import '../../network/tls_settings.dart';

/// Upper bound for the bytes waiting for a frame end.
const int mjpegMaxBufferBytes = 4 * 1024 * 1024;

/// How long the camera view waits before it opens a stream again.
///
/// The pause is one second, doubles with every attempt that brought no frame,
/// stops growing after four doublings and never passes fifteen seconds, so a
/// dead camera is polled gently and a recovered one is picked up within
/// seconds. Pure on purpose: the schedule is tested without a screen or a
/// socket. It is the same schedule as `MjpegReconnectPolicy` of the Android app.
class MjpegReconnectPolicy {
  const MjpegReconnectPolicy._();

  static const Duration baseDelay = Duration(seconds: 1);
  static const Duration maxDelay = Duration(seconds: 15);

  /// How long a connection may stay silent before it is given up and opened again.
  static const Duration stallTimeout = Duration(seconds: 30);
  static const int _maxDoublings = 4;
  static const int _countLimit = 1000;

  static int _bounded(int value, int top) => value < 0 ? 0 : (value > top ? top : value);

  /// Attempts in a row that brought no frame, after the one that just ended.
  static int failuresAfter(int previousFailures, {required bool gotFrame}) =>
      gotFrame ? 0 : _bounded(previousFailures, _countLimit) + 1;

  /// Pause before the next attempt, for the number of failures in a row.
  static Duration delayFor(int failures) {
    final doublings = _bounded(failures, _maxDoublings);
    final wait = baseDelay * (1 << doublings);
    return wait > maxDelay ? maxDelay : wait;
  }
}

/// The newest complete JPEG in [bytes] as (start, endExclusive), or null when
/// there is none yet. Used by the view, and testable on its own.
({int start, int end})? findLastJpegFrame(Uint8List bytes) {
  // Last end-of-image marker, then the closest start-of-image before it.
  var end = -1;
  for (var i = bytes.length - 2; i >= 0; i--) {
    if (bytes[i] == 0xFF && bytes[i + 1] == 0xD9) {
      end = i;
      break;
    }
  }
  if (end < 0) return null;
  for (var i = end - 2; i >= 0; i--) {
    if (bytes[i] == 0xFF && bytes[i + 1] == 0xD8) {
      return (start: i, end: end + 2);
    }
  }
  return null;
}

class MjpegView extends StatefulWidget {
  final String url;
  final Map<String, String>? headers;

  /// Creates the HTTP client of each connection (a test passes a fake).
  final http.Client Function()? clientFactory;
  const MjpegView({super.key, required this.url, this.headers, this.clientFactory});

  @override
  State<MjpegView> createState() => _MjpegViewState();
}

class _MjpegViewState extends State<MjpegView> with WidgetsBindingObserver {
  Uint8List? _frame;
  StreamSubscription<List<int>>? _sub;
  http.Client? _client;
  Timer? _retry;
  Timer? _stall;
  bool _hasError = false;
  String? _reason;
  int _generation = 0;
  bool _pausedByLifecycle = false;

  /// Attempts in a row that brought no frame (the input of the reconnect wait).
  int _failures = 0;

  /// True once the attempt in progress has delivered a frame.
  bool _attemptGotFrame = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (_client != null || _sub != null || _retry != null) {
          _stop();
          _pausedByLifecycle = true;
        }
      case AppLifecycleState.resumed:
        if (_pausedByLifecycle) {
          _pausedByLifecycle = false;
          _failures = 0;
          _start();
        }
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void didUpdateWidget(covariant MjpegView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _stop();
      _frame = null;
      _hasError = false;
      _reason = null;
      _failures = 0;
      _start();
    }
  }

  /// The attempt of [generation] is over (the stream ended, failed or was
  /// refused): close it and open another one after the wait of the schedule.
  /// An attempt that was already replaced does nothing.
  void _attemptEnded(int generation) {
    if (generation != _generation) return;
    _generation++; // whatever else this attempt reports is stale now
    _stall?.cancel();
    _stall = null;
    _sub?.cancel();
    _sub = null;
    _client?.close();
    _client = null;
    _failures = MjpegReconnectPolicy.failuresAfter(_failures, gotFrame: _attemptGotFrame);
    _retry?.cancel();
    _retry = Timer(MjpegReconnectPolicy.delayFor(_failures), () {
      _retry = null;
      if (mounted) _start();
    });
  }

  /// Starts counting the silence of the attempt of [generation] again.
  void _armStall(int generation) {
    _stall?.cancel();
    _stall = Timer(MjpegReconnectPolicy.stallTimeout, () {
      _stall = null;
      if (mounted && generation == _generation) setState(() => _hasError = true);
      _attemptEnded(generation);
    });
  }

  Future<void> _start() async {
    _retry?.cancel();
    _retry = null;
    final generation = ++_generation;
    _attemptGotFrame = false;
    _armStall(generation);
    final client = (widget.clientFactory ?? createClient)();
    _client = client;
    var pending = BytesBuilder(copy: false);
    try {
      final request = http.Request('GET', Uri.parse(widget.url));
      if (widget.headers != null) request.headers.addAll(widget.headers!);
      final response = await client.send(request);
      if (generation != _generation) {
        client.close();
        return; // replaced while connecting: this answer belongs to nobody
      }
      if (response.statusCode != 200) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _reason = 'HTTP ${response.statusCode}';
          });
        }
        _attemptEnded(generation);
        return;
      }
      _sub = response.stream.listen(
        (chunk) {
          if (generation != _generation) return;
          _armStall(generation);
          pending.add(chunk);
          if (pending.length > mjpegMaxBufferBytes) {
            pending = BytesBuilder(copy: false); // never produced a frame end: start over
            return;
          }
          final bytes = pending.toBytes();
          final found = findLastJpegFrame(bytes);
          if (found == null) return;
          final frame = Uint8List.fromList(Uint8List.sublistView(bytes, found.start, found.end));
          pending = BytesBuilder(copy: false);
          if (found.end < bytes.length) pending.add(Uint8List.sublistView(bytes, found.end));
          _attemptGotFrame = true;
          if (mounted) {
            setState(() {
              _frame = frame;
              _hasError = false;
              _reason = null;
            });
          }
        },
        onError: (Object _) {
          if (mounted && generation == _generation) setState(() => _hasError = true);
          _attemptEnded(generation);
        },
        onDone: () {
          if (mounted && generation == _generation) setState(() => _hasError = true);
          _attemptEnded(generation);
        },
        cancelOnError: true,
      );
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _hasError = true);
      _attemptEnded(generation);
    }
  }

  void _stop() {
    _generation++;
    _retry?.cancel();
    _retry = null;
    _stall?.cancel();
    _stall = null;
    _sub?.cancel();
    _sub = null;
    _client?.close();
    _client = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_frame == null) {
      final l10n = AppLocalizations.of(context)!;
      return Center(
        child: _hasError
            ? Text(
                _reason == null ? l10n.cameraStreamUnavailable : l10n.errCameraUnavailable(_reason!),
                style: const TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              )
            : const CircularProgressIndicator(),
      );
    }
    return Image.memory(_frame!, gaplessPlayback: true, fit: BoxFit.contain);
  }
}
