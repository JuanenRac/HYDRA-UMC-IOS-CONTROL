# Changelog

All notable changes to this project are documented here.

## [Unreleased]

## [0.2.9] - The version of the client in its identity and an offline copy that belongs to one server and one account

- **The client identity carries the version:** every request now sends `X-Hydra-Client: ios/<version>` (for example `ios/0.2.8`) instead of the bare type, as the Android app does. The server compares the type only, so access is opened and closed exactly as before, and keeps the version apart for the history of connections. A version the server would not take (1 to 24 of `0-9 A-Z a-z . _ -`) is left out and the header is just `ios`. New `test/client_header_test.dart` (the value, what the server reads of it, versions that are refused, every request and the headers of the camera stream); `test/voice_turn_test.dart` reads the value from the same function. Written and tested on the Dart VM only: not built for iOS.
- **The offline copy belongs to one server and one account:** the saved state carries the account and the server it was read from, and a copy that belongs to another server or account (or that an older build saved without one) is erased instead of being shown as the state of the one being opened.

## [0.2.8] - Safe mode of a robot, HTTPS first with a certificate you can trust and the version moved by the shared project tool

- **Safe mode of a robot:** the control bar has a button to disable the selected robot (hold to confirm, like STOP): the robot stops, its valves and pumps go off and the server refuses everything but STOP. A disabled robot shows the button in green; an administrator can hold it to enable the robot again. The server keeps enabling off by default, so the refusal says so in its own words (enabling not allowed, administrator required), and a command sent to a disabled robot says the robot is in safe mode, in the eight languages.

- **The version is moved by the shared project tool alone:** `python tools/hydra_project_tool.py bump` raises the build number and rewrites `lib/app_version.dart` itself, and the Dart script `tool/bump_version.dart` is gone. The version name keeps three components and the build number (the part after `+`) a plain counter, in the form Flutter accepts.
- **HTTPS first, plain HTTP only when allowed, and a certificate you can trust:** the app used to probe plain HTTP first and could fall back to it without asking, so a device on the network that answered in plain HTTP could receive the user name and password. Now every connection starts over HTTPS (REST, WebSocket and the live camera). Plain HTTP is a second try only when the new **Security** window allows it (and, outside the local network, only when that is allowed too); a server once seen over TLS is never retried in plain HTTP. A server with a self-signed certificate is trusted by its SHA-256 fingerprint: **Security** reads it from the server, shows it, and keeps it only after you trust it and save; from then on only a certificate with exactly that fingerprint is accepted. A CA certificate can be given instead. Security is reachable from the sign-in screen and from Settings, in all eight languages, and a failed secure connection now says so and points to it. The 3D view (a web view) still follows the system certificates. Traffic to this same machine (loopback) never needs the plain switch. 29 new tests, including a real TLS server with a self-signed certificate (249 in all).

- **README in the universal layout:** the README and its seven translations follow the layout that the four families share (22 sections in a fixed order), with an architecture picture and a repository-structure picture drawn from `docs/architecture.json` and `docs/structure.json`; the CI validator checks both pictures and the file tree.

- **The layout of the README is checked in the CI:** the validator runs `tools/universal_readme_check.py` and lists, as a warning, what differs from the universal layout of the README.

## [0.2.7] - The jog step is the one the server keeps for the robot and the permission prompts are in the language of the device

### Firmware and protocol

- **The permission prompts are in the language of the device.** The local-network and Face ID texts come from an `InfoPlist.strings` per language (English, Spanish, German, French, Italian, Japanese, Simplified Chinese, European Portuguese), registered in the project, instead of the English ones of `Info.plist` for every language. Checked by a test that reads the files and the project. Not tried on a device.
- **Audit record for administrators.** An Audit record button under the reservations opens the lines the server wrote down about the changes that matter, newest first, with a filter by type, robot and number of lines. Verifying checks the chain of SHA-256 hashes twice: the server over the whole record and the app over the lines it was given (a changed line, a replaced line whose successor still names the old one; a filtered window only shows gaps). The lines can be copied as stored (`.jsonl`). Says why when it can not read (not an administrator, older server, expired session, no network, record switched off or locked off).
- Tests for the three rules (`contract_v2_test.dart`, with SHA-256 vectors) and for the behaviour against a local server (`robot_view_model_conditional_test.dart`: the header, the 412, the table, the older server, the audit record).
- The live connection no longer falls back to `/ws?token=`: the token travels only as the `hydra.bearer` subprotocol, which every server since the subprotocol was added answers and which the server now requires (it refuses the address form by default). A server that does not answer it is reported as a failed connection instead of being handed the token in the address. A token that a subprotocol cannot carry is reported as rejected and no connection is attempted; `ServerInfo.wsUrl()` (unused) is gone. Three tests replace the one that expected the fallback.
- The README and the architecture notes describe the subprotocol as the only form.

