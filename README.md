<!-- =============================================================================
HYDRA-UMC-IOS-CONTROL - iOS and iPadOS operator console for a HYDRA-UMC server, written in Flutter
Copyright (C) JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
GPL-3.0-or-later - see LICENSE
============================================================================= -->

<p align="center">
  <img src="images/HYDRA_UMC_BANNER.svg" alt="HYDRA-UMC-IOS-CONTROL banner" width="100%">
</p>

# 🍎 HYDRA-UMC-IOS-CONTROL

<p align="center">🇺🇸 <b>English</b> | <a href="README_spa.md">🇪🇸 Español</a> | <a href="README_fra.md">🇫🇷 Français</a> | <a href="README_ita.md">🇮🇹 Italiano</a> | <a href="README_deu.md">🇩🇪 Deutsch</a> | <a href="README_zho.md">🇨🇳 简体中文</a> | <a href="README_jpn.md">🇯🇵 日本語</a> | <a href="README_por.md">🇵🇹 Português</a></p>

### Your HYDRA-UMC robots on an iPhone or iPad: find the server, move and watch the robots, and stop everything with one red button.

<p align="center">
  <img src="https://img.shields.io/badge/License-GPL%203.0--or--later-blue.svg" alt="GPL 3.0 or later">
  <img src="https://img.shields.io/badge/Framework-Flutter-02569B.svg" alt="Framework">
  <img src="https://img.shields.io/badge/Language-Dart-0175C2.svg" alt="Language">
  <img src="https://img.shields.io/badge/Platform-iOS-000000.svg" alt="Platform">
  <img src="https://img.shields.io/badge/Tests-254%20passing-2ea44f.svg" alt="Tests">
  <img src="https://img.shields.io/badge/Version-0.2.8-0f6cbd.svg" alt="Version">
  <img src="https://img.shields.io/badge/Maturity-functional-0F6CBD.svg" alt="Maturity">
</p>

---

