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

The CM5 already runs a real, working server for this: HYDRA-UMC STUDIO's
own `server.ts`. This app speaks the exact contract documented in
[`HYDRA-UMC-STUDIO/docs/REMOTE_API.md`](https://github.com/JuanenRac/HYDRA-UMC-STUDIO/blob/main/docs/REMOTE_API.md) -
the same one HYDRA-UMC SUITE and HYDRA-UMC-ANDROID-CONTROL use, not a
separate mobile-specific protocol. That document itself notes it can
drift from `server.ts`, the real source of truth, so it's worth verifying
against the server's own code rather than trusting the doc alone (the
`/ws` upgrade requires `?token=` unconditionally, and
`POST /api/robot/:id/command` is a real, working atomic endpoint the doc
under-documents relative to what it actually does).

- `POST /api/login` - `admin`/`admin`, every server in this ecosystem's own
  seeded default account (see `server.ts`'s own `users.ts`, which backs a
  real multi-user store: additional lower-privilege "operator" accounts
  can be created from Config > Users in the browser UI) - returns a
  bearer token, required for every write below and for the WebSocket
  upgrade.
- `GET /api/hydra-info` - discover/confirm a candidate IP is actually
  running HYDRA-UMC STUDIO, 404 if this app's own access has been
  disabled server-side (Config > Remote Access, per-client - identified
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

**Discovery:** `lib/network/discovery.dart` does a concurrent scan of
`GET /api/hydra-info` across this device's own real local subnet(s) -
derived from `dart:io`'s `NetworkInterface.list()` rather than a single
hardcoded guess, since a phone's LAN is just as likely to be
`192.168.0.x` or `10.x.x.x` as `192.168.1.x`. `192.168.1.x` is kept only
as a last-resort fallback if interface enumeration itself comes back
empty. Same overall approach HYDRA-UMC SUITE's own `discovery.py` and
HYDRA-UMC-ANDROID-CONTROL's own `Discovery.kt` use. `server.ts` also
publishes a real `_hydra._tcp` Bonjour service; real mDNS support here
(Apple's own `Network.framework`/`NWBrowser` via a Flutter plugin, or the
`multicast_dns` pub.dev package) is a documented future improvement, not
implemented yet - see `mejoras_futuras.txt`.

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
[HYDRA-UMC SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE), served
by [HYDRA-UMC STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO),
which is the human-facing side of
[HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC) itself.
