@echo off
REM =============================================================================
REM HYDRA-UMC CONTROL (iOS/Flutter) - build.bat
REM Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
REM GPL-3.0 - see LICENSE
REM
REM Builds the Windows desktop target - the only target this repo can
REM actually produce a runnable binary for on a Windows machine without
REM Xcode (windows/ and ios/ are the only 2 platforms configured in this
REM repo; see `flutter build ipa` on macOS for the real iOS .ipa).
REM =============================================================================

setlocal
python "%~dp0bump_manifest_version.py"
if errorlevel 1 ( echo VERSION BUMP FAILED. & pause & exit /b 1 )

echo =============================================================================
echo  HYDRA-UMC CONTROL (iOS/Flutter) - build.bat
echo  Builds the Windows desktop target: flutter pub get + automatic version
echo  bump (tool/bump_version.dart) + flutter build windows.
echo  Copyright (C) 2026 JuanenRac (Electro Hobby 3D) ^<electrohobby3d@gmail.com^>
echo  GPL-3.0 - see LICENSE
echo =============================================================================
echo.

where flutter >nul 2>nul
if errorlevel 1 (
    echo [ERROR] flutter was not found on PATH. Install the Flutter SDK
    echo         ^(https://docs.flutter.dev/get-started/install^) and add its
    echo         bin\ directory to PATH, then re-run this script.
    goto :error
)

echo [1/3] flutter pub get
call flutter pub get
if errorlevel 1 goto :error

echo [2/3] dart run tool/bump_version.dart
call dart run tool/bump_version.dart
if errorlevel 1 goto :error

echo [3/3] flutter build windows
call flutter build windows
if errorlevel 1 goto :error

echo.
echo Build complete: build\windows\x64\runner\Release\hydra_umc_control.exe
echo.
REM Keep the window open when this is launched by double-click instead of
REM from an already-open terminal, on success (here) and on failure (:error
REM below) alike.
pause
endlocal
exit /b 0

:error
echo.
echo Build FAILED.
echo.
pause
endlocal
exit /b 1
