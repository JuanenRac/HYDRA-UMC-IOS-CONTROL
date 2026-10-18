// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/three_d_screen.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
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

import '../l10n/app_localizations.dart';
import '../state/robot_view_model.dart';

class ThreeDScreen extends StatefulWidget {
  /// False until the tab is first shown: the viewer is a whole web page
  /// (Three.js) and is not loaded at start-up for a tab nobody opened.
  final bool active;
  const ThreeDScreen({super.key, this.active = true});

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
    if (!vm.isLoggedIn) {
      // Signed out: the page keeps the session token in its own web storage
      // (STUDIO saves it from the address), outside the Keychain. Empty it.
      if (_controller != null) {
        _controller!.clearLocalStorage();
        _controller!.clearCache();
        _controller!.loadRequest(Uri.parse('about:blank'));
        _loadedUrl = null;
      }
      return const SizedBox.shrink();
    }
    if (!widget.active && _controller == null) return const SizedBox.shrink();

    if (server == null || robotId == null) {
      return Center(child: Text(AppLocalizations.of(context)!.threedNoRobotSelected, style: const TextStyle(color: Colors.grey)));
    }

    final supported = !kIsWeb && (Platform.isIOS || Platform.isAndroid);
    if (!supported) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            AppLocalizations.of(context)!.threedUnsupportedPlatform,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    // The scheme the client learned (https for a TLS server), and the query
    // built as a query: the token and the id are encoded, not pasted.
    final base = Uri.parse(vm.serverBaseUrl ?? server.baseUrl);
    final url = base.replace(
      path: '/',
      queryParameters: {'hideUI': 'true', 'robotId': '$robotId', 'token': token ?? ''},
    ).toString();
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
