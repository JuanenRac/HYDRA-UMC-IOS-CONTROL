<p align="center">
  <img src="images/HYDRA_UMC_IOS_CONTROL_BANNER.jpg" alt="HYDRA-UMC iOS Control Banner" width="100%">
</p>

# 📱 HYDRA-UMC CONTROL (iOS)

A cross-platform Flutter app (Dart) that controls a robot on the [HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC) platform over Wi-Fi, speaking the exact same [`REMOTE_API.md`](https://github.com/JuanenRac/HYDRA-UMC-STUDIO/blob/main/docs/REMOTE_API.md) contract [HYDRA-UMC SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE) and [HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL) use - discovery, login, atomic per-robot commands, and live WebSocket sync against a running [HYDRA-UMC STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO) server.

## 🔀 Framework pivot (19 August 2026)

This project started as a native Swift/SwiftUI Package (scaffolding only, 15 August 2026). Rebuilt in **Flutter** on 19 August 2026 by explicit owner choice: the working environment here is Windows-only, and a native Swift project can be *written* but never *compiled or run* there (Xcode/the iOS SDK are macOS-only). Flutter's own Windows and Android targets let this app be built and actually run on this machine for real verification - confirmed end-to-end in this repo: `flutter analyze` clean, `flutter build windows` succeeds, `flutter test` passes, and the built `.exe` launches and renders with no runtime errors.

**This does not remove Apple's own restriction** - a real `.ipa` still requires Xcode on a Mac (or a macOS CI runner) to build and sign; nothing about switching frameworks changes that. What Flutter buys is the ability to verify every other line of this app's own logic (networking, state, UI) without needing one, rather than writing ~2,700 lines of Dart across 15 files blind. The old Swift skeleton was archived, not deleted - see `SONNET/_papelera/HYDRA-UMC-IOS-CONTROL_swift_skeleton_2026-08-19/` in this ecosystem's own private tracking repo.

## 🏗️ What's implemented

- **Login** (`lib/ui/login_screen.dart`, `lib/state/robot_view_model.dart`) - `POST /api/login` against `demo`/`demo` (pre-filled, the same hardcoded account every server in this ecosystem ships with), session token persisted across launches via `shared_preferences`.
- **Atomic command sync** (`lib/state/robot_view_model.dart`'s own `_sendAtomicCommand()`) - every write (enable/disable/play/pause/stop/jog/valve/pump/speed/vision) uses the real `POST /api/robot/:id/command` endpoint from day one, with correct combined-robot (`combinedWith`) propagation for the 5 commands that need it - built this way from the start rather than the heavier "always POST the whole settings tree" approach the Android app shipped first and had to migrate away from the same day.
- **Live WebSocket sync** (`lib/network/hydra_websocket.dart`) - `?token=` in the connection URL from day one (server.ts's `/ws` upgrade requires it unconditionally - both other clients in this ecosystem had this missing and had to be fixed the same day), handles both `"settings"` and `"delta"` broadcast types, auto-reconnects on drop.
- **Dashboard** (`lib/ui/dashboard_screen.dart`) - per-robot cards, reactive in real time via `Provider`'s own `ChangeNotifier`, LED convention (green pulsing = active, red solid = inactive) and combined-robot display (shown on the follower side only, resolved by id) matching what HYDRA-UMC-STUDIO's own Dashboard Overview settled on the same day.
- **Manual Control** (`lib/ui/control_screen.dart`, `lib/ui/widgets/joystick_pad.dart`) - jog D-pad (with/without XY table target), speed/acceleration sliders, valve/pump toggles, and **real long-press protection** on E-STOP/STOP (a quick tap does nothing but a haptic + visual hint, only a genuine hold sends the command) - built correctly from day one rather than claimed-but-missing, as it was in HYDRA-UMC-ANDROID-CONTROL's own README before that gap was found and fixed the same day.
- **Camera** (`lib/ui/camera_screen.dart`, `lib/ui/widgets/mjpeg_view.dart`) - a small hand-rolled MJPEG stream parser (no third-party package), a clear "Camera Disabled" state instead of a silently blank feed, and a switch to turn a robot's vision system on/off directly from the server (`server.ts`'s new `"vision"` atomic command, added 2026-08-19).
- **3D View** (`lib/ui/three_d_screen.dart`) - embeds HYDRA-UMC-STUDIO's own real-time 3D viewport in a WebView (`?hideUI=true&robotId=&token=`), same approach as the Android app, for the same reason (gets the real, currently-shipping 3D scene for free). Falls back to an honest placeholder on platforms `webview_flutter` doesn't support (this session's own Windows verification target).
- **System metrics** (`lib/state/robot_view_model.dart`) - `GET /api/system/metrics` polled every 5s, same cadence as the other 2 clients, shown in the Dashboard.

## 🚀 Building

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel). This repo was built/verified against Flutter 3.47.0.

```bash
flutter pub get
flutter analyze          # static analysis - no compiler needed
flutter test             # widget tests
flutter run -d windows   # or -d <ios-device-id> from a Mac, or -d chrome for a quick web preview
```

**Building the real iOS `.ipa`** requires Xcode on macOS - from that machine: `flutter build ipa` (or open `ios/Runner.xcworkspace` in Xcode directly). This cannot be done from Windows; see the framework pivot note above.

## 📂 Repository Structure

```text
HYDRA-UMC-IOS-CONTROL/
├── lib/
│   ├── main.dart                    # App entry point, ChangeNotifierProvider + login gate
│   ├── models/
│   │   ├── server_info.dart         # Discovery/connection entry - mirrors ServerInfo in the other 2 clients
│   │   └── hydra_state.dart         # RobotView/ControllerView/HydraState - thin mutable views over the raw settings.json tree
│   ├── network/
│   │   ├── hydra_api_client.dart    # REST: login, settings, atomic robot command, system metrics
│   │   ├── hydra_websocket.dart     # /ws live sync client
│   │   ├── discovery.dart           # Concurrent subnet scan against GET /api/hydra-info
│   │   └── auth_prefs.dart          # Persisted connection + token (shared_preferences)
│   ├── state/
│   │   └── robot_view_model.dart    # Single ChangeNotifier every screen listens to
│   └── ui/
│       ├── login_screen.dart, main_screen.dart, dashboard_screen.dart,
│       │   control_screen.dart, camera_screen.dart, three_d_screen.dart, settings_screen.dart
│       └── widgets/
│           ├── joystick_pad.dart     # Jog D-pad (deliberately not an analog stick, see file header)
│           ├── digital_readout.dart, status_led.dart
│           └── mjpeg_view.dart       # Hand-rolled MJPEG stream parser
├── ios/                              # Xcode project (build only from macOS)
├── windows/                          # This session's own build-verification target
├── docs/ARCHITECTURE.md
└── images/
```

## 🔗 Related Projects

Direct Flutter counterpart to [HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL) (native Kotlin/Compose, no code shared between the two) - both speak the exact same [`REMOTE_API.md`](https://github.com/JuanenRac/HYDRA-UMC-STUDIO/blob/main/docs/REMOTE_API.md) contract as [HYDRA-UMC SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE), served by [HYDRA-UMC STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO), which in turn is the human-facing side of [HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC) itself.

---

## 👤 Author

**JuanenRac** (Electro Hobby 3D)
📧 electrohobby3d@gmail.com
📺 youtube.com/@electrohobby3d

---

## 📜 License

GNU General Public License v3.0 (GPL-3.0) - see [`LICENSE`](LICENSE).
