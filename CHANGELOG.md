# Changelog

All notable changes to this project are documented here.

## [Unreleased]

- **The tests on the iPhone simulator run on their own:** `xcodebuild test` on a simulator of the macOS runner now runs once a week and on a pull request to main that changes the app, the iOS project or the Dart packages (it was started by hand only), with the Dart packages cached and a newer run of the same pull request cancelling the older one. It never runs on a push.
- **Strong biometric lock (Settings, off by default; port of the Android option):** while the Face ID / Touch ID gate is on, a second switch moves the saved session (token, user name, refresh token) to a Keychain item whose access control is the currently enrolled biometrics, so the system itself asks for the biometric to read it and nothing can fake the check; a face or finger enrolled later ends the saved session. The gate does not ask a second time in this mode. The app keeps a session and not a password, so the Android difference is that nothing is moved out of a form; iOS has no weak biometric class, so no sign-in method is lost (the warning of the Android option does not apply and the text says so). The texts are in the eight languages. `test/strong_session_backend_test.dart`. Not run on an iPhone: the Keychain prompt and the invalidation by a new enrolment need a device.
- **A read-only server is told apart from a robot in safe mode (text in the eight languages):** a 423 `server-read-only` now reads "The server is in read-only mode: the command was not sent. Only STOP and the safe-mode disable go through. An administrator can switch it off." instead of the safe-mode sentence of a single robot. The wording and the mapping are in place; they take effect with the SDK release that carries the new error kind (until then the old sentence is shown). `test/server_read_only_text_test.dart` and a case in `test/robot_view_model_safe_mode_test.dart`.

- **Listen only can be set for the server in use alone (off by default):** next to the general switch, Settings has a switch for the server the app is connected to (the list of `host:port` is kept on the phone). While it is on, that server gets no command but STOP and the safe-mode disable and no write but the session, and a held jog stops; other servers are not affected, and the general switch still covers all. The texts are in the eight languages. Same behaviour as the Android app. `test/listen_only_servers_test.dart`. Not run on an iPhone.
- **Widget tests of the audit dialog:** 6 tests against a real local server (a recorded line, the check of the chain when asked, the filters that ask the server again, an empty record, a record the server keeps off, a refusal shown as a sentence); no behaviour changes.
- **Tests of the words of the connections and server options dialogs:** 6 tests that read every kind of client, action, failure, "ago" unit, protection that is lowered and source of an option in the eight languages and check that none is empty or repeated; no behaviour changes.
- **README: the platform statement:** a note says that where the README speaks of the CM5 it means the pilot bench that runs today, and that the target platform of HYDRA-UMC, an NVIDIA Jetson Orin NX 16 GB, is a design that has not been built or tested.
- **Listen only dims and disables the controls it blocks (port of the Android app):** the joystick pad, the base-rotation buttons, HOME/RESET, PLAY, PAUSE, the enable button, the valves and pumps and the sliders are disabled and the last two groups drawn at 40 % opacity while the switch is on, like the DSI; STOP stays active. Not compiled or run on an iPhone. The opacity is a pure function (`ListenOnlyGate.controlOpacity`) with a test.
- **Listen only (off by default; port of the Android app):** a switch in Settings makes the app show the robots and their data without sending any command. While it is on, a banner on the Control tab says so and the view model drops every command except STOP and the safe-mode disable (the held jog goes through the same check and stops when it is switched on), because refusing a stop would be the unsafe side. The choice is kept across restarts. Texts in the eight languages; 4 tests against a real local server. Not compiled or run on an iPhone. The same switch also refuses, at the door of the network, every other write to the server (settings, push and presence registration, files) with a 423 that never leaves the phone, except STOP and the sign-in (`network/listen_only_gate.dart`, 3 more tests).

- **The comments of the view model and the screens state the contract, not the history:** the long narrative comments of `robot_view_model.dart` (sign-in and renewal, the socket, the atomic command, the global STOP, reservations) and of the headers of the cache, the biometric helper, the 3D screen, the assistant dialog and the telemetry screen say what each piece does and promises; no behaviour changes. A touch through an overlay does not apply on iOS (the system gives no app a way to draw over another one), so there is no switch for it.

