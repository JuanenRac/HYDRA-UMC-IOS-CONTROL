<p align="center">
  <img src="images/HYDRA_UMC_IOS_CONTROL_BANNER.jpg" alt="HYDRA-UMC iOS Control Banner" width="100%">
</p>

# 📱 HYDRA-UMC CONTROL (iOS)

<p align="center">
  <a href="README.md">🇺🇸 English</a> |
  <a href="README_spa.md">🇪🇸 Español</a> |
  <a href="README_fra.md">🇫🇷 Français</a> |
  <a href="README_ita.md">🇮🇹 Italiano</a> |
  🇩🇪 <b>Deutsch</b>
</p>


<p align="left">
  <img src="https://img.shields.io/badge/Lizenz-GPL%203.0-blue.svg" alt="GPL 3.0">
  <img src="https://img.shields.io/badge/Framework-Flutter-02569B.svg" alt="Flutter">
  <img src="https://img.shields.io/badge/Sprache-Dart-0175C2.svg" alt="Dart">
  <img src="https://img.shields.io/badge/Plattform-iOS-000000.svg" alt="iOS">
</p>


Eine plattformübergreifende Flutter-App (Dart), die einen Roboter der [HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC)-Plattform über Wi-Fi steuert und dabei genau denselben [`REMOTE_API.md`](https://github.com/JuanenRac/HYDRA-UMC-SERVER/blob/main/docs/REMOTE_API.md)-Vertrag spricht, den auch [HYDRA-UMC SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE) und [HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL) verwenden - Discovery, Login, atomare Befehle pro Roboter, und Live-WebSocket-Synchronisation mit einer laufenden [HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER)-Instanz (das eigenständige Backend, das aus dem Prozess von HYDRA-UMC STUDIO ausgegliedert wurde - STUDIO ist jetzt ein reiner Frontend-Client dieses Servers, genau wie diese App).

## 🔀 Warum Flutter, nicht natives Swift

Diese App zielt auf iOS/iPadOS ab, ist aber in **Flutter** statt Swift/SwiftUI gebaut: Die Arbeitsumgebung für dieses Repository ist ausschließlich Windows, und ein natives Swift-Projekt kann unter Windows *geschrieben*, aber niemals dort *kompiliert oder ausgeführt* werden (Xcode und das iOS-SDK sind ausschließlich macOS vorbehalten). Das eigene Windows-Desktop-Target von Flutter erlaubt es, diese App auf dieser Maschine wirklich zu bauen, auszuführen und zu testen - `flutter analyze` sauber, `flutter build windows` erfolgreich, `flutter test` bestanden, und die kompilierte `.exe` startet und rendert ohne Laufzeitfehler - statt Tausende Zeilen Swift blind zu schreiben, ohne jede Möglichkeit, irgendetwas davon zu verifizieren, bis ein Mac verfügbar ist.

**Dies hebt Apples eigene Beschränkung nicht auf** - eine echte `.ipa` erfordert weiterhin Xcode auf einem Mac (oder einen macOS-CI-Runner) zum Kompilieren und Signieren; an der Framework-Wahl ändert das nichts. Was Flutter bringt, ist die Möglichkeit, jede andere Zeile der eigenen Logik dieser App (Netzwerk, Zustand, UI) noch heute auf dieser Maschine zu verifizieren und später eine identische Codebasis ohne Neuschreiben nach iOS auszuliefern.

## 🏗️ Was implementiert ist

- **Login** (`lib/ui/login_screen.dart`, `lib/state/robot_view_model.dart`) - editierbare Server-IP/Port-Felder plus `POST /api/login` gegen `admin`/`admin` (vorausgefüllt - das Standardkonto, das jeder Server dieses Ökosystems bei seinem allerersten Start selbst anlegt; ein Server kann zusätzlich niedriger privilegierte "operator"-Konten haben, erstellt über Config > Users in der Browser-UI), Sitzungstoken bleibt über Neustarts hinweg via `shared_preferences` erhalten. Ein "Scan local network"-Button (`lib/network/discovery.dart`) findet Server, ohne dass der Benutzer die IP bereits kennen muss.
- **Netzwerk-Discovery** (`lib/network/discovery.dart`) - gleichzeitiger Scan von `GET /api/hydra-info` über das/die eigene(n) reale(n) lokale(n) Subnetz(e) dieses Geräts, abgeleitet von `dart:io`s eigenem `NetworkInterface.list()` statt einer einzigen fest angenommenen Vermutung, da das LAN eines Telefons ebenso gut `192.168.0.x` oder `10.x.x.x` wie `192.168.1.x` sein kann. Fällt nur dann auf `192.168.1.x` zurück, wenn die Aufzählung der Schnittstellen selbst leer ausfällt.
- **Atomare Befehlssynchronisation** (das eigene `_sendAtomicCommand()` von `lib/state/robot_view_model.dart`) - jede Schreiboperation (enable/disable/play/pause/stop/jog/valve/pump/speed/vision) nutzt den echten `POST /api/robot/:id/command`-Endpunkt, eine kleine gezielte Payload statt den gesamten settings-Baum zu überschreiben, mit korrekter Propagation des kombinierten Roboters (`combinedWith`) für die 5 Befehle, die dies benötigen.
- **Live-WebSocket-Synchronisation** (`lib/network/hydra_websocket.dart`) - hängt der Verbindungs-URL immer `?token=` an (der eigene `/ws`-Upgrade von `server.ts` verlangt dies bedingungslos), verarbeitet sowohl `"settings"`- als auch `"delta"`-Broadcast-Typen, verbindet sich bei Abbruch automatisch neu.
- **Dashboard** (`lib/ui/dashboard_screen.dart`) - Karten pro Roboter, in Echtzeit reaktiv über das eigene `ChangeNotifier` von `Provider`, LED-Konvention (grün pulsierend = aktiv, rot durchgehend = inaktiv) und Anzeige des kombinierten Roboters (nur auf der Follower-Seite angezeigt, per id aufgelöst) passend zum eigenen Dashboard Overview von HYDRA-UMC-STUDIO.
- **Manuelle Steuerung** (`lib/ui/control_screen.dart`, `lib/ui/widgets/joystick_pad.dart`) - Jog-D-Pad (mit/ohne XY-Tisch-Ziel), Geschwindigkeits-/Beschleunigungsregler, Ventil-/Pumpen-Schalter, und echter Long-Press-Schutz bei E-STOP/STOP (ein kurzes Antippen tut nichts außer einem haptischen + visuellen Hinweis, nur ein echtes anhaltendes Halten sendet den Befehl).
- **Kamera** (`lib/ui/camera_screen.dart`, `lib/ui/widgets/mjpeg_view.dart`) - ein kleiner, handgeschriebener MJPEG-Stream-Parser (kein Drittanbieter-Paket), ein klarer "Camera Disabled"-Zustand statt eines stillschweigend leeren Feeds, und ein Schalter, um das Vision-System eines Roboters direkt vom Server aus ein-/auszuschalten (der eigene atomare `"vision"`-Befehl von `server.ts`).
- **3D-Ansicht** (`lib/ui/three_d_screen.dart`) - bettet das eigene Echtzeit-3D-Viewport von HYDRA-UMC-STUDIO in eine WebView ein (`?hideUI=true&robotId=&token=`), derselbe Ansatz wie bei der Android-App, aus demselben Grund (bekommt die echte, aktuell ausgelieferte 3D-Szene kostenlos). Fällt auf einen ehrlichen Platzhalter zurück bei Plattformen, die `webview_flutter` nicht unterstützt (das Windows-Desktop-Target dieses Repositorys, verwendet zur Build-Verifikation).
- **Systemmetriken** (`lib/state/robot_view_model.dart`) - `GET /api/system/metrics` alle 5s abgefragt, dieselbe Kadenz wie bei den anderen 2 Clients, im Dashboard angezeigt.

## 🚀 Kompilieren

Erfordert das [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable-Kanal). Dieses Repository wird gegen Flutter 3.47.0 gebaut/verifiziert. Nur `windows/` und `ios/` sind in diesem Repository als Plattformen konfiguriert (keine `android/`-, `linux/`-, `web/`- oder `macos/`-Ordner) - Windows existiert, damit die eigene Logik dieser App ohne Mac gebaut und ausgeführt werden kann; iOS ist das eigentliche Ziel.

### Build-Skripte

```bash
./build.sh     # Git Bash / WSL - flutter pub get + Versions-Bump + flutter build windows
build.bat      # cmd.exe / PowerShell - flutter pub get + Versions-Bump + flutter build windows
```

Beide erzeugen `build/windows/x64/runner/Release/hydra_umc_control.exe`, und beide erhöhen zuerst die App-Version - siehe [Versionierung](#-versionierung) unten.

### Manueller Build

```bash
flutter pub get
flutter analyze          # statische Analyse - kein Compiler notwendig
flutter test             # Widget-Tests
dart run tool/bump_version.dart  # erhöht die Version, genau wie build.sh/build.bat
flutter build windows    # erzeugt build/windows/x64/runner/Release/hydra_umc_control.exe
flutter run -d windows   # oder -d <ios-device-id> von einem Mac aus, oder -d chrome fuer eine schnelle Web-Vorschau
```

**Die echte iOS-`.ipa` kompilieren** erfordert Xcode unter macOS - von dieser Maschine aus: `flutter build ipa` (oder `ios/Runner.xcworkspace` direkt in Xcode öffnen). Dies kann nicht von Windows aus erledigt werden; siehe "Warum Flutter, nicht natives Swift" oben.

## 🔢 Versionierung

Dieses Repository folgt einer ökosystemweiten Richtlinie: Die Version
wird bei **jedem echten Build** automatisch erhöht, ohne die
`version:`-Zeile in `pubspec.yaml` manuell zu bearbeiten.
`build.sh`/`build.bat` führen `tool/bump_version.dart` vor dem Aufruf
von `flutter build` aus und wenden dabei an:

- **Patch, Kilometerzähler-Stil (Basis 10):** +1 bei jedem Build;
  sobald 9 überschritten würde, wird auf 0 zurückgesetzt und minor
  bekommt +1 - z. B. `1.0.9` -> `1.1.0`. Major wird nie automatisch
  angefasst.
- **Build-Nummer** (der Teil nach `+`): ein einfacher monotoner
  Zähler, +1 bei jedem Build, ohne Übertrag.

Dasselbe Skript regeneriert `lib/app_version.dart` (generiert, nicht
manuell bearbeitet - eine einfache `const`-Datei, keine neue
Laufzeit-Abhängigkeit wie `package_info_plus`), die die App zur
Laufzeit liest, um ihre eigene Version auf dem **Einstellungen**-Bildschirm
anzuzeigen. Siehe [CHANGELOG.md](CHANGELOG.md) für die Versionshistorie.

## 📂 Repository-Struktur

```text
HYDRA-UMC-IOS-CONTROL/
├── build.bat, build.sh              # flutter pub get + Versions-Bump + flutter build windows
├── tool/
│   └── bump_version.dart            # Versions-Bump-Skript, von build.bat/build.sh vor jedem Build ausgeführt (siehe Versionierung oben)
├── lib/
│   ├── main.dart                    # App-Einstiegspunkt, ChangeNotifierProvider + Login-Gate
│   ├── app_version.dart             # GENERIERT - von tool/bump_version.dart neu erzeugt, nicht manuell bearbeiten
│   ├── models/
│   │   ├── server_info.dart         # Discovery-/Verbindungseintrag - spiegelt ServerInfo in den anderen 2 Clients
│   │   └── hydra_state.dart         # RobotView/ControllerView/HydraState - duenne veraenderliche Sichten auf den rohen settings.json-Baum
│   ├── network/
│   │   ├── hydra_api_client.dart    # REST: Login, Settings, atomarer Roboterbefehl, Systemmetriken
│   │   ├── hydra_websocket.dart     # /ws Live-Sync-Client
│   │   ├── discovery.dart           # Gleichzeitiger Scan des/der eigenen realen lokalen Subnetzes/e dieses Geraets gegen GET /api/hydra-info
│   │   └── auth_prefs.dart          # Persistierte Verbindung + Token (shared_preferences)
│   ├── state/
│   │   └── robot_view_model.dart    # Einziges ChangeNotifier, das jeder Screen abonniert
│   └── ui/
│       ├── login_screen.dart        # Host/Port/Benutzer/Passwort-Felder + "Scan local network"
│       ├── main_screen.dart         # Untere Navigationsleiste (Dashboard/Control/Camera/3D/Settings)
│       ├── dashboard_screen.dart    # Karten pro Roboter + Systemmetriken-Leiste
│       ├── control_screen.dart      # Jog/Geschwindigkeit/Ventil/Pumpe/Wiedergabe-Steuerung
│       ├── camera_screen.dart       # MJPEG-Viewer + Vision-Ein/Aus-Schalter
│       ├── three_d_screen.dart      # Bettet das eigene 3D-Viewport von STUDIO via WebView ein
│       ├── settings_screen.dart     # Verbindungsinformationen + Abmelden
│       └── widgets/
│           ├── joystick_pad.dart     # Jog-D-Pad (bewusst kein analoger Stick, siehe Datei-Kopfkommentar)
│           ├── digital_readout.dart, status_led.dart
│           └── mjpeg_view.dart       # Handgeschriebener MJPEG-Stream-Parser
├── ios/                              # Xcode-Projekt (nur von macOS aus kompilieren)
├── windows/                          # Windows-Desktop-Target - Build-Verifikation ohne Mac
├── docs/ARCHITECTURE.md
├── test/widget_test.dart
├── images/
├── README.md                         # diese Datei (Englisch)
└── README_spa.md / README_ita.md / README_fra.md / README_deu.md  # Uebersetzungen
```

## 🔗 Verwandte Projekte

Dieses Projekt ist Teil eines größeren Robotik-Ökosystems desselben Autors (JuanenRac / Electro Hobby 3D). Gut zu wissen, da eine Anfrage tatsächlich eines dieser Projekte betreffen könnte statt dieses Repository:

**HYDRA-UMC-Plattform** — die Multi-Roboter-Mikrofabrik-Zelle
- **[HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC)** — die Hauptplatine selbst: Raspberry-Pi-CM5-Host + Dual-Core-STM32H745-Echtzeit-Coprozessor, der bis zu 8 verteilte Roboterarme über CAN-OTA/SPI-OTA orchestriert. Eigene Hardware + Firmware, GPL-3.0/CERN-OHL-S v2/CC BY-SA 4.0.
- **[HYDRA-UMC STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO)** — webbasiertes Steuerungs-Dashboard für HYDRA-UMC: Multi-Roboter-3D-Visualisierung, Kinematik-/Trajektorienaufzeichnung, CAN-OTA-Flashing und -Testing für die gesamte Plattform. React + Vite + Three.js.
- **[HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER)** — das Headless-Backend (Node/Express/WebSocket), das früher im eigenen Prozess von HYDRA-UMC STUDIO gebündelt war. Verwaltet die REST/WS-API zur Robotersteuerung, die settings.json-Persistenz, die JWT-Authentifizierung und die mDNS-Erkennung; STUDIO ist jetzt ein rein statischer Frontend-Client, der über das Netzwerk mit ihm kommuniziert.
- **[HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL)** — Android-Steuerungs-App für HYDRA-UMC über Wi-Fi/Bluetooth. Echte, funktionierende App - vollständiger Funktionsumfang zur Fernsteuerung, JWT-Authentifizierung, verschlüsselte Anmeldedatenspeicherung.
- **HYDRA-UMC-IOS-CONTROL** *(dieses Repository)* — iOS/iPadOS-Steuerungs-App für HYDRA-UMC über Wi-Fi, gebaut in Flutter (plattformübergreifend, unter Windows ohne Mac verifizierbar; die endgültige `.ipa`-Paketierung benötigt weiterhin Xcode). Echte, funktionierende App - derselbe Funktionsumfang wie die Android-App.
- **[HYDRA-UMC-SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE)** — Desktop-Schwarmkommandozentrale (Python/PySide6): Multi-Controller-Netzwerkerkennung, live bidirektionale Synchronisation, echtes 3D-Roboter-Viewport, andockbarer Arbeitsbereich im Photoshop-Stil. Echt und funktionierend, kein Platzhalter.
- **[HYDRA-UMC-EDITOR-URDF](https://github.com/JuanenRac/HYDRA-UMC-EDITOR-URDF)** — grafischer Desktop-URDF-Ersteller/-Editor (Python/PySide6) für den eigenen Modellkatalog dieses Projekts: zieht Quelldateien von GitHub oder einem lokalen Ordner, validiert die Machbarkeit der Freiheitsgrade (DOF), bearbeitet Farbe/Skalierung/Kinematik mit einer Live-3D-Vorschau, und überträgt das fertige Ergebnis an einen laufenden STUDIO-Server. Echt und funktionierend, kein Platzhalter.
- **[HYDRA-UMC-DSI](https://github.com/JuanenRac/HYDRA-UMC-DSI)** — native Flutter-Touch-UI für HYDRA-UMCs eigenen 5"/7"-DSI-Touchscreen (1280×720, gleiche Auflösung bei beiden Größen) am Compute Module 5, die denselben Server direkt von der Platine aus steuert. Echtes, funktionierendes Grundgerüst mit allen 6 Katalogbildschirmen (Dashboard, manuelle Steuerung, Kamera, vereinfachte 3D-Ansicht, Systemmetriken, Login), angebunden an den Live-Server; der echte Linux-Build wurde bisher noch nicht auf echter Hardware ausgeführt (bislang nur Windows-Arbeitsumgebung - siehe das eigene README dieses Projekts).

**URTC-Plattform** — der Werkzeugkopf-Controller, den jeder HYDRA-UMC-Roboterarm trägt
- **[URTC](https://github.com/JuanenRac/URTC)** — Universal Robot Tool Controller: STM32F303-basierter CAN-Bus-Werkzeugkopf-Controller, 25 vollständig implementierte Werkzeugprofile, CAN-OTA-Firmware-Update.
- **[URTC Flasher](https://github.com/JuanenRac/URTC-FLASHER)** — Desktop-Tool für CAN-OTA- + Vollchip-SWD/JTAG-Flashing für URTC-Platinen (Windows/Linux).
- **[URTC Tester](https://github.com/JuanenRac/URTC-TESTER)** — Desktop-Tool zur Live-CAN-Bus-Diagnose für URTC-Platinen, ein Panel pro Werkzeugprofil (Windows/Linux).
- **[URTC Web Studio](https://github.com/JuanenRac/URTC-WEB-STUDIO)** — browserbasierte Alternative zu den 2 oben genannten Desktop-Tools (Web Serial API + SLCAN), keine lokale Installation notwendig.

---

## 👤 Autor

**JuanenRac** (Electro Hobby 3D)
📧 electrohobby3d@gmail.com
📺 youtube.com/@electrohobby3d

---

## 📜 Lizenz

GNU General Public License v3.0 (GPL-3.0) für den Quellcode - siehe [`LICENSE`](LICENSE).

Die Dokumentation (dieses README und seine eigenen Übersetzungen - `README_spa.md`, `README_ita.md`, `README_fra.md`, `README_deu.md`) steht unter **Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)** zur Verfügung. Vollständiger Text unter https://creativecommons.org/licenses/by-sa/4.0/.
