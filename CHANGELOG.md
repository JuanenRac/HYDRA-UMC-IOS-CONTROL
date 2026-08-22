# Changelog

All notable changes to HYDRA-UMC CONTROL (iOS) are summarized here. Full
session-by-session detail (including dates) lives in the private, unpublished
`SONNET/HYDRA-UMC-IOS-CONTROL/auditoria_historial.txt`.

Version numbers below follow the ecosystem-wide auto-bump policy described in
[README.md](README.md#-versioning); earlier entries are grouped under the
pre-policy version `1.0.0+1` the repo carried while the policy did not yet
exist.

## [1.0.4+5] - Visible error reporting

- **`_CrashScreen` now interactive** - converted from `StatelessWidget` to
  `StatefulWidget` with a "Copy error details" button that copies the
  exception and stack trace to the clipboard, so a crash can actually be
  reported instead of only being visible on-screen.
- **Async errors now surfaced to the user** - added a
  `GlobalKey<ScaffoldMessengerState>` hung off `MaterialApp` and
  `_surfaceAsyncError()`, so errors reaching `PlatformDispatcher.onError`/
  `runZonedGuarded` show a real SnackBar instead of only going to
  `debugPrint` (a no-op in release builds).
- **Doc/reference cleanup** - corrected stale references claiming
  HYDRA-UMC STUDIO hosts `server.ts` (moved to the standalone
  HYDRA-UMC-SERVER project) in `docs/ARCHITECTURE.md`, the
  `lib/network/hydra_api_client.dart` header, and the README (+4
  translations).

## Versioning policy introduced

- **Automatic version bump on every real build.** `build.sh`/`build.bat`
  now run `tool/bump_version.dart` before `flutter build`, which bumps
  `pubspec.yaml`'s `version:` line on every invocation: patch +1, with an
  odometer-style carry into minor once patch would exceed 9 (`1.0.9` ->
  `1.1.0`), and a plain monotonic build-number (+1, no carry). No manual
  version editing from here on.
- `lib/app_version.dart` (generated, not hand-edited) now exposes
  `kAppVersion`/`kAppBuildNumber`/`kAppVersionFull` at runtime, regenerated
  by the same script - avoids adding `package_info_plus` as a new runtime
  dependency just to show the version in the UI.
- Settings screen (`lib/ui/settings_screen.dart`) now shows the running
  app's version and build number.
- Build scripts (`build.sh`/`build.bat`) now print a visible banner
  (project, what the script does, author, license) on every run, and keep
  their window open at the end (success or failure) instead of closing
  immediately.
- This file added, seeded from the real project history below.

## 1.0.0+1 and prior (pre-versioning-policy history)

- Repo created as a placeholder, then scoped out: iOS/iPadOS control app
  for a HYDRA-UMC robot over Wi-Fi or Bluetooth via the Compute Module 5.
  Initial pass shipped `docs/ARCHITECTURE.md` (Wi-Fi transport
  real/working today via the same `REMOTE_API.md` contract as HYDRA-UMC
  SUITE and STUDIO; Bluetooth transport honestly marked as blocked - no
  BLE GATT service exists yet on the CM5 side anywhere in the ecosystem)
  plus a placeholder Swift Package skeleton and VS Code tasks. No real
  implementation yet by design.
- Pivot from the Swift skeleton to a real Flutter app (Windows can
  build/run/test Flutter for real without Xcode, unlike Swift). Flutter
  SDK installed by hand on this machine; old Swift skeleton archived
  (never deleted) to `SONNET/_papelera/`. Full Dart architecture built as
  a deliberate mirror of HYDRA-UMC-ANDROID-CONTROL's own concepts/field
  names (no shared code): models (`RobotView`/`ControllerView`/
  `HydraState`, correct `hasCamera` from day one), networking
  (`hydra_api_client.dart`, `hydra_websocket.dart` with `?token=` from day
  one, `discovery.dart` concurrent subnet scan, `auth_prefs.dart`), a
  central `RobotViewModel` (atomic per-robot commands via
  `POST /api/robot/:id/command` from day one, correct `combinedWith`
  propagation), and the full UI (login, 5-tab main nav, dashboard, manual
  control with real long-press E-STOP/STOP protection from day one,
  camera with MJPEG + vision toggle, 3D view via WebView,
  settings/logout). `flutter analyze` clean, `flutter test` passing,
  `flutter build windows` producing a real launched `.exe` throughout.
- mDNS-based discovery (`multicast_dns`) added alongside the subnet scan.
  Real app icon + native splash generated from
  `images/app_icon_source.png` via `flutter_launcher_icons`/
  `flutter_native_splash` (iOS + Windows icon; splash iOS-only, no Windows
  support in the tool). Biometric gate (Face ID/Touch ID/Windows Hello via
  `local_auth`) added to protect restoring a saved session on launch
  (`network/biometric_helper.dart`, `ui/biometric_gate_screen.dart`,
  toggle in `ui/settings_screen.dart`, `NSFaceIDUsageDescription` in
  `ios/Runner/Info.plist`) - adapted to this app's own session-token-only
  auth model rather than porting Android's password-refill design
  literally. Local push-style notifications investigated and deliberately
  reverted: `flutter_local_notifications` failed to compile on this
  machine (`fatal error C1083: atlbase.h` - missing ATL component in
  Visual Studio Build Tools, not installable without elevation), confirmed
  via a real failed build, then cleanly removed with
  `flutter build windows` reconfirmed working without it.
  `flutter analyze`/`flutter test`/`flutter build windows` reverified
  clean after every change, with the `.exe` launched and seen alive in
  `tasklist` after the visual/runtime-impacting changes.
