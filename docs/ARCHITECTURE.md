# HYDRA-UMC iOS Control - Architecture

**Status: scaffolding only.** This document describes the intended design
so real implementation work has a starting point - the actual SwiftUI
app is not built here (per the project owner's own instruction: "la app
la voy hacer yo"). Nothing under `Sources/` is real app logic; every file
there is a placeholder documenting where a piece belongs.

## 1. What this app is

A native iOS/iPadOS app that controls a robot running on the
[HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC) platform, reached
through its Compute Module 5 host - either over the same local Wi-Fi
network HYDRA-UMC STUDIO's own browser UI uses, or over Bluetooth for a
closer-range, no-network-setup-needed control path.

## 2. Wi-Fi transport (primary - real API exists today)

The CM5 already runs a real, working server for this: HYDRA-UMC STUDIO's
own `server.ts`. This app should speak the exact same contract documented
in [`HYDRA-UMC-STUDIO/docs/REMOTE_API.md`](https://github.com/JuanenRac/HYDRA-UMC-STUDIO/blob/main/docs/REMOTE_API.md) -
the same one [HYDRA-UMC SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE)
uses, not a separate mobile-specific protocol:

- `GET /api/hydra-info` - discover/confirm a candidate IP is actually
  running HYDRA-UMC STUDIO (product name, API version, robot/controller
  counts) before connecting to it for real.
- `GET`/`POST /api/settings` - read and write the full application state
  (robots, jobs, trajectories, configuration) - read-modify-write, no
  granular per-field update exists server-side.
- `WebSocket /ws` - live push: the server sends the current state on
  connect, then broadcasts every change (from any client - a browser tab,
  this app, HYDRA-UMC SUITE) to every other connected client. A change
  made from this app should show up live in an open HYDRA-UMC STUDIO
  browser tab, and vice versa - not just on next manual refresh.

**Recommended Swift networking stack:** `URLSession` for the REST calls
(no third-party HTTP client needed for 2 simple JSON endpoints), and
`URLSessionWebSocketTask` (native since iOS 13, no third-party WebSocket
library needed either) for `/ws`. Keeping this dependency-free is
deliberate - see `Sources/HydraUMCControl/Networking/` below for exactly
where these belong.

**Discovery on a real network:** the REMOTE_API.md document itself notes
no mDNS/Bonjour service is advertised yet (a real gap, not an oversight -
see that document's own "Future work" section). Until that exists
server-side, this app has 2 realistic options: (a) let the user type in
a HYDRA-UMC's IP/hostname manually (simplest, always works), or (b) scan
the local subnet's likely IP range hitting `/api/hydra-info` on each
candidate (same approach HYDRA-UMC SUITE's own network scanner uses -
see that project's own `discovery.py` for the reference algorithm once
it exists). Bonjour/mDNS (`NWBrowser` in `Network.framework`) becomes the
much better option once the CM5 side actually advertises a
`_hydra-umc._tcp` service - track that against REMOTE_API.md's own
"Future work" note rather than building Bonjour support against nothing.

## 3. Bluetooth transport (secondary - NOT backed by any server-side support yet)

**Honesty note, matching the rest of this ecosystem's documentation
convention:** there is currently no Bluetooth service of any kind running
on a HYDRA-UMC's CM5 - no BLE GATT server, no Bluetooth Classic profile,
nothing. Before this transport can be built on the iOS side, HYDRA-UMC's
own CM5-side software needs a corresponding BLE peripheral service (most
likely a BlueZ-based GATT server process on the CM5's own Linux OS,
exposing a custom service/characteristic set that mirrors a useful subset
of the Wi-Fi API above - short-range jog control and status readout are
the obvious first candidates, not full state sync, given BLE's much lower
throughput than Wi-Fi). That server-side work does not exist yet anywhere
in this ecosystem as of this document's own writing (15 August 2026) -
track it as a HYDRA-UMC-repository prerequisite, not something to build
from the iOS side alone.

Once that CM5-side service exists, the iOS side would use
`CoreBluetooth`'s `CBCentralManager`/`CBPeripheral` APIs - see
`Sources/HydraUMCControl/Bluetooth/` below for where that implementation
belongs once it's real.

## 4. Suggested source layout

```text
Sources/HydraUMCControl/
├── App.swift                  # @main entry point (placeholder)
├── Views/                     # SwiftUI views (placeholder)
├── Networking/                # URLSession REST client + URLSessionWebSocketTask live-sync client (placeholder)
└── Bluetooth/                 # CoreBluetooth CBCentralManager client, blocked on CM5-side GATT service (placeholder)
```

## 5. Relationship to the rest of the ecosystem

See the root [`README.md`](../README.md)'s own "Related Projects" section
for the full picture. The 3 things worth knowing specifically for this
app's own design: it speaks the exact same REMOTE_API.md contract as
[HYDRA-UMC SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE) (don't
invent a separate mobile protocol), it has a direct Android counterpart
([HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL))
that should stay in sync with this app's own feature set even though the
2 codebases don't share code, and [HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC)
is the actual hardware/firmware project this app ultimately controls.
