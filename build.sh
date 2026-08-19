#!/usr/bin/env bash
# =============================================================================
# HYDRA-UMC CONTROL (iOS/Flutter) - build.sh
# Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
# GPL-3.0 - see LICENSE
#
# Builds the Windows desktop target - the only target this repo can
# actually produce a runnable binary for on a Windows machine without
# Xcode (windows/ and ios/ are the only 2 platforms configured in this
# repo; see `flutter build ipa` on macOS for the real iOS .ipa). Runs
# under Git Bash/WSL on the same Windows machine `flutter build windows`
# itself requires - this is a bash-shell convenience wrapper, not a
# Linux/macOS build (there is no linux/ or macos/ platform folder here).
# =============================================================================
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
    echo "[ERROR] flutter was not found on PATH. Install the Flutter SDK" >&2
    echo "        (https://docs.flutter.dev/get-started/install) and add its" >&2
    echo "        bin/ directory to PATH, then re-run this script." >&2
    exit 1
fi

echo "[1/2] flutter pub get"
flutter pub get

echo "[2/2] flutter build windows"
flutter build windows

echo
echo "Build complete: build/windows/x64/runner/Release/hydra_umc_control.exe"
