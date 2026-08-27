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

echo "============================================================================="
echo " HYDRA-UMC CONTROL (iOS/Flutter) - build.sh"
echo " Builds the Windows desktop target: flutter pub get + automatic version"
echo " bump (tool/bump_version.dart) + flutter build windows."
echo " Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>"
echo " GPL-3.0 - see LICENSE"
echo "============================================================================="
echo

# Keep the window open on both success and failure when this is launched by
# double-click instead of from an already-open terminal. Runs automatically
# on every exit path (normal end of script, `exit 1` below, or `set -e`
# aborting on a failed command). `|| true` keeps a non-interactive/closed
# stdin (e.g. CI, or this script being run by another tool) from turning the
# read's own EOF into a spurious failure.
pause() {
    read -r -p "Press Enter to close this window..." _ || true
}
trap pause EXIT

if ! command -v flutter >/dev/null 2>&1; then
    echo "[ERROR] flutter was not found on PATH. Install the Flutter SDK" >&2
    echo "        (https://docs.flutter.dev/get-started/install) and add its" >&2
    echo "        bin/ directory to PATH, then re-run this script." >&2
    exit 1
fi

echo "[1/3] flutter pub get"
flutter pub get

echo "[2/3] dart run tool/bump_version.dart"
dart run tool/bump_version.dart || exit 1
python3 "$(dirname "$0")/bump_manifest_version.py" --sync || exit 1

echo "[3/3] flutter build windows"
flutter build windows

echo
echo "Build complete: build/windows/x64/runner/Release/hydra_umc_control.exe"