### Programs and windows

- **The jog step is the one the server keeps for the robot.** The step selector shows the step shared by every client that shows the robot (the nearest one it offers) and changing it sends the `jogStep` command, so the phone, the tablet and the browser agree; a robot with none yet keeps 10. Tested.
- **A quiet start-up and a new sign-in, like the other apps of the family.** The start-up picture is gone: the launch screen of the system is a plain dark screen and the app shows the mark, the name and one line for a second and a half before it opens. The sign-in has the same look: the mark and the name on top and the server, the user and the password in a rounded panel with their icons, a button to show the password and a large sign-in button. The line under the name and the password button are in the eight languages.
- **PLAY asks first.** Before a trajectory starts the app shows the robot, its recorded points, the speed and who has it reserved (a robot reserved by someone else says the server will refuse the command). It is on by default and is turned off in Settings; a robot that is already playing is not asked again, and the choice is kept. In the eight languages, with tests of the rules, the option and the dialog (cancelling sends nothing).
- **Conditional writes.** Every reservation, release and robot command carries the revision of the robot this app last saw (`If-Match`, kept per robot from the answers of the server and from `GET /api/robot/:id`). When someone else changed the robot in between, the server answers 412: nothing is applied, the change on screen is undone, the robot is read again so the screen shows what it is now, and the message says so in the eight languages. STOP is never conditional, a write is not conditional while another write to the same robot is on its way, and a take-over is never conditional. A choice in the list of reservations (kept on the device) selects Standard (reservations, the table and the one-off commands; the default), Strict (everything but STOP) or Off.
- **The server pushes the reservations** (WebSocket message `claims`): the list and the arming of the jog follow at once and the 15 second poll of the Control screen rests while a push is recent.
- **Reservations.** The Control screen shows who holds the selected robot (nobody, this device, your account on another device, another account), reserves and releases it, and lists every reservation of the server. Reservations stay optional.
- **Controller id.** The app keeps one controller id for the installation and sends it with every reserve, release, jog-arm and command (body and `X-Controller-Id` header), so a reservation belongs to the account and to this device. The refusals of the server read differently: another account, your account on another device or window, controller id required, and jog not armed.
- New switch in Settings, off by default: "Block commands on saved data". While the screen shows the saved copy of the robot state instead of the live one, every command except STOP is held back with its own message. Its choice is kept between launches.
- New switch on the sign-in screen, off by default: "Do not scan mobile-data or VPN networks". The subnet scan then leaves out those interfaces of the phone (mobile data, tunnels, VPN) instead of sweeping their address ranges.
- Accessibility: every jog D-pad button is announced by VoiceOver with its axis and direction (in the eight languages) and activates with one step; the D-pad cells are 44 pt (they were about 41) and the Z buttons are as wide as their column, so the whole button takes the touch, not only the arrow. The global STOP button is 44 pt high.
- **Take control (administrators only).** On a robot someone else holds, an administrator's session shows a **Take control** button that asks for confirmation and then reserves the robot with `force: true`. The role comes from the session token (the server checks it again); an operator never sees the button and nothing is sent if it is asked for anyway. Texts in the eight languages and unit tests for the role, the rule and the request.

### Tests, builds and checks