A cross-platform Flutter app (Dart) that controls a robot on the [HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC) platform over Wi-Fi, speaking the exact same [`REMOTE_API.md`](https://github.com/JuanenRac/HYDRA-UMC-SERVER/blob/main/docs/REMOTE_API.md) contract [HYDRA-UMC SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE) and [HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL) use - discovery, login, atomic per-robot commands, and live WebSocket sync against a running [HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER) instance (the headless backend split out of HYDRA-UMC STUDIO's own process - STUDIO is a pure frontend client of it now, same as this app).

> **Safety and security status:** this ecosystem is not a certified safety system. There is no hardware E-STOP path, no firmware-enforced limits or interlocks and no verified motion command yet; firmware images are checked with CRC-32 and an Ed25519 signature, and a release build refuses the published development keys (the tool heads and expansion boards behind the relay still run URTC bootloaders, which take a shared-key HMAC-SHA256 instead of a signature); TLS and mutual TLS are optional and off by default; no custom board has been populated or tested yet. Read the [security baseline](https://github.com/JuanenRac/HYDRA-UMC-DOCS/blob/main/docs/SECURITY_BASELINE.md) and the [threat model](https://github.com/JuanenRac/HYDRA-UMC-DOCS/blob/main/docs/THREAT_MODEL.md) before relying on any statement here for the safety of a person.

---

## 📋 At a glance

| | |
|---|---|
| Version | `0.2.8` |
| Maturity | Functional |
| Tests | 254 (`flutter test`) |
| Stack | Flutter 3.x / Dart |
| Target | An iPhone or iPad |
| On real hardware | Not yet: no run on real hardware is recorded for this version |

**Jump to:** [Overview](#-overview) · [Architecture](#-architecture) · [Features](#-features) · [Security & Safety](#-security--safety) · [Interfaces](#-interfaces) · [Configuration](#-configuration) · [Quick start](#-quick-start) · [Testing](#-testing) · [Troubleshooting](#-troubleshooting) · [Repository Structure](#-repository-structure) · [Related Projects](#-related-projects)

## 🚦 Project status

Each line is one part of this repository and the light says how far it is today. It is written from what the repository can show (tests, builds, runs), not from what is planned.

🟢 Done and verified · 🟡 Works, with known limits · 🟠 Partly done or not verified yet · 🔴 Not done or not working

| Area | State | What it means here |
|---|---|---|
| Software | 🟡 | Works for its main purpose; the honesty check above lists what is still missing |
| Tests | 🟢 | 254 automated tests, run on every change |
| Real hardware | 🔴 | Not yet: no run on real hardware is recorded for this version |
| Documentation | 🟢 | README in eight languages, checked against the manifest on every change |

## 🎯 Overview

Screens of the app: **login** (server address, account, a scan of the local network), **dashboard** (a card per robot with its live LED and the health of the compute module), **control** (jog pad, speed, valves and pumps, reservation of the robot, PLAY with an optional question first), **camera** (live MJPEG), **3D view** (the real STUDIO scene), **telemetry** (a terminal-style log) and **settings** (language, biometric lock, switches). A red **STOP** button sits in the app bar of every tab.

## 🧩 Role in HYDRA-UMC

**HYDRA-UMC-IOS-CONTROL** is the operator console of HYDRA-UMC for iPhone and iPad. It is written in Flutter so that its logic can be built, run and tested on Windows; the iOS build itself still needs Xcode on a Mac. It finds a HYDRA-UMC-SERVER on the local network, signs in, shows and moves the robots, watches their cameras and a 3D view, and stops everything with one tap, speaking the same remote contract as the SUITE and the Android app. It is not a safety device.

## 🏛️ Architecture

<p align="center">
  <img src="images/architecture.svg" alt="HYDRA-UMC-IOS-CONTROL architecture" width="100%">
</p>

### Why Flutter, not native Swift

This app targets iOS/iPadOS, but it is built in **Flutter** rather than Swift/SwiftUI: the working environment for this repo is Windows-only, and a native Swift project can be *written* on Windows but never *compiled or run* there (Xcode and the iOS SDK are macOS-only). Flutter's own Windows desktop target lets this app be built, run, and tested for real on this machine - `flutter analyze` clean, `flutter build windows` succeeds, `flutter test` passes, and the built `.exe` launches and renders with no runtime errors - instead of writing thousands of lines of Swift blind, with no way to verify any of it until a Mac is available.

**This does not remove Apple's own restriction** - a real `.ipa` still requires Xcode on a Mac (or a macOS CI runner) to build and sign; nothing about the choice of framework changes that. What Flutter buys is the ability to verify every other line of this app's own logic (networking, state, UI) on this machine today, and to ship an identical codebase to iOS later with no rewrite.

## ✨ Features

- **Login** (`lib/ui/login_screen.dart`, `lib/state/robot_view_model.dart`) - editable server IP/port and operator credential fields plus `POST /api/login`; no account or password is pre-filled. A production server requires explicitly configured bootstrap credentials for its first administrator, and additional lower-privilege "operator" accounts can be created from Config > Users in the browser UI. The session token persists across launches in the iOS Keychain (`flutter_secure_storage`); the host and port are kept with `shared_preferences`. A "Scan local network" button (`lib/network/discovery.dart`) finds servers without the user needing to already know the IP.
- **Network discovery** (`lib/network/discovery.dart`) - two independent paths run at once from the "Scan local network" sheet: real mDNS/Bonjour (`discoverMdns()`, queries the `_hydra._tcp.local` service `server.ts` publishes via the `multicast_dns` package - this app is the first of the ecosystem's 3 remote clients to add it) plus a concurrent brute-force scan of `GET /api/hydra-info` across this device's own real local subnet(s) (`scanSubnets()`, derived from `dart:io`'s `NetworkInterface.list()` rather than a single hardcoded guess, since a phone's LAN is just as likely to be `192.168.0.x` or `10.x.x.x` as `192.168.1.x`, falling back to `192.168.1.x` only if interface enumeration itself comes back empty). mDNS failing quietly on an unentitled iOS build is expected (Apple's own Multicast Networking entitlement isn't granted by a plain `flutter build ios`) - the subnet scan keeps working independently either way.
- **Biometric login gate** (`lib/network/biometric_helper.dart`, `lib/ui/biometric_gate_screen.dart`) - Face ID/Touch ID/Windows Hello via `package:local_auth`, an optional `Settings` toggle that gates restoring an already-valid saved session on launch (this app never stores a raw password, only a bearer token - adapted from HYDRA-UMC-ANDROID-CONTROL's own password-refill design to that difference).
- **Atomic command sync** (`lib/state/robot_view_model.dart`'s own `_sendAtomicCommand()`) - every write (play/pause/stop/jog/valve/pump/speed/vision) uses the real `POST /api/robot/:id/command` endpoint, a small targeted payload rather than overwriting the whole settings tree, with correct combined-robot (`combinedWith`) propagation for the 5 commands that need it.
- **Live WebSocket sync** (`lib/network/hydra_websocket.dart`) - sends the token as the `hydra.bearer` subprotocol and never in the connection URL (`server.ts` refuses `/ws?token=` by default), handles both `"settings"` and `"delta"` broadcast types, auto-reconnects on drop.
- **Dashboard** (`lib/ui/dashboard_screen.dart`) - per-robot cards, reactive in real time via `Provider`'s own `ChangeNotifier`, LED convention (green pulsing = active, red solid = inactive) and combined-robot display (shown on the follower side only, resolved by id) matching HYDRA-UMC-STUDIO's own Dashboard Overview.
- **Manual Control** (`lib/ui/control_screen.dart`, `lib/ui/widgets/joystick_pad.dart`) - jog D-pad (with/without XY table target), speed/acceleration sliders, valve/pump toggles, and the global **STOP** (`lib/ui/widgets/stop_all.dart`): one tap, no long press and no confirmation, it stops every robot (`POST /api/stop-all`) and sits in the app bar of every tab, the Control tab included. The answer is shown robot by robot (a warning when a robot failed or the stop was not saved; robots reserved by someone else are marked), a network error is retried once, a server over its rate limit or without that route is answered with the per-robot stop, and when nothing answers a persistent "STOP not confirmed" banner stays until a later STOP gets an answer. The round per-robot stop keeps its long-press protection.
- **Reservations and safety limits** (`lib/ui/widgets/access_panel.dart`, `lib/models/access.dart`, `lib/network/hydra_api_client.dart`, `lib/state/robot_view_model.dart`) - The Control screen shows who holds the selected robot (nobody, this device, the same account on another device, or another account) and offers **Reserve** and **Release**, plus the list of every reservation of the server (`GET /api/claims`). The device keeps one controller id for the installation and sends it with every reserve, release, jog-arm and command (body and `X-Controller-Id` header), so a reservation belongs to the account and to this device, not to the whole account. The refusals of the server are told apart: reserved by another account, by your account on another device or window, controller id required, and jog not armed. The limits of the robot's model are read from `GET /api/safety-limits`: a jog step above the limit is not sent, and the server's warnings are shown. When the administrator requires it, an **Arm jog** button (with a countdown) must be pressed before the joystick moves the robot; the arming ends by itself, with STOP, or on release. Reservations are optional: a robot nobody reserved is commanded as before. For an **administrator** only, a **Take control** button appears on a robot someone else holds; it asks for confirmation and then reserves the robot with `force: true` (the server accepts that from administrators only and checks the role again). Writes are conditional: each one carries the revision of the robot this app last saw (`If-Match`, `lib/models/contract_v2.dart`), and when someone else changed the robot in between the server answers 412, nothing is applied, the robot is read again and the message says so (Standard checks reservations, the table and one-off commands; Strict checks everything but STOP; Off checks nothing; the choice is in the list of reservations; STOP is never checked). The XY table jog is one atomic `table` command (an older server gets the jogs it understands), the server pushes the reservations over the WebSocket so the Control screen stops polling while they arrive, and administrators read the audit record (`lib/ui/widgets/audit_dialog.dart`) with its SHA-256 chain verified twice, by the server and on the device, and can copy its lines as `.jsonl`.
- **Optional switches** - two switches, both off by default: *Block commands on saved data* (Settings) holds back every command except STOP while the screen shows the saved copy of the robot state instead of the live one, and *Do not scan mobile-data or VPN networks* (login screen) leaves those interfaces out of the subnet scan. The jog D-pad buttons are at least 44 pt and are announced by VoiceOver with their axis and direction; the camera picture is closed while the app is in the background.
- **Ask before PLAY** - on by default, turned off in Settings: before a trajectory starts the app shows the robot, its recorded points, the speed and who has it reserved (a robot reserved by someone else says the server will refuse the command). A robot that is already playing is not asked again. The choice is kept.
- **Camera** (`lib/ui/camera_screen.dart`, `lib/ui/widgets/mjpeg_view.dart`) - a small hand-rolled MJPEG stream parser (no third-party package), a clear "Camera Disabled" state instead of a silently blank feed, and a switch to turn a robot's vision system on/off directly from the server (`server.ts`'s `"vision"` atomic command).
- **3D View** (`lib/ui/three_d_screen.dart`) - embeds HYDRA-UMC-STUDIO's own real-time 3D viewport in a WebView (`?hideUI=true&robotId=#token=`), same approach as the Android app, for the same reason (gets the real, currently-shipping 3D scene for free). Falls back to an honest placeholder on platforms `webview_flutter` doesn't support (this repo's Windows desktop target, used for build verification).
- **System metrics** (`lib/state/robot_view_model.dart`) - `GET /api/system/metrics` polled every 5s, same cadence as the other 2 clients, shown in the Dashboard.
- **8-language UI** (`lib/l10n/`, standard `flutter gen-l10n` pipeline) - English, Spanish, French, German, Italian, Japanese, Chinese and Portuguese, matching every other client in this ecosystem. A persisted `Settings > Language` override defaults to the OS locale; `RobotViewModel.lastError` is a typed `HydraError` rather than pre-formatted English text, so business-logic error messages (login/connection/command failures) localize correctly too, not just static screen chrome.
- **Offline state cache** (`lib/network/state_cache.dart`) - the last known settings tree persists to disk (debounced 1s) alongside the real instant it was saved, so the Dashboard/Control screens show real, if possibly stale, robot data immediately on launch instead of an empty state while the live `connect()` round-trip is still in flight. A real, visible banner (not just a silent guess) says "showing cached data from HH:mm" for as long as that stays true. Superseded by the real fetch the instant it succeeds.
- **Telemetry** (`lib/ui/telemetry_screen.dart`) - a terminal-style, newest-first log of real connection/login/command lifecycle events, capped at 50 entries, with a clear-log action - same "Matrix Green" convention as HYDRA-UMC-ANDROID-CONTROL's own Telemetry tab.
- **In-App Voice Assistant** (`lib/ui/voice_assistant_dialog.dart`) - a mic icon in the app bar opens a dialog to type a question or an order, sent to `HYDRA-UMC-VOICE-UI` through the same real `POST /api/voice/turn` Server route HYDRA-UMC-ANDROID-CONTROL's own in-app voice button and paired-Watch relay use. Never uploads audio - text input only for now, since on-device speech recognition needs the native iOS Speech framework this Windows-only development environment cannot build or verify against a real device/Xcode. A reply never invokes a robot command directly.

## 🔒 Security & Safety

| Threat | Defence | Where |
|---|---|---|
| A token stolen from the phone | The token, the user name and the refresh token are kept with `flutter_secure_storage` (the iOS Keychain); only the host, the port and the preferences go to `shared_preferences`; the app never stores a raw password | `network/auth_prefs.dart` |
| Credentials in the saved copy of the state | The copy of the last state that is written to disk is stripped of the keys `ipUsername` and `ipPassword` at any depth, and it is erased at sign-out | `network/state_cache.dart` |
| The token in a log or in the address of the WebSocket | The token goes in the `hydra.bearer` sub-protocol of the WebSocket and never in its address; the embedded 3D view gets it in the address fragment (`#token=`), which is not sent to the server; a test checks both | `network/hydra_websocket.dart`, `util/viewer_url.dart` |
| Someone holding the unlocked phone | An optional biometric lock (Face ID, Touch ID) gates restoring a saved session on launch; the camera picture is closed while the app is in the background | `network/biometric_helper.dart`, `ui/biometric_gate_screen.dart` |
| A robot moved by two people, a PLAY pressed by mistake, or a stop that does not arrive | The robot is reserved before it is jogged and the screen says who holds it; PLAY asks first by default and shows the robot, its points, the speed and who has it reserved; the global STOP is retried once, falls back to one stop per robot, and keeps a persistent "STOP not confirmed" banner if nothing answered | `models/access.dart`, `util/play_confirmation.dart`, `ui/widgets/stop_all.dart` |

**What it never does:** replace a physical emergency stop, or encrypt the traffic by itself: the app tries HTTPS once when a plain HTTP probe gets no answer, and it has no certificate pinning and no guard against plain traffic outside the local network. The STOP is the server's software stop.

## 🔌 Interfaces

| Topic or route | What it carries |
|---|---|
| `POST /api/login`, `/api/logout`, `/api/refresh` | sign in, sign out and renew the session |
| `GET /api/hydra-info` | tells a real server apart; used by the subnet scan and by the manual address, with one retry over HTTPS |
| `GET /api/settings`, `/api/system/metrics`, `/api/safety-limits`, `/api/claims` | the state of the robots, the compute module (every 5 s), the safety limits of each model and the reservations |
| `POST /api/robot/{id}/command`, `/claim`, `/release`, jog arming | one small command for one robot, its reservation and the arming of a jog, with conditional writes by robot revision |
| `POST /api/stop-all` | the global STOP: every robot, answered robot by robot |
| `GET /api/audit`, `POST /api/voice/turn`, `GET /api/camera/{id}/stream` | the audit record (administrators, with its own SHA-256 chain check), a typed voice turn, and the MJPEG stream of a camera |
| WebSocket `hydra.bearer`, mDNS `_hydra._tcp.local` | live state changes (`settings` and `delta` messages, reconnect after 3 s growing to 30 s, a ping every 20 s) and the Bonjour announcement of the server |

## ⚙️ Configuration

The app has no configuration file: everything is set on screen and stored on the device. Defaults come from the code.

| Variable | Default | What it sets |
|---|---|---|
| Settings > Ask before PLAY | on | shows the robot, its points, the speed and who has it reserved before a trajectory starts |
| Settings > Block commands on saved data | off | holds back every command except STOP while the screen shows the saved copy of the state instead of the live one |
| Login > Do not scan mobile-data or VPN networks | off | leaves those interfaces out of the subnet scan (32 hosts at a time, port 3000 unless you type another) |
| Settings > Biometric lock | off | asks for Face ID or Touch ID before a saved session is restored on launch |
| Settings > Language | the system language | one of the eight languages of the app (`lib/l10n/`), kept across launches |

## 🚀 Quick start

Requires the stable Flutter SDK (Dart 3.13 or newer). Windows runs the logic and the tests; a real iPhone build needs Xcode on a Mac.

```bash
flutter pub get                  # downloads the packages
flutter test                     # runs the unit tests on this machine
./build-test.sh                  # non-mutating build check (build-test.bat on Windows)
flutter build ios --no-codesign  # a real iOS build; only on a Mac with Xcode
```

## 🧪 Testing

254 automated tests run with `flutter test`. They need no hardware and nothing outside this machine.

The CI runs `HYDRA_UMC_CI=1 python tools/ci_validate.py`, which checks the manifest, the documents, the eight READMEs and the pictures.

## 🏗️ Build & Release

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel). This repo is built/verified against Flutter 3.47.0. Only `windows/` and `ios/` are configured as platforms in this repo (no `android/`, `linux/`, `web/`, or `macos/` folders) - Windows exists so this app's own logic can be built and run without a Mac; iOS is the real target.

### Build scripts

```bash
./build.sh     # Git Bash / WSL - flutter pub get + flutter build windows
build.bat      # cmd.exe / PowerShell - flutter pub get + flutter build windows
```

Both produce `build/windows/x64/runner/Release/hydra_umc_control.exe`, and neither changes the app's version - see [Versioning](#versioning) below.

### Manual build

```bash
flutter pub get
flutter analyze          # static analysis - no compiler needed
flutter test             # widget tests
dart run tool/bump_version.dart  # bump the version, same as build.sh/build.bat do
flutter build windows    # produces build/windows/x64/runner/Release/hydra_umc_control.exe
flutter run -d windows   # or -d <ios-device-id> from a Mac
```

**Building the real iOS `.ipa`** requires Xcode on macOS - from that machine: `flutter build ipa` (or open `ios/Runner.xcworkspace` in Xcode directly). This cannot be done from Windows; see "Why Flutter, not native Swift" above.

### Versioning

This repo follows an ecosystem-wide policy: building never changes the version. The explicit bump command (`python tools/hydra_project_tool.py bump`) runs `tool/bump_version.dart`, which applies:

- **Build number** (the part after `+`): a plain monotonic counter, +1 on
  every build, no carry.

The same script regenerates `lib/app_version.dart` (generated, not
hand-edited - a plain `const` file, not a new runtime dependency like
`package_info_plus`), which the app reads at runtime to show its own
version on the **Settings** screen. See [CHANGELOG.md](CHANGELOG.md) for
the version history.

## 🩺 Troubleshooting

| You see | Because | Do |
|---|---|---|
| "Session not authorized - sign in again" | The server refused the token (the WebSocket was closed with code 1008) or it expired | Sign in again |
| "STOP not confirmed by the server" | Nothing answered the global STOP within its short time limit, or the server could not save the stopped state | Press it again; if the banner stays, use the physical emergency stop |
| The robot is reserved by another account, or by your account on another device | A reservation belongs to the account and to the device (one controller id per installation) | Use that device, or release the reservation there |
| "Showing cached data from HH:mm" | The server is out of reach and the screen shows the saved copy of the last state; with Block commands on saved data on, every command but STOP is held back | Check the server and the Wi-Fi; the screen goes live again by itself when the connection returns |
| "Jog refused: the step is above the limit" | The step is above the limit that the server sets for this robot model (`GET /api/safety-limits`) | Use a smaller step; nothing was sent |
| "Scan local network" finds no server | On a real iPhone Bonjour needs an entitlement that a plain build does not carry, and the scan can leave out mobile-data and VPN networks | Join the same Wi-Fi as the server, or type its address and port by hand |

## 📂 Repository Structure

<p align="center">
  <img src="images/repository-structure.svg" alt="Repository structure of HYDRA-UMC-IOS-CONTROL" width="100%">
</p>

<details>
<summary>Text version of the tree</summary>

```text
HYDRA-UMC-IOS-CONTROL/
├── lib/                                                              source code
│   ├── main.dart                                                     App entry point, ChangeNotifierProvider + login gate
│   ├── app_version.dart                                              GENERATED - regenerated by bump_manifest_version.py, do not hand-edit
│   ├── models/                                                       data models and pure rules
│   ├── network/                                                      REST client, WebSocket and discovery
│   ├── state/                                                        the state every screen listens to
│   ├── l10n/                                                         Real generated localizations (8 languages) - see l10n.yaml at repo root
│   ├── util/                                                         Helpers without a screen of their own
│   └── ui/                                                           screens and widgets
├── ios/                                                              Xcode project (build only from macOS)
├── windows/                                                          Windows desktop target - build verification without a Mac
├── tools/                                                            project tools and CI checks
├── test/                                                             the unit tests of the logic
├── images/                                                           banner and the pictures of the README
├── .github/                                                          CI workflow and issue templates
├── build.bat / build.sh                                              flutter pub get, then flutter build windows; never changes the version
├── docs/ARCHITECTURE.md                                              architecture of the project
├── pubspec.yaml / pubspec.lock / l10n.yaml / analysis_options.yaml   The Flutter package definition and its locked versions, the settings of the l10n generator and the lint rules
├── CHANGELOG.md                                                      what changed in each version
├── build-test.sh                                                     non-mutating build check
├── bump_manifest_version.py                                          syncs the manifest version
├── hydra-umc.project.json                                            manifest: version, maturity, family
└── test.sh                                                           non-mutating build check (flutter test runs the unit tests)
```

</details>

## 🗺️ Roadmap & Known limits

There is no iPhone or iPad build in the CI: `flutter build ios` needs Xcode on a Mac, so the app has been run and tested on Windows only. Bonjour discovery needs an entitlement that a plain build does not carry, so on a real iPhone the subnet scan is what finds the server. There is no on-device speech recognition yet (the voice assistant takes typed text), no TLS settings and no Bluetooth.

## 🌍 Languages

This README and the documents of the repository exist in eight languages: English, Spanish, German, French, Italian, Japanese, Chinese and Portuguese (Portugal). They are written together and checked in the CI so that the eight files have the same sections and the same links.

## 🔗 Related Projects

This project is part of the HYDRA-UMC robotics ecosystem by the same author (JuanenRac / Electro Hobby 3D). Worth knowing about, since a request might actually be about one of these rather than this repository.

**Parent Project**
- **[HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER)** — the real headless backend (REST/WebSocket) every control client actually talks to; the backend this app's own login, atomic commands, and WebSocket sync all run against.

**Sibling Projects** — also talk to HYDRA-UMC-SERVER's own API, each their own client
- **[HYDRA-UMC-STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO)** — web control dashboard with real-time multi-robot 3D visualization; its own 3D viewport is embedded directly in this app's 3D View screen via WebView.
- **[HYDRA-UMC-SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE)** — desktop (PySide6) swarm command center for multiple servers at once, packaged as a standalone executable; speaks the exact same `REMOTE_API.md` contract as this app.
- **[HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL)** — native Android control app with biometric login and a paired Wear OS companion; speaks the exact same `REMOTE_API.md` contract as this app.
- **[HYDRA-UMC-DSI](https://github.com/JuanenRac/HYDRA-UMC-DSI)** — native touch UI for the onboard 7" DSI touchscreen, embedded on the CM5 itself.
- **[HYDRA-UMC-BRIDGE-AMR](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-AMR)** — coordination boundary for AGV/AMR fleets via a VDA 5050 MQTT publisher (tested against an emulated fleet only).
- **[HYDRA-UMC-BRIDGE-CNC](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-CNC)** — high-level CNC-cell coordinator with GRBL status/control-byte access (tested against an emulator only).
- **[HYDRA-UMC-BRIDGE-DROIDS](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-DROIDS)** — coordination boundary for legged/humanoid droids, with a Boston Dynamics Spot command sender (tested against an emulator only).
- **[HYDRA-UMC-BRIDGE-LASER](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-LASER)** — laser-cell coordinator reading 3 key/enclosure/interlock GPIO signals (tested against a fake chip only; it cannot arm or fire a laser).
- **[HYDRA-UMC-BRIDGE-OPENPNP](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-OPENPNP)** — safe high-level board-flow coordinator for OpenPnP pick-and-place.
- **[HYDRA-UMC-BRIDGE-PRINTER3D](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-PRINTER3D)** — safe coordination boundary for Moonraker/Klipper 3D printers, with real gated job commands.
- **[HYDRA-UMC-BRIDGE-ROS2](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-ROS2)** — coordinator with a lazily imported rclpy ROS 2 transport (not yet run against a ROS 2 installation).
- **[HYDRA-UMC-BRIDGE-UAV](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-UAV)** — coordination boundary for camera-equipped UAVs, with a MAVLink command sender (tested against an emulator only).

**Directly Related**
- **[HYDRA-UMC-WATCH](https://github.com/JuanenRac/HYDRA-UMC-WATCH)** — WearOS companion app with haptic alert patterns and a paired-phone voice relay (not yet run on a physical watch); the wrist companion of HYDRA-UMC-ANDROID-CONTROL (WearOS only - this iOS app has no Apple Watch counterpart yet).
- **[HYDRA-UMC-HIL-BRIDGE](https://github.com/JuanenRac/HYDRA-UMC-HIL-BRIDGE)** — hardware-in-the-loop router with a software collision interlock between simulation and real hardware (tested without real hardware); the bridge that lets this app remote-control the digital twin, hardware-in-the-loop.

**Also Part of the Ecosystem**

*Core Hardware & Platform*
- **[HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC)** — the robot-arm motherboard design: CM5 host + dual-core STM32H745, meant to orchestrate up to 8 tool arms over CAN-OTA/SPI-OTA (firmware at an early stage; no populated board yet).
- **[HYDRA-UMC-OS](https://github.com/JuanenRac/HYDRA-UMC-OS)** — reproducible Raspberry Pi OS product layer for the CM5: read-only agent, validated config/profiles, WiFi first-contact provisioning.
- **[HYDRA-UMC-SDK](https://github.com/JuanenRac/HYDRA-UMC-SDK)** — the shared JSON-Schema contract and software job-gate boundary every bridge validates its commands against (not a certified safety function).
- **[HYDRA-UMC-CONNECTOR-HUB](https://github.com/JuanenRac/HYDRA-UMC-CONNECTOR-HUB)** — declarative adapter-manifest registry and validator for external-machine connectors; extends the SDK's own contract idea to external machines without replacing the industrial-gateway projects.

*Core Backend & Clients*
- **[HYDRA-UMC-EDITOR-URDF](https://github.com/JuanenRac/HYDRA-UMC-EDITOR-URDF)** — desktop graphical URDF creator/editor that pushes finished models into STUDIO's own catalog.
- **[HYDRA-UMC-EDITOR-STL](https://github.com/JuanenRac/HYDRA-UMC-EDITOR-STL)** — desktop STL model editor, transforming/replacing/removing/adding real parts in the same model catalog HYDRA-UMC-EDITOR-URDF also edits.

*URTC Tool Platform*
- **[URTC](https://github.com/JuanenRac/URTC)** — firmware for the physical Universal Robot Tool Controller PCB, 25+ tool profiles over CAN bus.
- **[URTC-FLASHER](https://github.com/JuanenRac/URTC-FLASHER)** — desktop GUI flashing tool for URTC boards, CAN-OTA plus full-chip SWD/JTAG.
- **[URTC-TESTER](https://github.com/JuanenRac/URTC-TESTER)** — desktop live CAN-bus diagnostic tool for URTC boards, one panel per tool profile.
- **[URTC-WEB-STUDIO](https://github.com/JuanenRac/URTC-WEB-STUDIO)** — browser-based alternative to URTC-TESTER via the Web Serial API, no local install needed.
- **[URTC-GATEWAY](https://github.com/JuanenRac/URTC-GATEWAY)** — gateway in front of the URTC CAN bus: an allowed list of identifiers, a rate limit and a session key; software tested on a computer, not yet on a real bus.

*Vision AI Node (Hailo-8)*
- **[HYDRA-UMC-VISION-NODE](https://github.com/JuanenRac/HYDRA-UMC-VISION-NODE)** — integration hub for the Hailo-8 vision pipeline, with a real per-stage hardware-readiness check.
- **[HYDRA-UMC-DETECTION-HEF](https://github.com/JuanenRac/HYDRA-UMC-DETECTION-HEF)** — real compiled-model registry with Hailo-architecture/checksum safe-load verification.
- **[HYDRA-UMC-VISION-STREAMER](https://github.com/JuanenRac/HYDRA-UMC-VISION-STREAMER)** — real GStreamer pipeline + MediaMTX config generator with a real HailoRT integration boundary.
- **[HYDRA-UMC-VISUAL-SERVOING-API](https://github.com/JuanenRac/HYDRA-UMC-VISUAL-SERVOING-API)** — Position-Based Visual Servoing correction law with authorisation gated on the zone state; no camera pose estimation yet.
- **[HYDRA-UMC-SAFETY-ZONES](https://github.com/JuanenRac/HYDRA-UMC-SAFETY-ZONES)** — v0 zone-breach, calibration-freshness and E-STOP-request logic that takes object positions from a file; no detector feeds it and no physical E-STOP is wired to it yet.

*Cognitive AI Node (Hailo-10)*
- **[HYDRA-UMC-COGNITIVE-NODE](https://github.com/JuanenRac/HYDRA-UMC-COGNITIVE-NODE)** — integration hub for the Hailo-10 cognitive pipeline (LLM/VLA/voice orchestration).
- **[HYDRA-UMC-VLA-ENGINE](https://github.com/JuanenRac/HYDRA-UMC-VLA-ENGINE)** — real action-token encoding/decoding and trajectory generation for a Vision-Language-Action model.
- **[HYDRA-UMC-VOICE-UI](https://github.com/JuanenRac/HYDRA-UMC-VOICE-UI)** — real voice front-end (VAD + intent parser) with a bounded, confirmation-gated Watch relay.
- **[HYDRA-UMC-SEMANTIC-PLANNER](https://github.com/JuanenRac/HYDRA-UMC-SEMANTIC-PLANNER)** — real rule-based task decomposition and semantic error recovery over MCU error codes.
- **[HYDRA-UMC-DOCS-QA](https://github.com/JuanenRac/HYDRA-UMC-DOCS-QA)** — real stdlib-only TF-IDF document search over this ecosystem's own Markdown docs.
- **[HYDRA-UMC-LOCAL-TECHNICIAN](https://github.com/JuanenRac/HYDRA-UMC-LOCAL-TECHNICIAN)** — local, policy-gated AI maintenance technician for the ecosystem itself - observes, diagnoses and proposes fixes; the two highest risk levels are deliberately not implemented yet.

*Orchestration & Swarm*
- **[HYDRA-UMC-ORCHESTRATOR](https://github.com/JuanenRac/HYDRA-UMC-ORCHESTRATOR)** — integration hub with a real gRPC/Protobuf health-report contract and mission state machine.
- **[HYDRA-UMC-JOB-DISPATCHER](https://github.com/JuanenRac/HYDRA-UMC-JOB-DISPATCHER)** — real priority-based job queue with deduplication, over a real HTTP API.
- **[HYDRA-UMC-NODE-HEALING](https://github.com/JuanenRac/HYDRA-UMC-NODE-HEALING)** — real gRPC-based fleet health watchdog with retry/backoff and identity-mismatch detection.
- **[HYDRA-UMC-PATH-PLANNER-3D](https://github.com/JuanenRac/HYDRA-UMC-PATH-PLANNER-3D)** — real RRT-based 3D path planner with real obstacle/workspace collision validation.
- **[HYDRA-UMC-SWARM-SYNC](https://github.com/JuanenRac/HYDRA-UMC-SWARM-SYNC)** — real CRDT LWW-Element-Map state sync, property-tested for multi-cell convergence.

*Digital Twin & Simulation*
- **[HYDRA-UMC-TWIN](https://github.com/JuanenRac/HYDRA-UMC-TWIN)** — integration hub for the digital-twin engine, with a real version-compatibility sync contract.
- **[HYDRA-UMC-PHYSICS-REPLICA](https://github.com/JuanenRac/HYDRA-UMC-PHYSICS-REPLICA)** — real forward kinematics and joint-limit validation over a real URDF subset.
- **[HYDRA-UMC-SYNTHETIC-DATA-GEN](https://github.com/JuanenRac/HYDRA-UMC-SYNTHETIC-DATA-GEN)** — real procedural 2D scene generator with YOLO/COCO annotation export.

*Data & Analytics*
- **[HYDRA-UMC-DATALAKE](https://github.com/JuanenRac/HYDRA-UMC-DATALAKE)** — real sqlite3-backed time-series store with a real ingest/query HTTP API.
- **[HYDRA-UMC-ANOMALY-DETECTOR](https://github.com/JuanenRac/HYDRA-UMC-ANOMALY-DETECTOR)** — real FFT + statistical baseline anomaly detector with drift monitoring.
- **[HYDRA-UMC-PRODUCTION-REPORTS](https://github.com/JuanenRac/HYDRA-UMC-PRODUCTION-REPORTS)** — real OEE/availability calculation over DATALAKE history, with reproducible CSV export.
- **[HYDRA-UMC-TELEMETRY-COLLECTOR](https://github.com/JuanenRac/HYDRA-UMC-TELEMETRY-COLLECTOR)** — real CAN/WebSocket ingestion pipeline into DATALAKE, with sequence deduplication.

*Industrial Gateway*
- **[HYDRA-UMC-GATEWAY-INDUSTRIAL](https://github.com/JuanenRac/HYDRA-UMC-GATEWAY-INDUSTRIAL)** — integration hub relaying to industrial protocols, with a real command allowlist/backpressure layer.
- **[HYDRA-UMC-OPCUA-SERVER](https://github.com/JuanenRac/HYDRA-UMC-OPCUA-SERVER)** — real OPC-UA address space, verified with a real binary-protocol client session.
- **[HYDRA-UMC-MQTT-BROKER](https://github.com/JuanenRac/HYDRA-UMC-MQTT-BROKER)** — real MQTT broker with optional per-client authentication and topic ACLs.
- **[HYDRA-UMC-MTCONNECT-ADAPTER](https://github.com/JuanenRac/HYDRA-UMC-MTCONNECT-ADAPTER)** — real MTConnect `/probe` and `/current` XML endpoints with degraded-mode output.

*Complementary Tools & Ecosystem Operations*
- **[HYDRA-UMC-DASHBOARD-AI](https://github.com/JuanenRac/HYDRA-UMC-DASHBOARD-AI)** — Smart Summaries and Anomaly Highlighting panels over DATALAKE/ANOMALY-DETECTOR, with an honest statistical fallback.
- **[HYDRA-UMC-TOOL-CLI](https://github.com/JuanenRac/HYDRA-UMC-TOOL-CLI)** — fleet CLI with a real, stable exit-code contract, a genuine live client of HYDRA-UMC-SERVER's own API.
- **[URTC-SMART-RACK](https://github.com/JuanenRac/URTC-SMART-RACK)** — firmware for a board-mounting rack with real tool-ID decoding and Smart Idle pre-heating logic.
- **[URTC-VISION-TOOL](https://github.com/JuanenRac/URTC-VISION-TOOL)** — firmware plus a real Python vision companion for a thermal/RGB inspection tool head.
- **[HYDRA-UMC-UPDATER](https://github.com/JuanenRac/HYDRA-UMC-UPDATER)** — administrative desktop tool that discovers, clones and updates every repo in this ecosystem.
- **[HYDRA-UMC-OS-REBUILDER](https://github.com/JuanenRac/HYDRA-UMC-OS-REBUILDER)** — Windows/Linux desktop tool that builds a ready-to-flash CM5 image pre-loaded with the ecosystem's most current versions, with Raspberry-Pi-Imager-style first-boot Wi-Fi/user/SSH configuration.
- **[HYDRA-UMC-OPS-AGENT](https://github.com/JuanenRac/HYDRA-UMC-OPS-AGENT)** — maintenance-incident coordinator: a low-privilege edge role collects a sanitized inventory/health snapshot, a control-plane role renders it read-only and asks an AI provider to suggest a diagnosis - never applies a patch or deploys anything.
- **[HYDRA-UMC-DEV-SERVER](https://github.com/JuanenRac/HYDRA-UMC-DEV-SERVER)** — reproducible development host (Raspberry Pi 5 / CM5) that stores the ecosystem's source and runs bounded build/test tasks under a durable queue; a dedicated dev role, explicitly not an operational CM5.

## 📚 Documentation

Where to read more:

* [docs/SOURCE_MAP.md](docs/SOURCE_MAP.md) - every source file of the app with a line on what it does
* **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — the Wi-Fi transport contract this app speaks against `server.ts` (endpoint by endpoint), why there's still no Bluetooth path, the real dual-path discovery mechanism, and this app's relationship to the rest of the ecosystem.
* [Security baseline of the ecosystem](https://github.com/JuanenRac/HYDRA-UMC-DOCS/blob/main/docs/SECURITY_BASELINE.md)
* [Threat model of the ecosystem](https://github.com/JuanenRac/HYDRA-UMC-DOCS/blob/main/docs/THREAT_MODEL.md)
* [Changelog of this repository](CHANGELOG.md)
* [License of this repository](LICENSE.md)

## 🤝 Contributing & Community

* Before a pull request run `HYDRA_UMC_CI=1 py -3 tools/ci_validate.py` (or `HYDRA_UMC_CI=1 python3 tools/ci_validate.py`): it must print `CI_VALIDATION=PASS`. Do not run `build.sh` or `build.bat` for this check; building is not a check.
* The eight READMEs are written from one source in HYDRA-UMC-DOCS; do not edit them by hand. Change the source and write them again with `tools/make_readmes.py`.
* Do not state in a README what has not run: say "simulated" or "not tried on hardware" where that is the truth.
* See [CONTRIBUTING.md](CONTRIBUTING.md), the [code of conduct](CODE_OF_CONDUCT.md), [SECURITY.md](SECURITY.md) and [SUPPORT.md](SUPPORT.md).

## 👤 AUTHOR

**JuanenRac (Electro Hobby 3D)** · electrohobby3d@gmail.com

## 📜 LICENSE

GPL-3.0-or-later - [LICENSE](LICENSE).
