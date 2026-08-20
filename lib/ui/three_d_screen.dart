// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/three_d_screen.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
//
// Embeds HYDRA-UMC-STUDIO's own real-time 3D viewport in a WebView
// (?hideUI=true&robotId=&token=) - same approach
// HYDRA-UMC-ANDROID-CONTROL's own ui/ThreeDScreen.kt uses, for the same
// reason: gets the real, currently-shipping STUDIO 3D scene (every real
// robot mesh/kinematics) for free instead of reimplementing it natively.
// webview_flutter only ships an Android/iOS(+macOS) platform
// implementation - guarded behind Platform.isIOS/isAndroid so this screen
// degrades to an honest placeholder rather than crashing on platforms it
// doesn't support (this app's primary target is iOS; the Windows desktop
// target exists so this app's own logic can be built and run on a
// Windows dev machine without needing a Mac, but 3D falls back to a
// placeholder there since webview_flutter has no Windows implementation).
// =============================================================================

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../state/robot_view_model.dart';

class ThreeDScreen extends StatefulWidget {
  const ThreeDScreen({super.key});

  @override
  State<ThreeDScreen> createState() => _ThreeDScreenState();
}

class _ThreeDScreenState extends State<ThreeDScreen> {
  WebViewController? _controller;
  String? _loadedUrl;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RobotViewModel>();
    final server = vm.activeServer;
    final robotId = vm.selectedRobotId;
    final token = vm.apiClient?.authToken;

    if (server == null || robotId == null) {
      return const Center(child: Text('No robot selected', style: TextStyle(color: Colors.grey)));
    }

    final supported = !kIsWeb && (Platform.isIOS || Platform.isAndroid);
    if (!supported) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '3D view requires iOS or Android (WebView) - not available on this verification platform.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final url = '${server.baseUrl}/?hideUI=true&robotId=$robotId&token=${token ?? ''}';
    // The controller is created once and reused, and loadRequest() only
    // fires when the URL actually changes (a different robot/server/token) -
    // build() itself runs on every RobotViewModel.notifyListeners() call
    // (every WS "settings"/"delta" broadcast, the 5-second system-metrics
    // poll, connectionStatus flips, ...), so a fresh WebViewController +
    // loadRequest() on every build reloaded the embedded 3D scene from
    // scratch several times a minute - resetting camera orbit/zoom and
    // flickering the view - instead of leaving one live WebView running.
    _controller ??= WebViewController()..setJavaScriptMode(JavaScriptMode.unrestricted);
    if (_loadedUrl != url) {
      _loadedUrl = url;
      _controller!.loadRequest(Uri.parse(url));
    }

    return WebViewWidget(controller: _controller!);
  }
}
