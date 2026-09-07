// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/widgets/mjpeg_view.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
//
// Minimal MJPEG stream viewer - a hand-rolled parser (buffers the streamed
// HTTP response, splits frames on real JPEG SOI/EOI markers 0xFFD8/0xFFD9)
// rather than a third-party package, same reasoning
// HYDRA-UMC-ANDROID-CONTROL's own ui/MjpegPlayer.kt uses its own native
// Canvas-based parser instead of a library: this server's own MJPEG
// multipart stream (server.ts's GET /api/camera/:id/stream) is simple
// enough that a small dependency-free parser is more honest about what it
// actually does than pulling in a package for it.
// =============================================================================

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../l10n/app_localizations.dart';

class MjpegView extends StatefulWidget {
  final String url;
  const MjpegView({super.key, required this.url});

  @override
  State<MjpegView> createState() => _MjpegViewState();
}

class _MjpegViewState extends State<MjpegView> {
  Uint8List? _frame;
  StreamSubscription<List<int>>? _sub;
  http.Client? _client;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant MjpegView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _stop();
      _frame = null;
      _hasError = false;
      _start();
    }
  }

  Future<void> _start() async {
    _client = http.Client();
    final buffer = BytesBuilder(copy: false);
    try {
      final response = await _client!.send(http.Request('GET', Uri.parse(widget.url)));
      _sub = response.stream.listen(
        (chunk) {
          buffer.add(chunk);
          _extractFrames(buffer);
        },
        onError: (Object _) {
          if (mounted) setState(() => _hasError = true);
        },
        onDone: () {
          if (mounted) setState(() => _hasError = true);
        },
        cancelOnError: true,
      );
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  void _extractFrames(BytesBuilder buffer) {
    final bytes = buffer.toBytes();
    // JPEG SOI (0xFFD8) ... EOI (0xFFD9) - find the LAST complete frame in
    // the buffer so a slow UI thread naturally drops stale frames instead
    // of queueing them.
    final start = _indexOfMarker(bytes, 0xFF, 0xD8);
    if (start < 0) return;
    final end = _indexOfMarker(bytes, 0xFF, 0xD9, from: start + 2);
    if (end < 0) return;
    final frame = Uint8List.sublistView(bytes, start, end + 2);
    if (mounted) {
      setState(() {
        _frame = Uint8List.fromList(frame);
        _hasError = false;
      });
    }
    buffer.clear();
    if (end + 2 < bytes.length) buffer.add(bytes.sublist(end + 2));
  }

  int _indexOfMarker(Uint8List bytes, int a, int b, {int from = 0}) {
    for (var i = from; i < bytes.length - 1; i++) {
      if (bytes[i] == a && bytes[i + 1] == b) return i;
    }
    return -1;
  }

  void _stop() {
    _sub?.cancel();
    _client?.close();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_frame == null) {
      return Center(
        child: _hasError
            ? Text(AppLocalizations.of(context)!.cameraStreamUnavailable, style: const TextStyle(color: Colors.grey))
            : const CircularProgressIndicator(),
      );
    }
    return Image.memory(_frame!, gaplessPlayback: true, fit: BoxFit.contain);
  }
}