- **The Live Activity channel, the stop shortcut and the quick action of the icon have Swift tests, and the header of the network discovery tells the contract:** 11 new tests on the simulator cover how the Live Activity takes its state from the arguments (every field, the defaults, a field of another type, the stale date), that an unknown method is refused, that updating or ending with no activity running is harmless, that starting answers true or false, that the stop intent leaves one request for the app (taken once), that the app offers one shortcut that opens the app, that the quick action of the icon asks for the stop, and that finishing a dictation with nothing pending is harmless. The line coverage of the Swift code of the app goes from 47 % to 62 % (the Live Activity file from 12 % to 82 %, the stop shortcut to 100 %); the dictation file stays at 23 % because it needs the permission prompts of a real phone. Nothing was run on an iPhone.
- **The settings, the sign-in screen and the 3D screen listen to the fields they draw, not to the whole view model:** the settings are redrawn when one of their switches, the server, the connection state, the pinned certificate, the role or the language change; the sign-in screen when the pairing or the last error change; the 3D screen only when the address of the viewer, the robot or the sign-in change (the page is no longer asked to rebuild for the metrics tick or for a robot that moves); `test/selector_rebuild_test.dart` checks both directions for each (3 more tests; 554 in all).

- **The dashboard, the log tab, the ecosystem tab and the main screen listen to the fields they draw, not to the whole view model:** each is redrawn when its robots, its log lines, its project list or its title, connection label and saved-data banner change, and no longer for the metrics tick or for a field that is not its own; `test/selector_rebuild_test.dart` checks both directions for each (5 more tests; 551 in all).

- **The camera screen listens to the fields it draws, not to the whole view model:** it is redrawn when its robots, their cameras, the server address or the media headers change, and no longer for the metrics tick or for a field that is not its own; `test/selector_rebuild_test.dart` checks both directions (2 more tests).

- **The global STOP is tested to be on screen where robots are driven:** `test/stop_presence_test.dart` (2 widget tests) checks that the Control tab carries the large global STOP once a robot is selected and that the main screen carries the one of its bar, with or without a robot.

- **The Swift tests report their line coverage on the simulator:** the manual workflow `ios-xcodebuild-test.yml` now runs `xcodebuild test` with code coverage on, keeps the result bundle and prints the coverage of the targets and the least covered files of the app (`xccov`) in the summary of the run.

- **The comments of the view model and of the 3D screen say what holds now, not the story of the bug:** the longest narrative blocks (the debounce of a command, the generation guard of the rollback, the saved-data flag, the biometric gate, the snapshot before a change and the reason for the controller of the 3D page) were rewritten as the contract they describe; the history stays in this file.

- **The control screen is redrawn only for what it shows (a first step of the selectors):** it used to listen to the whole view model, so every change of anything else (the state of the connection, the saved-data banner, a voice reply) redrew the jog pad, the sliders and the buttons. It now listens to one text that holds exactly what it draws or decides from (the robots, the reservations, the limits and the arming of the jog, the requests under way, the Work of the robot, the switches of PLAY and HOME/RESET, the role and the state of the STOP), and each of those changes still redraws it. `test/selector_rebuild_test.dart` counts the widgets Flutter rebuilds for what is not the screen's and for nine changes that must redraw it (2 tests).

- **The connection diagnostics are tested:** `test/connection_diagnostics_test.dart` (8 tests) covers which trust applies to a connection (plain http, pinned fingerprint, own authority, system certificates), the figures of the probes (smallest, average, largest, lost, none answered), and a report that names the address, the trust, each probe and the link, holds no password, token or certificate, says `unknown` for what the server did not tell and never goes past its line limit.

- **The Swift tests ran in full on the simulator, with the push token tests of the Live Activity passing:** the manual workflow now prints what each failed check said, and the reply of the watch link waits up to 20 seconds in the tests (a cold simulator took longer than 5 seconds once and made a test of the stop request of the watch fail).