- **The 3D viewer no longer gets the token in its query**: the embedded viewer is opened with `?hideUI=true&robotId=N#token=...`, a fragment that is never sent to the server, so no access log, proxy or referrer sees it (same as the Android app; the web viewer reads it from there). The address is built by `lib/util/viewer_url.dart` and covered by tests.
- CI builds the iOS app on a macOS runner (`flutter build ios --release --no-codesign`), so a change that breaks the Xcode project or a plugin is caught before a release instead of on the owner's Mac.
- The eight languages carry the new texts, with their tests.
- Building no longer changes the version; raising it is the explicit `bump` command (`python tools/hydra_project_tool.py bump`). The build scripts only report the version they built, and CI fails if a build script runs a bump.
- Added `tools/hydra_project_tool.py`: the same `validate`, `test`, `version`, `status` and `bump` commands in every repository. The checks run with `HYDRA_UMC_CI=1` and fail if the version changes; only `bump` changes it.
- Fixed stale comments and metadata: the project manifest build and notes, the icon-source comment in `pubspec.yaml`, and the test list in the eight READMEs.
- Tests: 4 new files (saved-data block, interface filter, jog pad accessibility and size, camera lifecycle). The block, the label and the size tests fail with the previous code.

### Other changes

- **The XY table jog is one atomic `table` command**, relative to where the table is (checked as a whole against the limits of the model before it is sent and counted as a jog for the arming of the jog); a server that predates the command is detected and gets the jogs that did the same before.
- **Safety limits.** The limits of the robot's model are read from the server: a jog step above the limit is not sent (it says which limit), and when the administrator requires it the jog waits for an explicit **Arm jog** (with a countdown) that ends by itself, with STOP, or on release.
- The banner follows the animated style of the ecosystem banners, with the name, the kind and the technologies of the project.
- The live camera picture is closed when the app goes to the background and opened again when it comes back, instead of downloading video the user cannot see.
- Removed the unused `postSettings` and `HydraState.merge`; the notes in the API client no longer say that every server seeds an `admin/admin` account (a production server has none).

## [0.2.6]

- Maturity is functional: nothing here has been verified on real hardware yet.
- The READMEs say, in the eight languages, what is planned and what has only been tested against fakes, emulators or fixtures, and carry a short safety and security status note.

## [0.2.5] - Reconnect back-off that stays a back-off, and tolerant readers of server data

- **Reconnect back-off:** the wait before a reconnect was `3 s x 2^(failed attempts - 1)` computed in 64-bit integers, which overflows at 62 consecutive failed attempts (about half an hour with a server that stays down): the wait fell to zero and the app reconnected every fraction of a second until the server came back. The doubling now stops at 10 steps, so the wait is always between 3 s and 30 s.
- **Settings tree:** a robot, controller or camera whose fields have the wrong type (a number for a name, a text for a flag, an entry that is not an object) no longer throws a cast error from the model getters and takes the screen down; each field reads as its default and entries that are not objects are skipped.
- **HTTP answers:** a `200` whose body is JSON but not an object (a list, `null`, a number) is a `HydraApiException` instead of a cast error, a discovery answer whose `product`, `appVersion` or `hostname` is not text no longer breaks the scan, and a STOP answer with a count that is not a finite number (JSON `1e999`) keeps its robots instead of failing.
- Tests: 26 new (119 in all, line coverage of the app code up from 35 % to 45 %): tolerant readers, HTTP answers, STOP answer, back-off, frames of the wrong shape on the WebSocket, and the error texts in the 8 languages. The sign-out test no longer depends on how fast the first WebSocket close arrives.

## [0.2.4]

- Build version synchronized with `hydra-umc.project.json` and the repository-native version source.
- The licence is written as GPL-3.0-or-later in every header and in the package metadata.

## [0.2.3] - One-tap global STOP

