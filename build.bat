@echo off
REM HYDRA_UMC_SCRIPT_STANDARD_HEADER_BEGIN
REM *****************************************************************************
REM Project   : HYDRA-UMC-IOS-CONTROL
REM Script    : build.bat
REM Purpose   : Incremental project build, verification and packaging workflow.
REM Author    : JuanenRac (Electro Hobby 3D)
REM Email     : electrohobby3d@gmail.com
REM Copyright : (C) 2026 JuanenRac
REM License   : GPL-3.0 - see LICENSE
REM *****************************************************************************
REM HYDRA_UMC_SCRIPT_STANDARD_HEADER_END
REM HYDRA_UMC_SCRIPT_STANDARD_BANNER_BEGIN
echo.
echo *****************************************************************************
echo * HYDRA-UMC-IOS-CONTROL - build.bat
echo * Mode      : INCREMENTAL BUILD
echo * Author    : JuanenRac (Electro Hobby 3D)
echo * Email     : electrohobby3d@gmail.com
echo * Copyright : (C) 2026 JuanenRac
echo * License   : GPL-3.0 - see LICENSE
echo * ------------------------------------------------------------------------- *
echo * 1. Increment the project version and synchronise its manifest.
echo * 2. Run this project's declared build, verification and packaging commands.
echo * 3. Report the result and keep an interactive terminal open.
echo *****************************************************************************
echo.
REM HYDRA_UMC_SCRIPT_STANDARD_BANNER_END
REM
REM Builds the Windows desktop target - the only target this repo can
REM actually produce a runnable binary for on a Windows machine without
REM Xcode (windows/ and ios/ are the only 2 platforms configured in this
REM repo; see `flutter build ipa` on macOS for the real iOS .ipa).
setlocal
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

REM tool/bump_version.dart is the real, single source of the app's own
REM native version (pubspec.yaml). It must run BEFORE the manifest is
REM touched - bumping the manifest first (as this script used to)
REM produces a manifest that claims a version newer than the app this
REM same build actually produces, the exact drift class this ecosystem's
REM version-mirror convention exists to prevent. See build.sh, which
REM already had this ordering right.
echo [2/3] dart run tool/bump_version.dart
call dart run tool/bump_version.dart
if errorlevel 1 goto :error

REM HYDRA_UMC_SCRIPT_STANDARD_VERSION_CAPTURE_BEFORE
for /f "usebackq delims=" %%V in (`python -c "import json; print(json.load(open(r'%~dp0hydra-umc.project.json', encoding='utf-8'))['version'])"`) do set "HYDRA_UMC_VERSION_BEFORE=%%V"
python "%~dp0bump_manifest_version.py" --sync
if errorlevel 1 ( echo VERSION SYNC FAILED. & pause & exit /b 1 )
REM HYDRA_UMC_SCRIPT_STANDARD_VERSION_CAPTURE_AFTER
for /f "usebackq delims=" %%V in (`python -c "import json; print(json.load(open(r'%~dp0hydra-umc.project.json', encoding='utf-8'))['version'])"`) do set "HYDRA_UMC_VERSION_AFTER=%%V"
if not defined HYDRA_UMC_VERSION_BEFORE set "HYDRA_UMC_VERSION_BEFORE=unknown"
if not defined HYDRA_UMC_VERSION_AFTER set "HYDRA_UMC_VERSION_AFTER=unknown"
echo.
echo *****************************************************************************
echo * VERSION SYNC COMPLETED
echo * v%HYDRA_UMC_VERSION_BEFORE% ^> v%HYDRA_UMC_VERSION_AFTER%
echo * Project manifest has been synchronised to the app's own real native version.
echo *****************************************************************************
echo.

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