- **The Live Activity can be refreshed by the server while the app is suspended, off by default:** a new switch under the Live Activity (`liveActivity.serverPushEnabledByDefault` is false) asks the system for the push token of the activity when it starts, hands it to `POST /api/push/live-activities` with the robot on the card, and takes it back with `DELETE` when the activity ends, when the job finishes, when the session ends, when a new token replaces it and when the switch is turned off. A token that arrives with nothing running, with the switch off or twice is dropped; a server without the route reads as unavailable and a failure never shows an error or stops the card. The server decides how much the card shows. Texts in 8 languages; 15 more tests in Dart and 3 in Swift (the hexadecimal form of the token). Needs the SDK 0.6.0 contract; not run on an iPhone.
- **28 real Swift tests of the Runner target, run on the iOS simulator:** 11 of them cover the watch link (no alert is queued when no watch can be reached, an unknown or malformed message of the watch is not accepted, the stop request goes to Dart and only a real `true` is accepted, the presence is passed on, the second tap of a spoken order gets the answer of Dart) and the dictation (arguments refused, cancel when nothing listens, unknown methods refused). The first 17: `ios/RunnerTests/RunnerTests.swift` drives the real method channels of the app through a loopback messenger (no engine) and covers the global stop request (taken once, a request older than the limit forgotten, the listener told), the pairing links (only the links of this app are kept, handed over once, the last wins, case-insensitive scheme and host, unknown methods refused), the alerts channel (arguments refused, unknown method refused) and the state of the Live Activity (round trip, difference, incomplete document refused). The manual workflow `iOS tests on the simulator` ran them: all passed. They are not a phone; the Keychain, the push token and the speech recogniser need a device.
- **The Swift side is built and tested on the iOS simulator by a manual workflow:** `ios-xcodebuild-test.yml` runs on a macOS runner of GitHub (no Mac of the owner), generates the iOS configuration without signing and runs `xcodebuild test` of the Runner scheme on an iPhone simulator. Nothing is signed or uploaded. Today the only Swift test is the template one, so it proves that the Runner, the widget extensions and the watch app build; real tests of the Swift code still have to be written, and a run on a phone stays pending.

- **The HTTP client talks through the shared package of the SDK:** `HydraApiClient` extends the shared `HydraApiCore` (headers, bearer token, controller id, `If-Match`, the numbering of motion commands, the renewal of an expired session and the reading of error answers) over a small `PackageHttpTransport` adapter, and keeps its public API; the choice between http and https and the typed endpoints stay in the app. The error type (`HydraError`), the connection history, the server access options and the preferences (`ClientPrefs`, `AuthPrefs`) now come from the same package, with this app's own wording and storage adapters. The renewal tests go through the real client.

## [0.3.5] - The stored session follows the rules shared with the other mobile apps: AuthPrefs keeps the host, the port, the scheme and its other flags, and hands the token, the user name and the refresh token to SessionStore of the shared... (and 1 more changes)

- **The stored session follows the rules shared with the other mobile apps:** `AuthPrefs` keeps the host, the port, the scheme and its other flags, and hands the token, the user name and the refresh token to `SessionStore` of the shared Dart package, so a fix to the handling of the session lands in every app. A save that fails half way now reverts the user name as well as the token, and a save without a refresh token no longer drops the one kept in memory. The app also keeps its install marker (`purgeStaleKeychainOnFirstRun`) on the same store. The SDK is pinned to the commit that carries it.

- **The server entry and the views over the settings tree come from the shared package of the SDK:** `ServerInfo`, `HydraState`, `ControllerView` and `RobotView` are no longer kept as a copy in the app (the file re-exports them), so the two Flutter apps cannot drift apart on them; no change in behaviour.

## [0.3.4] - The root of the app no longer redraws on every message of the model: the application shell listens only to the language the person chose, and the gate between the unlock, sign-in and main screens only to the lock and the session. (and 1 more changes)

- **The root of the app no longer redraws on every message of the model:** the application shell listens only to the language the person chose, and the gate between the unlock, sign-in and main screens only to the lock and the session.

