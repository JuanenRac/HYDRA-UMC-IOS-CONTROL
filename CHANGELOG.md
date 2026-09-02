# Changelog

All notable changes to HYDRA-UMC CONTROL (iOS) are summarized here. Full
session-by-session detail (including dates) lives in a private, unpublished
internal log.

Version numbers below follow the ecosystem-wide auto-bump policy described in
[README.md](README.md#-versioning); earlier entries are grouped under the
pre-policy version `0.0.0+1` the repo carried while the policy did not yet
exist.

## [0.1.1]

- **Offline state cache** (`lib/network/state_cache.dart`, ported from
  HYDRA-UMC-ANDROID-CONTROL's own `StateCache.kt`) - the last known
  settings tree persists to disk (`shared_preferences`, debounced 1s the
  same way ANDROID-CONTROL's DataStore write is) and loads back on
  launch, so the Dashboard/Control screens show real, if possibly stale,
  robot data immediately instead of an empty state while the live
  `connect()` round-trip is still in flight - genuinely useful right
  after the phone comes back into WiFi range. Superseded by the real
  fetch the instant it succeeds. Real save/load round-trip test coverage
  in `test/state_cache_test.dart`, including corrupt-cache handling.
- **Telemetry screen** (`lib/ui/telemetry_screen.dart`, new 6th tab) -
  ported the Logs half of HYDRA-UMC-ANDROID-CONTROL's own
  `TelemetryScreen.kt` (its separate "Ecosystem" tab reads a different
  server endpoint and is a larger feature of its own, not part of this
  port): a terminal-style, newest-first, monospace log of real
  connection/login/command lifecycle events (green text, red for
  anything that looks like an error - same "Matrix Green" convention as
  the Android app), capped at 50 entries, with a clear-log action.
  `RobotViewModel`'s new `telemetryLog`/`clearTelemetryLog()` are covered
  by `test/telemetry_log_test.dart` (real command round-trip via a mocked
  HTTP client, the 50-entry cap, and clearing).

## [0.1.0]

- **Human-readable uptime on the Dashboard** (`lib/ui/dashboard_screen.dart`'s
  new `formatUptime()`) - was a raw hours-with-one-decimal figure (`4.3h`);
  now the same "2d 4h 15m" format HYDRA-UMC-ANDROID-CONTROL's own
  `DashboardScreen.kt` `formatUptime()` already shows, ported to match
  (same untranslated d/h/m units in every language, matching this
  ecosystem's short-technical-abbreviation convention). Real test
  coverage in `test/format_uptime_test.dart` for the minutes-only/
  hours-and-minutes/days-hours-minutes/zero-day-boundary cases.

## [0.0.9]

- **Full 7-language UI localization** - this app had no `intl`/
  `flutter_localizations` at all before this release; every screen showed
  hardcoded English regardless of device locale, unlike the rest of the
  ecosystem's UIs (STUDIO, SUITE, ANDROID-CONTROL, WATCH, UPDATER). Added
  the standard `flutter gen-l10n` pipeline (`lib/l10n/app_*.arb`, one real
  translation per key - Spanish, French, German, Italian, Japanese, Chinese,
  no placeholders) covering every screen's chrome, dialogs, tooltips and
  navigation labels, plus a persisted language override
  (`Settings > Language`, `LanguagePrefs` via `shared_preferences`) that
  defaults to the OS locale when unset.
- **Business-logic error messages now localizable too**: `RobotViewModel.
  lastError` was a raw English `String` built inside a `ChangeNotifier` with
  no `BuildContext` to localize from. Replaced with a typed `HydraError`
  (kind + raw parameters, never pre-formatted text) that the UI layer
  resolves via `AppLocalizations` only when it actually renders a message -
  `hydra_websocket.dart`'s two client-side connection-failure literals are
  now localized the same way, while a server-relayed WS error message is
  correctly left untouched (already resolved server-side, not this app's
  text to translate).
- Real test coverage: `test/localization_test.dart` builds an actual widget
  tree under `Locale('es')`/`Locale('ja')` and asserts on the resolved
  strings and interpolated placeholders, not just that the English default
  still renders.

## [0.0.8] - Debounced the speed/acceleration slider's real network send

- **`lib/state/robot_view_model.dart`** - `setSpeed()` now debounces its
  real `POST /api/robot/:id/command` send by 300ms, matching
  HYDRA-UMC-ANDROID-CONTROL's own `sendAtomicCommand(..., debounceMs =
  300)`. Every drag frame of the speed/acceleration `Slider`
  (`ui/control_screen.dart`) used to fire its own real network request -
  the local optimistic UI update still applies instantly every frame
  (unchanged), only the actual round-trip is now coalesced into one real
  send once the drag settles, cancelling any still-pending send for the
  same command name (`_sendAtomicCommand`'s new `debounce` parameter,
  backed by a per-command `Timer` map). Every other real-time control
  (jog, E-STOP/play/pause/stop, valve/pump toggles) already sent
  immediately and is unaffected.

## [0.0.7] - Fixed a real version-drift bug in build.bat's own step order

- **`build.bat`** - it ran `bump_manifest_version.py` (a real, independent
  bump) *before* `dart run tool/bump_version.dart`, the real source of
  the app's own native version (`pubspec.yaml`). That let the manifest
  advance to a version the compiled app hadn't reached yet - exactly the
  drift class this ecosystem's version-mirror convention exists to
  prevent. `build.sh` already had the correct order; `build.bat` now
  matches: `dart run tool/bump_version.dart` first, then
  `bump_manifest_version.py --sync` to align the manifest to what the
  app build actually produced. Verified with a real `flutter build
  windows` run through the fixed script.
- **`tools/ci_validate.py`** - new `validate_local_markdown_links()`
  rejects a relative Markdown link whose target file doesn't actually
  exist (external URLs and anchors are skipped, not probed). `CI_VALIDATION=PASS`.

## [0.0.6]

- Build version synchronized with `hydra-umc.project.json` and the repository-native version source.

## [0.0.5]

- Build version synchronized with `hydra-umc.project.json` and the repository-native version source.

## [0.0.4+5] - Visible error reporting

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
  odometer-style carry into minor once patch would exceed 9 (`0.0.9` ->
  `0.1.0`), and a plain monotonic build-number (+1, no carry). No manual
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

## 0.0.0+1 and prior (pre-versioning-policy history)

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
  (never deleted) internally. Full Dart architecture built as
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
