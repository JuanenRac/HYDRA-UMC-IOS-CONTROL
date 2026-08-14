<p align="center">
  <img src="images/HYDRA_UMC_IOS_CONTROL_BANNER.jpg" alt="HYDRA-UMC iOS Control Banner" width="100%">
</p>

# 📱 HYDRA-UMC IOS CONTROL

**Status: scaffolding only, no real app yet.** A native iOS/iPadOS app that controls a robot on the [HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC) platform over Wi-Fi (speaking the same [`REMOTE_API.md`](https://github.com/JuanenRac/HYDRA-UMC-STUDIO/blob/main/docs/REMOTE_API.md) contract [HYDRA-UMC SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE) uses) or Bluetooth (blocked on future CM5-side work - see below). See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full design. The actual SwiftUI implementation is being built by the project owner - this repository provides the architecture write-up, a minimal Swift Package source layout, and VSCode configuration for Swift development, not real app code.

## 🏗️ What exists so far

- `docs/ARCHITECTURE.md` - the real design doc: Wi-Fi transport (real, working API today), Bluetooth transport (honestly flagged as blocked on a CM5-side BLE service that doesn't exist yet anywhere in this ecosystem).
- `Package.swift` + `Sources/HydraUMCControl/` - a Swift Package skeleton (`App.swift`, `Views/`, `Networking/`, `Bluetooth/`), every file a documented placeholder, not implementation. A real installable iOS app still needs an Xcode project wrapping this - not created here.
- `.vscode/` - recommended Swift extensions, editor settings, and build tasks (`swift build`/`swift test` against the package; a placeholder `xcodebuild` task for once a real Xcode project exists).

## 🔗 Related Projects

This project is part of a larger robotics ecosystem by the same author (JuanenRac / Electro Hobby 3D). Worth knowing about, since a request might actually be about one of these rather than this repository:

**HYDRA-UMC platform** — the multi-robot micro-factory cell
- **[HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC)** — the motherboard itself: Raspberry Pi CM5 host + dual-core STM32H745 real-time co-processor, orchestrating up to 8 distributed robot arms over CAN-OTA/SPI-OTA. Own hardware + firmware, GPL-3.0/CERN-OHL-S v2/CC BY-SA 4.0.
- **[HYDRA-UMC STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO)** — web-based control dashboard for HYDRA-UMC: multi-robot 3D visualization, kinematics/trajectory recording, CAN-OTA flashing and testing for the whole platform. React + Vite + Three.js.
- **[HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL)** — Android control app for HYDRA-UMC over Wi-Fi/Bluetooth. Scaffolding stage (architecture doc + VSCode/Gradle project layout), real implementation pending.
- **HYDRA-UMC-IOS-CONTROL** *(this repository)* — iOS control app for HYDRA-UMC over Wi-Fi/Bluetooth. Scaffolding stage (architecture doc + VSCode/Swift Package layout), real implementation pending.
- **[HYDRA-UMC-SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE)** — desktop (Python/PySide6) swarm command center: multi-controller network discovery, live bidirectional sync, real 3D robot viewport, Photoshop-style dockable workspace. Real and working, not a placeholder.

**URTC platform** — the tool head controller every HYDRA-UMC robot arm carries
- **[URTC](https://github.com/JuanenRac/URTC)** — Universal Robot Tool Controller: STM32F303-based CAN bus tool head controller, 25 fully-implemented tool profiles, CAN-OTA firmware update.
- **[URTC Flasher](https://github.com/JuanenRac/URTC-FLASHER)** — desktop CAN-OTA + full-chip SWD/JTAG flashing tool for URTC boards (Windows/Linux).
- **[URTC Tester](https://github.com/JuanenRac/URTC-TESTER)** — desktop live CAN-bus diagnostic tool for URTC boards, one panel per tool profile (Windows/Linux).
- **[URTC Web Studio](https://github.com/JuanenRac/URTC-WEB-STUDIO)** — browser-based alternative to the 2 desktop tools above (Web Serial API + SLCAN), no local install needed.

## 👤 Author

**JuanenRac** (Electro Hobby 3D)
📧 electrohobby3d@gmail.com
📺 youtube.com/@electrohobby3d

## 📜 License

This repository's `LICENSE` file is set to the **GNU General Public License v3.0 (GPL-3.0)**, matching the convention used elsewhere in this ecosystem for pure-software projects (e.g. [HYDRA-UMC STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO)). No source code exists in this repository yet - the license applies to whatever gets built here once the project owner defines its actual scope, not to anything currently present.