- **The reading of a pairing link comes from the shared package:** `util/pairing_link.dart` now re-exports `PairingLink`, `PairingOffer`, `PairingProblem` and `PairingResult` from the SDK package `hydra_umc_app_common` (pinned to a newer commit), the same code the DSI app uses; a test checks that the limits of the package are the ones of the generated command contract. Nothing changes for the user.

## [0.3.3] - A test signs in against the one stand-in server of the SDK: fakeserversessiontest.dart starts the vendored hydrafakeserver.py as a process (skipped without Python) and drives the real client through sign-in, a refused password... (and 2 more changes)

- **A test signs in against the one stand-in server of the SDK:** `fake_server_session_test.dart` starts the vendored `hydra_fake_server.py` as a process (skipped without Python) and drives the real client through sign-in, a refused password and the global STOP; `tools/sync_sdk_answers.py` keeps the copy identical to the SDK.

- **The second contract, the HOME/RESET rules and the WebSocket client come from the shared package of the SDK:** the conditional writes, the `table` command, the audit chain, the reservations and safety limits, the rules of HOME/RESET and the live-sync socket moved to `clients/dart_app_common` (pinned to a commit of the SDK), which the iOS app and the panel app now share instead of keeping a copy each; what stays here is the prefix of the controller id, the phrase for each HOME/RESET reason (it needs the localizations of this app) and the mapping of the socket errors to the errors this app shows. A new test checks the contract of the continuous commands, the prefix and the address of the socket, and the vendored server answers follow the SDK file again.

- **The build test of the repository compiles only on CI or when allowed:** for the stacks that compile (`rust`, `go`, `android`, `flutter`, `firmware-c`), `tools/build_test.py` prints `BUILD_TEST=SKIPPED` with exit status 2 on a plain PC, never a pass; `ALLOW_LOCAL_BUILD=1` allows it and a CI runner always may. The `python` and `node` stacks are not locked.

## [0.3.2] - The models are tested with the answers the SDK generates from the server inventory: test/serveranswerstest.dart replays a minimal and a full body of the server-information, stop-all, ecosystem-status and sign-in routes and a... (and 4 more changes)

- **The models are tested with the answers the SDK generates from the server inventory:** `test/server_answers_test.dart` replays a minimal and a full body of the server-information, stop-all, ecosystem-status and sign-in routes and a refusal of the sign-in against the app's models; the vendored `test/fixtures/server-answers.json` is kept identical to the SDK file by `tools/sync_sdk_answers.py --check`, which the CI validator runs.

- **The code the two Flutter apps copied by hand comes from one package:** the SHA-256 of the audit chain, the result of the global STOP and the rules of the PLAY confirmation are read from `hydra_umc_app_common` (in the SDK, pinned to a commit) through the same file paths as before; a workflow now analyzes and tests the app on every push.

- **The 3D view stops in the background:** when the app is backgrounded the embedded viewer is replaced by a blank page (its socket and render loop stop) and it loads again on return, as the camera image already did. A momentary `inactive` state (a system alert, the app switcher) keeps it.

- **An expired session is renewed under the http client too:** `lib/network/renewing_client.dart` wraps the client of the server API; a request that carried a bearer token and was answered with a 401 or a 403 TOKEN_EXPIRED / TOKEN_INVALID asks the session for a new token (the same single-flight renewal) and is sent once more with it; login and refresh (no bearer token), role refusals and a failed renewal reach the caller untouched. 7 new tests.
- **The server routes the app calls are fixed and checked:** `tools/check_rest_routes.py` lists the `/api/...` routes found in the sources, compares them with `docs/rest_routes.json` (a route can only be added or dropped on purpose) and, when the shared contracts are next to the repository, fails if a route is not in the server contract. The CI validator runs it.

## [0.3.1] - Bench test script: docs/BENCHTESTS.md lists the checks that need an iPhone, an iPad and an Apple Watch (lifecycle, 3D view, claim renewal, jog stop), all marked not executed. (and 19 more changes)

- **Bench test script:** `docs/BENCH_TESTS.md` lists the checks that need an iPhone, an iPad and an Apple Watch (lifecycle, 3D view, claim renewal, jog stop), all marked not executed.