- **Global STOP:** a red **STOP** button in the app bar of every tab (Dashboard, Control, Camera, 3D, Telemetry, Settings) stops every robot of every controller with one tap: no long press and no confirmation. It calls `POST /api/stop-all` at once (bearer token and client header, no body), without waiting for any refresh, and works for an admin and an operator account. A robot reserved by another account is stopped too.
- **Result robot by robot:** a banner under the app bar lists each robot (stopped or not, the reason, "reserved by ..." when someone else holds it), turns red with a warning when a robot failed or the server could not save the stop, and is closed by the user. The state is read again afterwards.
- **STOP that gets through:** a network error is retried once with a short timeout; a server over its rate limit (429) or without the route (404) is answered with the per-robot stop of every robot; when nothing answers, a persistent "STOP not confirmed" banner with a Retry button stays until a later STOP gets an answer.
- **Control tab:** the long-press E-STOP of the selected robot is replaced by a big one-tap global STOP; the round per-robot stop next to play/pause keeps its long-press protection.
- STOP, its descriptions and the result texts in the 8 languages; 8 new tests (93 in all) against a local server: the request, the per-robot answer, a failed/unsaved/reserved robot, the 429 and 404 fall back, the retry, the persistent state and the token renewal.

## [0.2.2] - Home pose no longer crashes the Control screen, session renewal, clear server refusals

- **The Control screen no longer disappears at the home pose:** the server writes whole numbers without decimals, so a joint at 0 arrived as an integer and `as double` threw, replacing the whole Control screen (STOP, jog, play) with the error screen. Joint angles are now read as numbers whatever their form (`RobotView.joint`); device answers with other number types no longer break the network scan either.
- **One renewal for one expired token:** the server's "Access denied" frame and the 1008 close that follows it are one event; they used to start two refreshes with the single-use refresh token, and the second one signed the user out. Renewals are single-flight, an expired token found by a REST call or by a command is renewed with the refresh token and the request repeated, and only a failed renewal signs out, completely (socket, polling, timers, stored session and offline copy), instead of leaving sockets running behind the login screen.
- **Clear refusals:** a robot reserved by another account (409), a command the server does not have (400), a missing permission (403) and a 200 answer with warnings each have their own message in the 8 languages, and the optimistic change is undone. Errors are detected by status and code, not by looking for "401" in a message.
- **Pause is explicit:** it is sent as `{paused: true|false}` computed once, like the Android app, so a combined pair cannot drift apart.
- **No "enable"/"disable":** the server has no such command (it answered 400, and before that a false success); both are gone from the app and the docs.
- **Jog that stops when released:** while one jog is on the wire the next tick of a held button is dropped instead of piling up behind a slow link, and nothing jogs while a trajectory is running.
- **STOP that gets through:** a stop is sent with 2 s timeouts and, when nobody answers, again up to 3 times; if it still fails the message says the STOP was not confirmed.
- **Token out of the address:** the WebSocket sends the token as the `hydra.bearer` subprotocol (a server that refuses it gets `?token=` automatically), pings every 20 s to notice a dead link, reconnects with a growing back-off and ignores binary frames; every full snapshot is applied (the "same as the last one" filter hid changes made by deltas in between).
- **Camera and 3D view on TLS servers:** both build their address from the scheme the client learned (https for a TLS server), the camera stream carries the bearer header, a non-200 answer is shown as such, the newest frame is the one drawn, the picture buffer is capped, the camera is chosen through `assignedRobotId`, and the camera and 3D tabs do nothing until they are shown. The 3D page's web storage is emptied on sign-out.
- **Keychain and offline copy:** the scheme a server answered on is remembered (a TLS server is never probed over plain http again), a fresh installation erases a session an earlier one left in the Keychain, Keychain items are for this device only, a login replaces the stored refresh token, the offline copy drops camera credentials and is erased on sign-out, and a biometric lock that cannot be shown now fails closed.
- **Smaller fixes:** system metrics carry the bearer token and a host without a temperature sensor shows `--`, a relative XY-table jog no longer writes `pos.tx`/`pos.ty`, the same error shown twice is shown twice, the voice assistant sends the app's chosen language, the scan finishes even if one host answers with something unexpected, the Windows build is credited to the project and its GPL-3.0 licence, and `Info.plist` lists the `_hydra._tcp` Bonjour service and the 8 languages.
- 24 new tests (85 in all): the refusals, the single renewal, the jog guard, the WebSocket subprotocol and its fallback, the offline copy and the Keychain rules.

## [0.2.1] - Portuguese interface

