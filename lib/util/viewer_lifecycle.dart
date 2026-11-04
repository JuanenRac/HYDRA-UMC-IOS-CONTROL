// =============================================================================
// HYDRA-UMC-IOS-CONTROL - When the embedded 3D viewer may keep running
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
// =============================================================================

import 'package:flutter/widgets.dart' show AppLifecycleState;

/// The embedded viewer is a whole web page with its own socket and render loop. iOS keeps a
/// WebView alive in the background and only suspends it later, on its own schedule: the app
/// loads a blank page as soon as it is really backgrounded and loads the viewer again on
/// return. `inactive` (a system alert, the app switcher) is momentary and keeps it.
class ViewerLifecycle {
  const ViewerLifecycle._();

  /// True when the viewer must be stopped in [state].
  static bool mustStop(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        return true;
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        return false;
    }
  }
}