- **The renewal of an expired session lives in its own class:** `lib/state/session_manager.dart` renews the session once however many requests and socket events notice the expired token together, repeats the request once, and leaves every other answer (a permission refusal, a server error, a failed renewal) as it came; the view model only says how a renewal is done. Same behaviour as before, now tested without the view model.
- **Pairing by link always requires the certificate fingerprint:** a link without `fp` is refused with its own message (in the eight languages) instead of offering a connection that would not be pinned; the confirmation window no longer has a "no fingerprint" branch, and accepting always requires TLS and pins that certificate. New tests for every way the fingerprint can be missing.
- **Continuous jog with a dead-man (off by default):** a switch in Settings shows buttons on the Control screen that move an axis while they are held, the same as the Android app: `jogStart`, a heartbeat every 100 ms and `jogStop`. The axis is stopped, with a stop sent as urgently as a STOP and tried again, when the button is released or the finger slides off, with STOP or the global STOP, when the screen is left or the app goes to the background, when the connection drops, after two missed heartbeats, after 30 seconds, when the link is bad and when the server refuses a heartbeat; a stop the server did not confirm says so. It is refused, with a sentence of its own, when the robot is offline, in safe mode or running a trajectory, while a STOP is pending, when the jog must be armed and is not, for a session that is neither operator nor administrator and on a server that does not know the commands. Every number lives in `docs/robot_command_contract.json` (identical to the Android file). Tested on the Dart VM against a fake clock and server; the commands themselves wait for the server (not implemented there yet).
- **Link indicator and block on a bad link:** the Control screen shows how fast the server answers (a coloured dot, the grade and the last round trip), measured with one small request every two seconds while the connection is up and the app is on screen. A second switch, on by default, refuses the continuous jog and stops a running one when the slowest recent answer reaches the blocking time or the server stops answering.
- **Pairing by link (off by default):** a switch in Settings and on the sign-in screen, with a box to paste a link, and the URL scheme `hydra-umc` in `Info.plist` so the camera of the phone can open `hydra-umc://pair?host=..&port=..&fp=..&name=..` with this app. The link is validated strictly (a host, a port, a SHA-256 fingerprint, a bounded name, no repeated fields), the app shows what it read and asks before it keeps anything, and with a fingerprint it sets the connection to require TLS and pins that certificate. Nothing is read while the switch is off.
- **Alerts to the Apple Watch:** a lost or restored connection, a robot offline or in safe mode and a STOP not confirmed or confirmed are pushed to the paired watch as messages that are never queued, in the language of the app. They are rationed (the same event at most once per window, a minimum gap, a few per minute; a critical one is never held back) and need the Apple Watch option as well as their own switch.
- **Relays of the watch (off by default):** two switches pass the presence heartbeat of the operator and the second tap of the two-step confirmation of a spoken order from the watch to the server. They wait for endpoints that the server does not have yet, and a server that answers 404 makes the relay go quiet.
- **Work selector:** the Control screen shows the Work loaded in the robot and lists the work files of the folder of the robot on the server; picking one reads it, checks its points the way the server does and loads it with the `trajectory` command. It never starts the playback, and a robot that is playing, in safe mode or offline is refused with a sentence. Texts for all of this in the eight languages, the same as the Android app.
- **Not compiled in Xcode nor tried on an iPhone or a watch:** the Swift parts of these features (the URL scheme and the pairing channel, the alerts and relays of the watch link) were written without a Mac; the Dart logic is covered by tests with fake clocks, servers and bridges.