- **Portuguese interface:** `lib/l10n/app_pt.arb` (87 keys, the same `{placeholders}` as English), generated by the standard `flutter gen-l10n` pipeline, and `Português` in `Settings > Language`. The app is now in 8 languages and a README_por.md joins the other seven.
- **Translation check:** `test/localization_test.dart` now resolves Portuguese strings end to end and fails when any language file misses an English key or changes a `{placeholder}`. 61 tests in all; `flutter analyze` reports no issues.
- **README fix:** the HYDRA-UMC-WATCH entry in Related Projects called a WearOS app "the Apple Watch companion to this app". It is the wrist companion of HYDRA-UMC-ANDROID-CONTROL; this iOS app has no Apple Watch counterpart yet. Corrected in all languages.

## [0.2.0] - Could no longer reach a server with TLS turned on

- **Real bug, found reviewing this app for the same TLS rollout that fixed HYDRA-UMC-ANDROID-CONTROL/STUDIO/SUITE:** `ServerInfo`, `HydraApiClient` and `HydraWebSocket` all had `http://`/`ws://` hardcoded, with no way to reach a server that switched to HYDRA-UMC-SERVER's optional HTTPS/WSS-only mode (`TLS_CERT_PATH`/`TLS_KEY_PATH`, server.ts). `getHydraInfo()` now probes the current scheme first and, only if that gets no answer at all, retries once over HTTPS, remembered via `usesTls` for every later call through that same client - `login()` and `getSettings()` (this app's own two real entry points, a fresh sign-in and a restored session) both resolve it before their real request, and it is threaded into the WebSocket this app also opens. A plain-HTTP server (today's default) behaves exactly as before. `flutter analyze`: no issues. `flutter test`: all 59 tests pass, including the real local-server WebSocket reconnect suite.

## [0.1.9] - Actively pauses the WebSocket and metrics poll when backgrounded

- Found on code review: this app relied entirely on iOS's own
  OS-level socket timeout to eventually notice a backgrounded connection
  was dead, rather than actively closing it - HYDRA-UMC-ANDROID-CONTROL's
  own equivalent already closes proactively.
  `_RootGateState.didChangeAppLifecycleState` (`main.dart`) now also
  reacts to `AppLifecycleState.paused` (not the merely-transient
  `inactive` state a system alert or the app switcher also produces),
  calling new `RobotViewModel.pauseForBackground()`: disconnects the
  real WebSocket and cancels the 5s REST metrics poll the moment the app
  leaves the foreground. `reconnectIfNeeded()` on resume already fully
  re-establishes both, unchanged. 3 new tests against a real local
  WebSocket server, one proving the server side actually observes the
  connection close, not just a local status flag flipping.

## [0.1.8] - The offline state cache now says when it is showing stale data

`lib/network/state_cache.dart`'s persisted last-known settings tree used
to save/load with no timestamp at all - exactly the plain "visual cache"
risk: nothing on screen ever said whether what was showing was five
seconds or five days old, if a real reconnect never happened (a dead
server, a wrong host after a device restore, ...). `saveState()` now also
records the real save instant; a new `loadCachedState()` returns it
alongside the cached tree as a `CachedState` (a build predating this
field reports the epoch - unknown age is treated as maximally stale,
never as "just saved"). `RobotViewModel` exposes this as
`isShowingCachedState`/`cachedStateSavedAt`, set when `init()` loads a
cache and cleared the moment either real path that replaces `state` with
a live server response succeeds (the REST fetch in `connect()`, or the
WS `onSettings` callback). `MainScreen` shows a real, visible banner
("Showing cached data from HH:mm…") for as long as that stays true,
regardless of which of the 6 tabs is active - mirrors
HYDRA-UMC-WATCH's own real `LastKnownStateCache.kt` staleness pattern,
ported to this persistent (not in-memory) cache. 9 new/updated tests
across `state_cache_test.dart` and two new files
(`robot_view_model_cached_state_test.dart`,
`main_screen_cached_state_banner_test.dart`), `flutter analyze` clean.

## [0.1.7] - A rejected session token now tries to heal itself before logging out

`0.1.6` stopped a `wsAuthRejected` (RFC 6455 1008) close from retrying
forever against a token the server will never accept again - but it still
forced a real, visible logout every time, even though most real 1008s are
just the access token's own routine time-based expiry, not an actual
revocation. `HydraApiClient` gains `refresh()`/`logoutRemote()`
(`POST /api/refresh` / `POST /api/logout`, HYDRA-UMC-SERVER 0.6.2's own
opaque refresh-token pair from `POST /api/login`); `AuthPrefs` stores the
refresh token in secure storage only, same treatment as the access token
itself, never a plaintext fallback. `RobotViewModel`'s WS `onError` now
tries a new `_attemptTokenRefresh()` on an auth failure before forcing
logout, and reopens the socket with the fresh token on success; a real
revoked session, no refresh token on file, or a server predating this
feature all still fall through to the same forced logout as before. This
app never stores a password (see `auth_prefs.dart`'s own header comment),
so it mirrors HYDRA-UMC-DSI's/STUDIO's own refresh-token client rather
than ANDROID-CONTROL's "replay the remembered password" approach.
`RobotViewModel` is now built with an injectable `AuthPrefs` for real test
coverage. Verified with a real end-to-end regression test
(`test/robot_view_model_silent_refresh_test.dart`) against a real local
HTTP+WebSocket server: a first `/ws` connection closed with 1008 is
recovered silently (second connection carries the refreshed token,
`isLoggedIn` never flips), while an unrecognized refresh token still
forces a real logout.

## [0.1.6] - A rejected session token no longer retries forever, silently

`network/hydra_websocket.dart`'s `onDone` always rescheduled a reconnect,
unconditionally - a real gap: server.ts
closes the `/ws` upgrade with RFC 6455 code 1008 for a missing/invalid/
expired token and never sends a message frame first (the connection is
rejected before any data can flow), so the existing `{"error": "..."}`
message check could never catch this case. The app just spun forever in
"connecting" -> "disconnected" against a token the server will never
accept again, with no visible error and no path back to the login screen.
Now checks the real close code and, on a 1008, stops retrying and surfaces
a new, localized `wsAuthRejected` error (all 7 languages) that
`RobotViewModel` treats the same as a server-relayed "denied"/"token"
message: force logout, disconnect. Same fix ported to HYDRA-UMC-DSI's own
copy of this file. Real end-to-end regression test against a real local
WebSocket server (`test/hydra_websocket_reconnect_test.dart`), asserting
both the error and that no second connection attempt is ever made.

## [0.1.5] - In-app voice/text assistant button

New mic icon in the app bar opens VoiceAssistantDialog: type a question or
an order, sent to HYDRA-UMC-VOICE-UI through the same authenticated
`POST /api/voice/turn` Server route HYDRA-UMC-ANDROID-CONTROL's own
in-app voice button and paired-Watch relay use (`HydraApiClient.
postVoiceTurn()`, tagged `X-Hydra-Client: ios` like every other request
this app sends, so Config > Remote Access gates it the same way as the
rest of this app's own traffic). A reply only ever carries text/status;
`sendVoiceTurn()` never invokes `sendAtomicCommand` or mutates robot
state directly, and a motion-related reply is explicitly marked
`requiresConfirmation`.

Text input only for now: unlike Android's `RecognizerIntent` (a system
intent, always present), on-device speech recognition on iOS needs the
native Speech framework wired through a real plugin and Info.plist
entries this Windows-only development environment cannot build or verify
against a real device/Xcode - documented honestly in
`ui/voice_assistant_dialog.dart` rather than claimed working. Typing
already delivers the real request in full.

3 new tests (`test/voice_turn_test.dart`, a real local `dart:io`
`HttpServer`, same "real local server, never a mocked client" convention
as `test/hydra_websocket_reconnect_test.dart`) cover the real request
shape, the client-identity header, and a real server-error path.

## [0.1.4] - a failed logout or a half-written session could resurrect an old token

Same real fix as HYDRA-UMC-DSI's own `AuthPrefs`, found by
static inspection of both files: `clearToken()` caught a failed
secure-storage `delete()` and only logged it, so a real logout could
return successfully while the old token was still sitting in secure
storage - a later `loadToken()` (a real restart, say) could resurrect
the "cleared" session. Separately, `saveToken()` wrote the token and
username as two separate secure-storage calls; a token write that
succeeded followed by a username write that failed left secure storage
holding a real, orphaned token while the catch block reported the whole
session as in-memory-only.

Fixed with a plain, non-secret `hydra_logged_out` marker in ordinary
SharedPreferences - the real, persistent source of truth `loadToken()`/
`loadUsername()` now check FIRST, set BEFORE `clearToken()` ever
attempts the real secure delete, and cleared only by a fresh,
successful `saveToken()`. `saveToken()` itself now reverts (best-effort)
whatever it did manage to write if a later step in the same call fails.

## [0.1.3] - real regression found by independent revalidation

An independent revalidation reproduced a real gap in v0.1.2's own
secure-storage fix (against a real fake `SecureTokenBackend`, no real platform
channel) - the exact same shape of bug also found and
fixed in HYDRA-UMC-DSI's own `auth_prefs.dart`:

- `saveToken()` wrapped every secure-storage write so a
  failure fell back to writing the token in PLAIN `SharedPreferences` -
  exactly the failure of the protection mechanism itself silently
  removing the guarantee the earlier fix was meant to provide. The biometric lock
  screen would still do nothing to protect that plaintext copy
  underneath it. Fixed: a secure-storage write failure now keeps the
  session in memory ONLY, for the current app run - never written to
  disk in plaintext. A real restart on a device whose secure storage is
  genuinely broken now requires logging in again, rather than the token
  quietly living in a plaintext file (included in a normal iOS device
  backup, or a plain JSON file on Windows). Never regresses a device
  where secure storage genuinely works (this app's real, intended
  Keychain/DPAPI deployment targets). A pre-existing legacy plaintext token
  is still migrated in and read normally - that is reading pre-existing
  data, not a new plaintext write.
- 2 new regression tests (one asserting the plaintext file is never
  touched, one proving a fresh app instance genuinely cannot recover an
  in-memory-only session - the real, deliberate trade-off this fix
  makes); the 2 existing tests that used to assert the old plaintext
  fallback as correct behavior were rewritten to assert the fix instead.
  `flutter analyze`/`flutter test` both clean.

## [0.1.2] - Real secure storage for the session token

- The session token lived in the same plain `SharedPreferences` file as
  host/port and the biometric-enabled flag - a plain, unencrypted store
  (`NSUserDefaults` on iOS is included in a normal device backup). A
  biometric lock screen only gates the UI path back into the app; it never
  encrypted the file underneath it. `network/auth_prefs.dart` now
  reads/writes the token through a new `SecureTokenBackend`, backed by
  `flutter_secure_storage` (real Keychain on iOS, DPAPI-backed encrypted
  storage on Windows - this app's two real deployment targets). Every
  secure call is wrapped: on any failure it falls back to the exact same
  `SharedPreferences`-backed behavior this file had before this fix,
  logging a clear, token-free warning instead of silently losing a real
  session. A token saved under the old plain key is migrated into secure
  storage (and the old copy removed) the first time it is read back. 8 new
  tests (`test/auth_prefs_test.dart`) cover the real round trip, the
  migration, and the no-regression fallback path, all against a fake
  backend (no real platform channel). Same fix and design as
  HYDRA-UMC-DSI's own `network/auth_prefs.dart` (ported, not reinvented -
  both files started identical per this file's own header).
- **New `test/hydra_websocket_reconnect_test.dart`** (5 tests):
  `network/hydra_websocket.dart`'s
  real reconnection logic had no dedicated test - the one related test
  file (`websocket_uri_test.dart`) only covers URI construction
  (`buildConnectionUri()`), not the reconnect cycle itself. Real
  end-to-end tests against a real local `dart:io` WebSocket server
  (`HttpServer` + `WebSocketTransformer`), not a mock - same fixture and
  coverage as HYDRA-UMC-DSI's own `test/hydra_websocket_test.dart` (same
  class, same real gap, ported rather than reinvented). Covers: the real
  handshake gating `WsStatus.connected`, a real settings payload
  delivered end to end, automatic reconnection after a real connection
  drop, `disconnect()` cancelling a pending reconnect for good, and the
  real error reported when nothing is listening.

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

## Earlier history

### 0.0.0+1 and prior (pre-versioning-policy history)

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
