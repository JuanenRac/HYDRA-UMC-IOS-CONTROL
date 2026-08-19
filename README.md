<p align="center">
  <img src="images/HYDRA_UMC_IOS_CONTROL_BANNER.jpg" alt="HYDRA-UMC iOS Control Banner" width="100%">
</p>

# 📱 HYDRA-UMC CONTROL (iOS)

A cross-platform Flutter app (Dart) that controls a robot on the [HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC) platform over Wi-Fi, speaking the exact same [`REMOTE_API.md`](https://github.com/JuanenRac/HYDRA-UMC-STUDIO/blob/main/docs/REMOTE_API.md) contract [HYDRA-UMC SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE) and [HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL) use - discovery, login, atomic per-robot commands, and live WebSocket sync against a running [HYDRA-UMC STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO) server.

## 🔀 Why Flutter, not native Swift

This app targets iOS/iPadOS, but it is built in **Flutter** rather than Swift/SwiftUI: the working environment for this repo is Windows-only, and a native Swift project can be *written* on Windows but never *compiled or run* there (Xcode and the iOS SDK are macOS-only). Flutter's own Windows desktop target lets this app be built, run, and tested for real on this machine - `flutter analyze` clean, `flutter build windows` succeeds, `flutter test` passes, and the built `.exe` launches and renders with no runtime errors - instead of writing thousands of lines of Swift blind, with no way to verify any of it until a Mac is available.

**This does not remove Apple's own restriction** - a real `.ipa` still requires Xcode on a Mac (or a macOS CI runner) to build and sign; nothing about the choice of framework changes that. What Flutter buys is the ability to verify every other line of this app's own logic (networking, state, UI) on this machine today, and to ship an identical codebase to iOS later with no rewrite.

## 🏗️ What's implemented

- **Login** (`lib/ui/login_screen.dart`, `lib/state/robot_view_model.dart`) - editable server IP/port fields plus `POST /api/login` against `admin`/`admin` (pre-filled - the default account every server in this ecosystem seeds on its own first-ever start; a server can also have additional lower-privilege "operator" accounts, created from Config > Users in the browser UI), session token persisted across launches via `shared_preferences`. A "Scan local network" button (`lib/network/discovery.dart`) finds servers without the user needing to already know the IP.
- **Network discovery** (`lib/network/discovery.dart`) - concurrent scan of `GET /api/hydra-info` across this device's own real local subnet(s), derived from `dart:io`'s `NetworkInterface.list()` rather than a single hardcoded guess, since a phone's LAN is just as likely to be `192.168.0.x` or `10.x.x.x` as `192.168.1.x`. Falls back to `192.168.1.x` only if interface enumeration itself comes back empty.
- **Atomic command sync** (`lib/state/robot_view_model.dart`'s own `_sendAtomicCommand()`) - every write (enable/disable/play/pause/stop/jog/valve/pump/speed/vision) uses the real `POST /api/robot/:id/command` endpoint, a small targeted payload rather than overwriting the whole settings tree, with correct combined-robot (`combinedWith`) propagation for the 5 commands that need it.
- **Live WebSocket sync** (`lib/network/hydra_websocket.dart`) - always attaches `?token=` to the connection URL (`server.ts`'s own `/ws` upgrade requires it unconditionally), handles both `"settings"` and `"delta"` broadcast types, auto-reconnects on drop.
- **Dashboard** (`lib/ui/dashboard_screen.dart`) - per-robot cards, reactive in real time via `Provider`'s own `ChangeNotifier`, LED convention (green pulsing = active, red solid = inactive) and combined-robot display (shown on the follower side only, resolved by id) matching HYDRA-UMC-STUDIO's own Dashboard Overview.
- **Manual Control** (`lib/ui/control_screen.dart`, `lib/ui/widgets/joystick_pad.dart`) - jog D-pad (with/without XY table target), speed/acceleration sliders, valve/pump toggles, and real long-press protection on E-STOP/STOP (a quick tap does nothing but a haptic + visual hint, only a genuine hold sends the command).
- **Camera** (`lib/ui/camera_screen.dart`, `lib/ui/widgets/mjpeg_view.dart`) - a small hand-rolled MJPEG stream parser (no third-party package), a clear "Camera Disabled" state instead of a silently blank feed, and a switch to turn a robot's vision system on/off directly from the server (`server.ts`'s `"vision"` atomic command).
- **3D View** (`lib/ui/three_d_screen.dart`) - embeds HYDRA-UMC-STUDIO's own real-time 3D viewport in a WebView (`?hideUI=true&robotId=&token=`), same approach as the Android app, for the same reason (gets the real, currently-shipping 3D scene for free). Falls back to an honest placeholder on platforms `webview_flutter` doesn't support (this repo's Windows desktop target, used for build verification).
- **System metrics** (`lib/state/robot_view_model.dart`) - `GET /api/system/metrics` polled every 5s, same cadence as the other 2 clients, shown in the Dashboard.

## 🚀 Building

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel). This repo is built/verified against Flutter 3.47.0. Only `windows/` and `ios/` are configured as platforms in this repo (no `android/`, `linux/`, `web/`, or `macos/` folders) - Windows exists so this app's own logic can be built and run without a Mac; iOS is the real target.

### Build scripts

```bash
./build.sh     # Git Bash / WSL - flutter pub get + flutter build windows
build.bat      # cmd.exe / PowerShell - flutter pub get + flutter build windows
```

Both produce `build/windows/x64/runner/Release/hydra_umc_control.exe`.

### Manual build

```bash
flutter pub get
flutter analyze          # static analysis - no compiler needed
flutter test             # widget tests
flutter build windows    # produces build/windows/x64/runner/Release/hydra_umc_control.exe
flutter run -d windows   # or -d <ios-device-id> from a Mac, or -d chrome for a quick web preview
```

**Building the real iOS `.ipa`** requires Xcode on macOS - from that machine: `flutter build ipa` (or open `ios/Runner.xcworkspace` in Xcode directly). This cannot be done from Windows; see "Why Flutter, not native Swift" above.

## 📂 Repository Structure

```text
HYDRA-UMC-IOS-CONTROL/
├── build.bat, build.sh              # flutter pub get + flutter build windows
├── lib/
│   ├── main.dart                    # App entry point, ChangeNotifierProvider + login gate
│   ├── models/
│   │   ├── server_info.dart         # Discovery/connection entry - mirrors ServerInfo in the other 2 clients
│   │   └── hydra_state.dart         # RobotView/ControllerView/HydraState - thin mutable views over the raw settings.json tree
│   ├── network/
│   │   ├── hydra_api_client.dart    # REST: login, settings, atomic robot command, system metrics
│   │   ├── hydra_websocket.dart     # /ws live sync client
│   │   ├── discovery.dart           # Concurrent scan of this device's own real local subnet(s) against GET /api/hydra-info
│   │   └── auth_prefs.dart          # Persisted connection + token (shared_preferences)
│   ├── state/
│   │   └── robot_view_model.dart    # Single ChangeNotifier every screen listens to
│   └── ui/
│       ├── login_screen.dart        # Host/port/user/pass fields + "Scan local network"
│       ├── main_screen.dart         # Bottom nav shell (Dashboard/Control/Camera/3D/Settings)
│       ├── dashboard_screen.dart    # Per-robot cards + system metrics bar
│       ├── control_screen.dart      # Jog/speed/valve/pump/playback controls
│       ├── camera_screen.dart       # MJPEG viewer + vision on/off switch
│       ├── three_d_screen.dart      # Embeds STUDIO's own 3D viewport via WebView
│       ├── settings_screen.dart     # Connection info + sign out
│       └── widgets/
│           ├── joystick_pad.dart     # Jog D-pad (deliberately not an analog stick, see file header)
│           ├── digital_readout.dart, status_led.dart
│           └── mjpeg_view.dart       # Hand-rolled MJPEG stream parser
├── ios/                              # Xcode project (build only from macOS)
├── windows/                          # Windows desktop target - build verification without a Mac
├── docs/ARCHITECTURE.md
├── test/widget_test.dart
└── images/
```

## 🔗 Related Projects

This project is part of a larger robotics ecosystem by the same author (JuanenRac / Electro Hobby 3D). Worth knowing about, since a request might actually be about one of these rather than this repository:

**HYDRA-UMC platform** — the multi-robot micro-factory cell
- **[HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC)** — the motherboard itself: Raspberry Pi CM5 host + dual-core STM32H745 real-time co-processor, orchestrating up to 8 distributed robot arms over CAN-OTA/SPI-OTA. Own hardware + firmware, GPL-3.0/CERN-OHL-S v2/CC BY-SA 4.0.
- **[HYDRA-UMC STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO)** — web-based control dashboard for HYDRA-UMC: multi-robot 3D visualization, kinematics/trajectory recording, CAN-OTA flashing and testing for the whole platform. React + Vite + Three.js.
- **[HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL)** — Android control app for HYDRA-UMC over Wi-Fi/Bluetooth. Real, working app - full remote-control feature set, JWT auth, encrypted credential storage.
- **HYDRA-UMC-IOS-CONTROL** *(this repository)* — iOS/iPadOS control app for HYDRA-UMC over Wi-Fi, built in Flutter (cross-platform, verifiable on Windows without a Mac; final `.ipa` packaging still needs Xcode). Real, working app - same feature set as the Android app.
- **[HYDRA-UMC-SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE)** — desktop (Python/PySide6) swarm command center: multi-controller network discovery, live bidirectional sync, real 3D robot viewport, Photoshop-style dockable workspace. Real and working, not a placeholder.
- **[HYDRA-UMC-EDITOR-URDF](https://github.com/JuanenRac/HYDRA-UMC-EDITOR-URDF)** — desktop (Python/PySide6) graphical URDF creator/editor for this project's own model catalog: pulls source files from GitHub or a local folder, validates DOF feasibility, edits color/scale/kinematics with a live 3D preview, and pushes the finished result to a running STUDIO server. Real and working, not a placeholder.
- **[HYDRA-UMC-DSI](https://github.com/JuanenRac/HYDRA-UMC-DSI)** — planned: a native touch UI for HYDRA-UMC's own 7" DSI touchscreen (1280×800) on the Compute Module 5, controlling this same server directly from the board. Not started yet.

**URTC platform** — the tool head controller every HYDRA-UMC robot arm carries
- **[URTC](https://github.com/JuanenRac/URTC)** — Universal Robot Tool Controller: STM32F303-based CAN bus tool head controller, 25 fully-implemented tool profiles, CAN-OTA firmware update.
- **[URTC Flasher](https://github.com/JuanenRac/URTC-FLASHER)** — desktop CAN-OTA + full-chip SWD/JTAG flashing tool for URTC boards (Windows/Linux).
- **[URTC Tester](https://github.com/JuanenRac/URTC-TESTER)** — desktop live CAN-bus diagnostic tool for URTC boards, one panel per tool profile (Windows/Linux).
- **[URTC Web Studio](https://github.com/JuanenRac/URTC-WEB-STUDIO)** — browser-based alternative to the 2 desktop tools above (Web Serial API + SLCAN), no local install needed.

---

## 👤 Author

**JuanenRac** (Electro Hobby 3D)
📧 electrohobby3d@gmail.com
📺 youtube.com/@electrohobby3d

---

## 📜 License

GNU General Public License v3.0 (GPL-3.0) - see [`LICENSE`](LICENSE).