- **Ecosystem tab:** the Telemetry screen has a second tab, Ecosystem, with the project manifests that the server finds next to itself (`GET /api/ecosystem/status`), grouped by family, with a green or red bulb only for the projects that declare a network service and a refresh button; a server that does not know the route says so in a sentence. It is read on entering the tab and by the button, never polled, and two reads are never closer than a time set in `docs/ios_feature_contract.json`. Texts in the eight languages, the same as the Android app.
- **Connection diagnostics:** an entry of Settings measures a few small reads of `GET /api/hydra-info` and shows the address and scheme, how the certificate is trusted (none, the pinned fingerprint, an own authority or the system), the versions of the server and of this app, the latency (smallest, average, largest, probes without an answer), the grade of the link and the state of the live connection. A button copies a plain-text report that holds no password and no token. The grade of the link is a port of the Android `LinkHealth` (the slowest recent answer decides), with its limits read from `docs/robot_command_contract.json`.
- **Notifications on this phone (off by default):** a switch in Settings asks the system for permission and, once given, shows a local notification when a job finishes, when a robot goes offline or into safe mode and when the connection stays lost, in the language of the app. They are rationed (the same alert at most once per window, never two closer than a minimum gap, never more than a few per minute), the first reading after signing in only sets the baseline, and they only appear while the app is open; the push notifications of the server cover the rest. A refused permission leaves the switch off.
- **Live Activity (off by default):** a switch in Settings shows the running trajectory (robot, state, step of the total) on the lock screen and in the Dynamic Island while the app is open; it starts when a job plays, follows the steps no faster than a set gap, and ends when the job ends (a finished job stays on the lock screen for a while) or the session does. It only shows a status and has no button. The Swift half and the widget sources are written; the widget extension still needs its target in Xcode.
- **Apple Watch (off by default):** a switch in Settings sends the state of the running job to a paired watch and lets the watch ask the phone for the global stop; the phone checks that the request is fresh and the switch is on, makes the same global stop as the STOP button with its own session, and tells the watch whether it accepted. The watch holds no session of its own. The watch app sources are written; its Xcode target is not created yet.
- **Dictation for the assistant (off by default):** a switch in Settings adds a microphone button to the assistant that writes what you say into the text box with the Speech framework of iOS. The audio is recognised on the iPhone itself; a language without a recognizer on the device says so instead of listening, unless a second switch allows the online recognition of Apple. The text is never sent by itself: you read it and press Send, and the server still asks for the confirmation of any order. Permission texts and messages in the eight languages.
- **Contracts:** `docs/robot_command_contract.json` is again identical to the copy in the Android app (it gains the dead-man jog, link health, pairing, watch alerts, relays and work files, all used by this app now), and `docs/ios_feature_contract.json` holds the settings of the features above; `tools/gen_command_contract.py` writes the constants of both and the validation fails when they differ.
- **Not compiled in Xcode nor tried on an iPhone or a watch:** the Swift parts (notifications, dictation, Live Activity, the link to the watch) and the sources of the Live Activity widget and the watch app were written without a Mac. The logic is covered by tests on the Dart VM (the planners, the rationing, the report, the surfaces with fake bridges, the view model against a local server) and the Swift files are held to the Dart side by a test that reads them, but no one has built or run them on a device.

- **A refused HOME / RESET says so:** when the server will not send the robot home (the pose is not the home pose of its model, or a joint would leave its range) the app says the robot did not move, in the eight languages, the same as the Android app.

- **Wording aligned with STUDIO:** nine texts that read differently from STUDIO although they mean the same (arm the jog, the reservations, the unreachable server, the ended session and others) now use the words of STUDIO in every language, the same as the Android app.

## [0.3.0] - HOME/RESET with a two-step confirmation, global stop from outside the app, push notifications, Bluetooth LE, the Parol6 on its real kinematics, numbered motion commands, reservations kept alive and the access options of the server

- **HOME/RESET:** a button on the Control screen that takes the selected robot to its zero position through the `reset` command of the server, the same as the Android app. It is off by default (a switch in Settings turns it on and the choice is kept) and it asks twice, in order and within a time limit, before anything is sent. It is refused with a sentence of its own, in the eight languages, when the robot is playing, in safe mode, offline or without a position, while a STOP is being sent or was not confirmed, while a jog is on the wire, when the jog must be armed and is not, and for a session that is neither operator nor administrator (the server decides the role again); a server that does not know `reset` is told apart and remembered. The command carries a rising number like the jog. The default, the number of confirmations and their time limit live in `docs/robot_command_contract.json` (identical in HYDRA-UMC-ANDROID-CONTROL) and reach the app through the generated constants. Tested against a local fake server and a widget test: no robot is involved.
- **The commands go through a repository outside the view model:** `lib/state/robot_command_repository.dart` keeps the revision of each robot, retries a stop when nobody answers, plays a `table` move as jogs on an older server, counts the jogs on the wire, debounces continuous commands under their own name and measures each answer, the same split as the Android app; the command names and limits are generated from `docs/robot_command_contract.json` (identical to the Android file) by `tools/gen_command_contract.py`, and the validation fails when they differ. Tested against a fake server.
- **A reservation held here is kept alive:** while the Control screen is open, a reservation of this device is asked for again shortly before it ends, so a long session does not lose the robot, and the reservations of the device are released when the person signs out.
- **The server load no longer rebuilds every screen:** the reading that arrives every few seconds goes to a value listened to only by the bar of the Dashboard that shows it.

