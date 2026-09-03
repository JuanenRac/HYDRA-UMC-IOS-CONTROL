# HYDRA-UMC iOS Control - Architecture

**Status: real, working app.** See the root [`README.md`](../README.md)'s own "Why Flutter, not native Swift" section for why this iOS/iPadOS app is built in Flutter rather than Swift.

## 1. What this app is

A cross-platform Flutter app that controls a robot running on the
[HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC) platform, reached
through its Compute Module 5 host over the same local Wi-Fi network
HYDRA-UMC STUDIO's own browser UI uses. Its real target is iOS/iPadOS;
Windows is an additionally enabled build target (the only other platform
configured in this repo) used to actually compile/run/test this app's own
logic from a Windows development machine, since a real `.ipa` can only be
built on macOS - see the README's own "Why Flutter, not native Swift"
section.

## 2. Wi-Fi transport (the only transport - no Bluetooth)

The CM5 already runs a real, working server for this: HYDRA-UMC-SERVER's
own `server.ts` - the headless Node/Express/WebSocket backend that used
to be bundled inside HYDRA-UMC STUDIO's own process before the two were
split apart; STUDIO is now a pure static frontend client with no backend
code of its own, talking to this same server over the network exactly
like this app does. This app speaks the exact contract documented in
[`HYDRA-UMC-SERVER/docs/REMOTE_API.md`](https://github.com/JuanenRac/HYDRA-UMC-SERVER/blob/main/docs/REMOTE_API.md) -
the same one HYDRA-UMC SUITE and HYDRA-UMC-ANDROID-CONTROL use, not a
separate mobile-specific protocol. That document itself notes it can
drift from `server.ts`, the real source of truth, so it's worth verifying
against the server's own code rather than trusting the doc alone (the
`/ws` upgrade requires `?token=` unconditionally, and
`POST /api/robot/:id/command` is a real, working atomic endpoint the doc
under-documents relative to what it actually does).

- `POST /api/login` - `admin`/`admin`, every server in this ecosystem's own
  seeded default account (see HYDRA-UMC-SERVER's own `users.ts`, which
  backs a real multi-user store: additional lower-privilege "operator"
  accounts can be created from Config > Users in the browser UI) - returns
  a bearer token, required for every write below and for the WebSocket
  upgrade.
- `GET /api/hydra-info` - discover/confirm a candidate IP is actually
  running a HYDRA-UMC-SERVER instance, 404 if this app's own access has
  been disabled server-side (Config > Remote Access, per-client - identified
  via the `X-Hydra-Client: ios` header this app sends on every request,
  see `hydra_api_client.dart`'s own `_clientHeaders`).
- `GET`/`POST /api/settings` - full application state read/write -
  `GET` needs no auth, `POST` requires an **admin** token specifically
  (an "operator" token gets 403 here). Used for the initial full-state
  load and for `SettingsScreen`'s own diagnostics; NOT the primary write
  path (see below).
- `POST /api/robot/:id/command` - the **primary** write path for every
  mutation this app makes (enable/disable/play/pause/stop/jog/valve/pump/
  speed/vision) - small, single-robot payload; works for a token of
  **either** role (unlike the full-tree `POST /api/settings` above); the
  server computes which `combinedWith` siblings are also affected,
  persists to disk, and broadcasts a WS `"delta"` to every other connected
  client on its own.
- `WebSocket /ws?token=` - live push: the server sends the current state
  on connect, then broadcasts every change (from any client) to every
  other connected client.
- `GET /api/system/metrics` - host CPU/memory/temperature/uptime, no auth
  needed, polled every 5s for the Dashboard.

**Networking stack:** `package:http` for REST, `package:web_socket_channel`
for `/ws` - both dependency-light, well-maintained pub.dev packages
rather than hand-rolled socket code.

**Discovery:** `lib/network/discovery.dart` runs two independent paths at
once from the same "Scan local network" sheet in `login_screen.dart`:
`discoverMdns()` queries the real `_hydra._tcp.local` mDNS/Bonjour service
`server.ts` publishes (via the `multicast_dns` pub.dev package), and
`scanSubnets()` is a concurrent brute-force `GET /api/hydra-info` sweep
across this device's own real local subnet(s) - derived from `dart:io`'s
`NetworkInterface.list()` rather than a single hardcoded guess, since a
phone's LAN is just as likely to be `192.168.0.x` or `10.x.x.x` as
`192.168.1.x`. `192.168.1.x` is kept only as a last-resort fallback if
interface enumeration itself comes back empty. This app is the first of
the ecosystem's 3 remote clients to add real mDNS - HYDRA-UMC SUITE's own
`discovery.py` and HYDRA-UMC-ANDROID-CONTROL's own `Discovery.kt` still
only scan subnets - added additively, without dropping the subnet-scan
fallback either of them still relies on: iOS silently drops multicast
*receive* for any app without Apple's dedicated Multicast Networking
entitlement (not something a plain `flutter build ios` grants for free),
so `discoverMdns()` failing quietly on an unentitled iOS build is expected
behavior, not a bug - `scanSubnets()` keeps working independently either
way.

## 3. Bluetooth transport - not built, and not planned until server-side support exists

**Honesty note, matching the rest of this ecosystem's documentation
convention:** there is still no Bluetooth service of any kind running on
a HYDRA-UMC's CM5 - no BLE GATT server, nothing. This is blocked on
HYDRA-UMC's own CM5-side software, not this app.

## 4. Real source layout

```text
lib/
├── main.dart
├── models/        server_info.dart, hydra_state.dart
├── network/       hydra_api_client.dart, hydra_websocket.dart, discovery.dart, auth_prefs.dart
├── state/         robot_view_model.dart
└── ui/            login_screen.dart, main_screen.dart, dashboard_screen.dart,
                   control_screen.dart, camera_screen.dart, three_d_screen.dart,
                   settings_screen.dart, widgets/
```

See the root README's own "Repository Structure" section for what each
file does - not duplicated here to avoid the 2 documents drifting apart.

## 5. Relationship to the rest of the ecosystem

See the root [`README.md`](../README.md)'s own "Related Projects"
section. Direct counterpart to
[HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL)
(no code shared, same API contract, feature parity is a design goal even
though the 2 codebases are independent), speaks the same contract as
[HYDRA-UMC SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE) - both
talk directly to [HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER),
the headless backend that owns this API; the same server also backs
[HYDRA-UMC STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO)'s own
browser dashboard, which is now a pure frontend client of it rather than
bundling its own backend, and is the human-facing side of
[HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC) itself.
