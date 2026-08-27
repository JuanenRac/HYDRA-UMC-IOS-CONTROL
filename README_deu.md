<p align="center">
  <img src="images/HYDRA_UMC_BANNER.svg" alt="HYDRA-UMC-IOS-CONTROL banner" width="100%">
</p>

# 📱 HYDRA-UMC CONTROL (iOS)

<p align="center">
  <a href="README.md">🇺🇸 English</a> |
  <a href="README_spa.md">🇪🇸 Español</a> |
  <a href="README_fra.md">🇫🇷 Français</a> |
  <a href="README_ita.md">🇮🇹 Italiano</a> |
  🇩🇪 <b>Deutsch</b> |
  <a href="README_zho.md">🇨🇳 简体中文</a> |
  <a href="README_jpn.md">🇯🇵 日本語</a>
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
  bekommt +1 - z. B. `0.0.9` -> `0.1.0`. Major wird nie automatisch
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
└── README_spa.md / README_ita.md / README_fra.md / README_deu.md / README_zho.md / README_jpn.md  # Uebersetzungen
```

## 🔗 Verwandte Projekte

Dieses Projekt ist Teil eines größeren Robotik-Ökosystems desselben Autors (JuanenRac / Electro Hobby 3D), das aus vielen Projekten besteht. Gut zu wissen, da eine Anfrage tatsächlich eines dieser Projekte betreffen könnte statt dieses Repository.

**Direkt mit dieser App verwandt**
- **[HYDRA-UMC-WATCH](https://github.com/JuanenRac/HYDRA-UMC-WATCH)** — die Apple-Watch-Begleit-App zu dieser App, für Steuerung und Status auf einen Blick am Handgelenk.
- **[HYDRA-UMC-HIL-BRIDGE](https://github.com/JuanenRac/HYDRA-UMC-HIL-BRIDGE)** — die Brücke, die es dieser App erlaubt, den digitalen Zwilling per Hardware-in-the-Loop fernzusteuern.

**Der Rest des Ökosystems**

💠 *Kern-Ökosystem*: [HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC) · [HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER) · [HYDRA-UMC-STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO) · [HYDRA-UMC-SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE) · [HYDRA-UMC-DSI](https://github.com/JuanenRac/HYDRA-UMC-DSI) · [HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL) · [HYDRA-UMC-EDITOR-URDF](https://github.com/JuanenRac/HYDRA-UMC-EDITOR-URDF) · [URTC](https://github.com/JuanenRac/URTC) · [URTC-FLASHER](https://github.com/JuanenRac/URTC-FLASHER) · [URTC-TESTER](https://github.com/JuanenRac/URTC-TESTER) · [URTC-WEB-STUDIO](https://github.com/JuanenRac/URTC-WEB-STUDIO)

👁️ *Vision-KI-Knoten (Hailo-8)*: [HYDRA-UMC-VISION-NODE](https://github.com/JuanenRac/HYDRA-UMC-VISION-NODE) · [HYDRA-UMC-VISION-STREAMER](https://github.com/JuanenRac/HYDRA-UMC-VISION-STREAMER) · [HYDRA-UMC-DETECTION-HEF](https://github.com/JuanenRac/HYDRA-UMC-DETECTION-HEF) · [HYDRA-UMC-SAFETY-ZONES](https://github.com/JuanenRac/HYDRA-UMC-SAFETY-ZONES) · [HYDRA-UMC-VISUAL-SERVOING-API](https://github.com/JuanenRac/HYDRA-UMC-VISUAL-SERVOING-API)

🧠 *Kognitiver KI-Knoten (Hailo-10)*: [HYDRA-UMC-COGNITIVE-NODE](https://github.com/JuanenRac/HYDRA-UMC-COGNITIVE-NODE) · [HYDRA-UMC-VLA-ENGINE](https://github.com/JuanenRac/HYDRA-UMC-VLA-ENGINE) · [HYDRA-UMC-VOICE-UI](https://github.com/JuanenRac/HYDRA-UMC-VOICE-UI) · [HYDRA-UMC-SEMANTIC-PLANNER](https://github.com/JuanenRac/HYDRA-UMC-SEMANTIC-PLANNER) · [HYDRA-UMC-DOCS-QA](https://github.com/JuanenRac/HYDRA-UMC-DOCS-QA)

🐝 *Orchestrierung & Schwarm*: [HYDRA-UMC-ORCHESTRATOR](https://github.com/JuanenRac/HYDRA-UMC-ORCHESTRATOR) · [HYDRA-UMC-SWARM-SYNC](https://github.com/JuanenRac/HYDRA-UMC-SWARM-SYNC) · [HYDRA-UMC-PATH-PLANNER-3D](https://github.com/JuanenRac/HYDRA-UMC-PATH-PLANNER-3D) · [HYDRA-UMC-JOB-DISPATCHER](https://github.com/JuanenRac/HYDRA-UMC-JOB-DISPATCHER) · [HYDRA-UMC-NODE-HEALING](https://github.com/JuanenRac/HYDRA-UMC-NODE-HEALING)

🎮 *Digitaler Zwilling & Simulation*: [HYDRA-UMC-TWIN](https://github.com/JuanenRac/HYDRA-UMC-TWIN) · [HYDRA-UMC-PHYSICS-REPLICA](https://github.com/JuanenRac/HYDRA-UMC-PHYSICS-REPLICA) · [HYDRA-UMC-SYNTHETIC-DATA-GEN](https://github.com/JuanenRac/HYDRA-UMC-SYNTHETIC-DATA-GEN)

📊 *Daten & Analytik*: [HYDRA-UMC-DATALAKE](https://github.com/JuanenRac/HYDRA-UMC-DATALAKE) · [HYDRA-UMC-TELEMETRY-COLLECTOR](https://github.com/JuanenRac/HYDRA-UMC-TELEMETRY-COLLECTOR) · [HYDRA-UMC-ANOMALY-DETECTOR](https://github.com/JuanenRac/HYDRA-UMC-ANOMALY-DETECTOR) · [HYDRA-UMC-PRODUCTION-REPORTS](https://github.com/JuanenRac/HYDRA-UMC-PRODUCTION-REPORTS)

🏭 *Industrielles Gateway*: [HYDRA-UMC-GATEWAY-INDUSTRIAL](https://github.com/JuanenRac/HYDRA-UMC-GATEWAY-INDUSTRIAL) · [HYDRA-UMC-OPCUA-SERVER](https://github.com/JuanenRac/HYDRA-UMC-OPCUA-SERVER) · [HYDRA-UMC-MQTT-BROKER](https://github.com/JuanenRac/HYDRA-UMC-MQTT-BROKER) · [HYDRA-UMC-MTCONNECT-ADAPTER](https://github.com/JuanenRac/HYDRA-UMC-MTCONNECT-ADAPTER)

🛠️ *Ergänzende Werkzeuge*: [URTC-SMART-RACK](https://github.com/JuanenRac/URTC-SMART-RACK) · [URTC-VISION-TOOL](https://github.com/JuanenRac/URTC-VISION-TOOL) · [HYDRA-UMC-TOOL-CLI](https://github.com/JuanenRac/HYDRA-UMC-TOOL-CLI) · [HYDRA-UMC-DASHBOARD-AI](https://github.com/JuanenRac/HYDRA-UMC-DASHBOARD-AI)

---

## 👤 Autor

**JuanenRac** (Electro Hobby 3D)
📧 electrohobby3d@gmail.com
📺 youtube.com/@electrohobby3d

---

## 📜 Lizenz

GNU General Public License v3.0 (GPL-3.0) für den Quellcode - siehe [`LICENSE`](LICENSE).

Die Dokumentation (dieses README und seine eigenen Übersetzungen - `README_spa.md`, `README_ita.md`, `README_fra.md`, `README_deu.md`, `README_zho.md`, `README_jpn.md`) steht unter **Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)** zur Verfügung. Vollständiger Text unter https://creativecommons.org/licenses/by-sa/4.0/.

## 🛠️ BUILD & RUN

Verwenden Sie den Build-Check ohne Versionierung vor einem Release-Build:

| Aktion | Windows | Linux / macOS |
|---|---|---|
| Build-Check (ohne Änderung von Version oder CHANGELOG) | `build-test.bat` | `./build-test.sh` |
| Ausführung / Entwicklung (falls vorhanden) | `run*.bat` oder `dev*.bat` | `./run*.sh` oder `./dev*.sh` |

`build-test.bat` und `build-test.sh` kompilieren oder validieren den Projekt-Stack, ohne `hydra-umc.project.json` zu erhöhen oder `CHANGELOG.md` zu verändern. Sie dürfen nur normale Compiler-Ausgaben erzeugen. Die vorhandenen Skripte `build*.bat`, `build*.sh`, `run*` und `dev*` behalten ihr projektbezogenes Versions- oder Laufzeitverhalten bei; verwenden Sie sie, wenn dieses Verhalten benötigt wird.