- **Global stop from outside the app:** a shortcut for the Shortcuts app, Siri, Spotlight and the Action button, and a quick action on the app icon (long press), with their names and phrases in the eight languages. They open the app and make the very same global stop as the STOP button (`POST /api/stop-all` with the session of the person, and the one-by-one fallback), so the contract and the handling of the token are unchanged. A request waits for a session for one minute at most and is dropped after that, so a stop asked for long ago never fires later. Built in the macOS CI, never run on an iPhone.
- **Push notifications from the server:** a switch in Settings (off until the person turns it on) asks for the permission of the system, takes the device token of the phone and registers it with the server together with the language of the app, so the server can tell the phone through the Apple push service when a job finishes or a global stop is issued; the token is taken off the server when the switch is turned off or the person signs out. A server that has push notifications switched off says so in the switch. Texts in the eight languages; the entitlement and the native half are in the iOS project. Tested against a fake system and a local server, never against a real iPhone.
- **Bluetooth LE (experimental):** an entry of Settings searches for HYDRA-UMC devices nearby (only those that advertise the HYDRA service, or all of them on request) and reads the state of one over the same Bluetooth contract as the Android app: framed messages in both directions, a service check, notifications, one write at a time, automatic reconnection with growing delays and a clear message in the eight languages for every failure. While connected this way the phone does not talk to the server. Built on flutter_blue_plus 1.x (BSD-3-Clause); the permission text of iOS is in the eight languages. It is tested only against a simulated link, never against a real device.
- **Jog of a Parol6 on its real kinematics:** the jog pad resolves a combined move once against the real chain of the arm (the same solver as the studio and the Android app) and every axis command of that tick carries the same joints, instead of leaving the generic formula of the server to guess them. A target outside the reach of the arm is refused before anything is sent, with a sentence in the eight languages.
- **Base rotation (J1) buttons:** two buttons beside the jog pad turn the base alone by the chosen step; they work for every model, stop at the real limit of a Parol6 (a generic -180 to 180 for the others) and send nothing once the limit is reached.
- **Motion commands are numbered:** a jog, a table move, a joint move and a stop carry a rising number, so the server can refuse a jog that arrives after a later stop; a refusal for arriving out of order is told apart from a reservation and shown in the eight languages.
- **Who connects to the server:** a Connections button in the access panel opens a simple list of the apps the server has seen (kind, user, version, local network or from outside, the sessions open now, the sign-ins that worked or were refused, how long ago) and the latest sign-ins, refused sign-ins, sign-outs and ended sessions, read from the connection routes of the server. An administrator sees every entry and any other account only its own; no password or token is in either list, and an address appears only if the server was told to keep it. It says so plainly when the server is too old to offer them. Texts in the eight languages.
- **Access options of the server in Settings (administrators only):** an entry of Settings opens nine switches read from the server configuration: the health route without a sign-in, the announcement of the global stop, keeping the address of each client in the history of connections, the camera pictures without a ticket, a token in the WebSocket address, the blanking of secrets in the log, the signature of a spoken confirmation, the password of an IP camera handed over through the environment of its process and TLS switched on by a new installation. Each shows where its value comes from (default, saved from a screen, or fixed by the environment of the server, which locks it), only what changed is sent, every change that lowers the protection asks first, and a server that does not offer an option does not show it. Texts in the eight languages.

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
