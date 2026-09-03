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

- **Login** (`lib/ui/login_screen.dart`, `lib/state/robot_view_model.dart`) - editierbare Server-IP/Port- und Bediener-Zugangsdatenfelder plus `POST /api/login`; kein Konto und kein Passwort sind vorausgefüllt. Ein Produktionsserver verlangt ausdrücklich konfigurierte Bootstrap-Zugangsdaten für seinen ersten Administrator; zusätzliche, niedriger privilegierte "operator"-Konten können über Config > Users in der Browser-UI angelegt werden. Das Sitzungstoken bleibt über Neustarts hinweg via `shared_preferences` erhalten. Ein "Scan local network"-Button (`lib/network/discovery.dart`) findet Server, ohne dass der Benutzer die IP bereits kennen muss.
- **Netzwerk-Discovery** (`lib/network/discovery.dart`) - zwei unabhängige Wege laufen gleichzeitig vom "Scan local network"-Blatt aus: echtes mDNS/Bonjour (`discoverMdns()`, fragt den `_hydra._tcp.local`-Dienst ab, den `server.ts` über das `multicast_dns`-Paket veröffentlicht - diese App ist die erste der 3 entfernten Clients des Ökosystems, die das hinzufügt) plus ein gleichzeitiger Brute-Force-Scan von `GET /api/hydra-info` über das/die eigene(n) reale(n) lokale(n) Subnetz(e) dieses Geräts (`scanSubnets()`, abgeleitet von `dart:io`s eigenem `NetworkInterface.list()` statt einer einzigen fest angenommenen Vermutung, da das LAN eines Telefons ebenso gut `192.168.0.x` oder `10.x.x.x` wie `192.168.1.x` sein kann, fällt nur dann auf `192.168.1.x` zurück, wenn die Aufzählung der Schnittstellen selbst leer ausfällt). Dass mDNS auf einem nicht berechtigten iOS-Build still fehlschlägt, ist erwartet (Apples eigene Multicast-Networking-Berechtigung wird von einem einfachen `flutter build ios` nicht gewährt) - der Subnetz-Scan funktioniert trotzdem unabhängig weiter.
- **Biometrische Zugangssperre** (`lib/network/biometric_helper.dart`, `lib/ui/biometric_gate_screen.dart`) - Face ID/Touch ID/Windows Hello über `package:local_auth`, ein optionaler Schalter in `Settings`, der die Wiederherstellung einer bereits gültigen gespeicherten Sitzung beim Start absichert (diese App speichert nie ein Klartext-Passwort, nur ein Token - angepasst vom eigenen Passwort-Wiederbefüllungs-Design von HYDRA-UMC-ANDROID-CONTROL an diesen Unterschied).
- **Atomare Befehlssynchronisation** (das eigene `_sendAtomicCommand()` von `lib/state/robot_view_model.dart`) - jede Schreiboperation (enable/disable/play/pause/stop/jog/valve/pump/speed/vision) nutzt den echten `POST /api/robot/:id/command`-Endpunkt, eine kleine gezielte Payload statt den gesamten settings-Baum zu überschreiben, mit korrekter Propagation des kombinierten Roboters (`combinedWith`) für die 5 Befehle, die dies benötigen.
- **Live-WebSocket-Synchronisation** (`lib/network/hydra_websocket.dart`) - hängt der Verbindungs-URL immer `?token=` an (der eigene `/ws`-Upgrade von `server.ts` verlangt dies bedingungslos), verarbeitet sowohl `"settings"`- als auch `"delta"`-Broadcast-Typen, verbindet sich bei Abbruch automatisch neu.
- **Dashboard** (`lib/ui/dashboard_screen.dart`) - Karten pro Roboter, in Echtzeit reaktiv über das eigene `ChangeNotifier` von `Provider`, LED-Konvention (grün pulsierend = aktiv, rot durchgehend = inaktiv) und Anzeige des kombinierten Roboters (nur auf der Follower-Seite angezeigt, per id aufgelöst) passend zum eigenen Dashboard Overview von HYDRA-UMC-STUDIO.
- **Manuelle Steuerung** (`lib/ui/control_screen.dart`, `lib/ui/widgets/joystick_pad.dart`) - Jog-D-Pad (mit/ohne XY-Tisch-Ziel), Geschwindigkeits-/Beschleunigungsregler, Ventil-/Pumpen-Schalter, und echter Long-Press-Schutz bei E-STOP/STOP (ein kurzes Antippen tut nichts außer einem haptischen + visuellen Hinweis, nur ein echtes anhaltendes Halten sendet den Befehl).
- **Kamera** (`lib/ui/camera_screen.dart`, `lib/ui/widgets/mjpeg_view.dart`) - ein kleiner, handgeschriebener MJPEG-Stream-Parser (kein Drittanbieter-Paket), ein klarer "Camera Disabled"-Zustand statt eines stillschweigend leeren Feeds, und ein Schalter, um das Vision-System eines Roboters direkt vom Server aus ein-/auszuschalten (der eigene atomare `"vision"`-Befehl von `server.ts`).
- **3D-Ansicht** (`lib/ui/three_d_screen.dart`) - bettet das eigene Echtzeit-3D-Viewport von HYDRA-UMC-STUDIO in eine WebView ein (`?hideUI=true&robotId=&token=`), derselbe Ansatz wie bei der Android-App, aus demselben Grund (bekommt die echte, aktuell ausgelieferte 3D-Szene kostenlos). Fällt auf einen ehrlichen Platzhalter zurück bei Plattformen, die `webview_flutter` nicht unterstützt (das Windows-Desktop-Target dieses Repositorys, verwendet zur Build-Verifikation).
- **Systemmetriken** (`lib/state/robot_view_model.dart`) - `GET /api/system/metrics` alle 5s abgefragt, dieselbe Kadenz wie bei den anderen 2 Clients, im Dashboard angezeigt.
- **UI in 7 Sprachen** (`lib/l10n/`, Standard-`flutter gen-l10n`-Pipeline) - Englisch, Spanisch, Französisch, Deutsch, Italienisch, Japanisch und Chinesisch, wie bei den übrigen Clients dieses Ökosystems. Eine gespeicherte Einstellung unter `Einstellungen > Sprache` verwendet standardmäßig die Systemsprache; `RobotViewModel.lastError` ist ein typisierter `HydraError` statt vorformatiertem englischem Text, sodass auch die Fehlermeldungen der Geschäftslogik (Anmelde-/Verbindungs-/Befehlsfehler) korrekt lokalisiert werden, nicht nur der statische Bildschirmtext.
- **Offline-Statuscache** (`lib/network/state_cache.dart`) - der zuletzt bekannte Einstellungsbaum wird auf der Platte gespeichert (mit 1s Debounce), sodass Dashboard/Steuerung sofort beim Start echte, wenn auch möglicherweise veraltete, Roboterdaten zeigen statt eines leeren Zustands, während der echte `connect()`-Roundtrip noch läuft. Wird ersetzt, sobald der echte Abruf erfolgreich ist.
- **Telemetrie** (`lib/ui/telemetry_screen.dart`) - ein Terminal-artiges, neueste-zuerst-Protokoll echter Verbindungs-/Anmelde-/Befehlsereignisse, begrenzt auf 50 Einträge, mit einer Aktion zum Löschen - dieselbe "Matrix-Grün"-Konvention wie der eigene Telemetrie-Tab von HYDRA-UMC-ANDROID-CONTROL.

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
│   │   ├── auth_prefs.dart          # Persistierte Verbindung + Token (shared_preferences)
│   │   ├── biometric_helper.dart    # Dünner Wrapper über package:local_auth (Face-ID/Touch-ID-Gate)
│   │   └── state_cache.dart         # Portiert von Androids eigenem StateCache.kt - letzter bekannter guter Zustand, über Starts hinweg persistiert
│   ├── state/
│   │   ├── robot_view_model.dart    # Einziges ChangeNotifier, das jeder Screen abonniert
│   │   └── hydra_error.dart         # Typisierte Fehleroberfläche für RobotViewModel (ohne eigenen BuildContext)
│   ├── l10n/                        # Echte generierte Lokalisierungen (7 Sprachen) - siehe l10n.yaml im Repo-Root
│   │   ├── app_localizations.dart   # Generierte Basisklasse
│   │   ├── app_localizations_en.dart, _es.dart, _it.dart, _fr.dart, _de.dart, _ja.dart, _zh.dart
│   │   └── language_prefs.dart      # Persistierte Sprachüberschreibung (shared_preferences)
│   └── ui/
│       ├── login_screen.dart        # Host/Port/Benutzer/Passwort-Felder + "Scan local network"
│       ├── biometric_gate_screen.dart # Von main.darts _RootGate gezeigt, während Face-ID/Touch-ID aussteht
│       ├── main_screen.dart         # Untere Navigationsleiste (Dashboard/Control/Camera/3D/Settings)
│       ├── dashboard_screen.dart    # Karten pro Roboter + Systemmetriken-Leiste
│       ├── control_screen.dart      # Jog/Geschwindigkeit/Ventil/Pumpe/Wiedergabe-Steuerung
│       ├── camera_screen.dart       # MJPEG-Viewer + Vision-Ein/Aus-Schalter
│       ├── three_d_screen.dart      # Bettet das eigene 3D-Viewport von STUDIO via WebView ein
│       ├── telemetry_screen.dart    # Portiert von Androids eigenem TelemetryScreen.kt
│       ├── settings_screen.dart     # Verbindungsinformationen + Abmelden
│       └── widgets/
│           ├── joystick_pad.dart     # Jog-D-Pad (bewusst kein analoger Stick, siehe Datei-Kopfkommentar)
│           ├── digital_readout.dart, status_led.dart
│           └── mjpeg_view.dart       # Handgeschriebener MJPEG-Stream-Parser
├── ios/                              # Xcode-Projekt (nur von macOS aus kompilieren)
├── windows/                          # Windows-Desktop-Target - Build-Verifikation ohne Mac
├── docs/ARCHITECTURE.md
├── test/                             # widget_test, websocket_uri_test, format_uptime_test, localization_test, state_cache_test, telemetry_log_test
├── images/
├── README.md                         # diese Datei (Englisch)
└── README_spa.md / README_ita.md / README_fra.md / README_deu.md / README_zho.md / README_jpn.md  # Uebersetzungen
```

## 🔗 Verwandte Projekte

Dieses Projekt ist Teil des HYDRA-UMC-Robotik-Ökosystems desselben Autors (JuanenRac / Electro Hobby 3D). Gut zu wissen, da eine Anfrage eigentlich eines dieser Projekte betreffen könnte statt dieses Repositorys.

**Übergeordnetes Projekt**
- **[HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER)** — das reale Headless-Backend (REST/WebSocket), mit dem jeder Steuerungsclient tatsächlich spricht; das Backend, gegen das der eigene Login, die atomaren Befehle und die WebSocket-Synchronisierung dieser App laufen.

**Geschwisterprojekte** — sprechen ebenfalls mit der eigenen API von HYDRA-UMC-SERVER, jeweils als eigener Client
- **[HYDRA-UMC-STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO)** — Web-Steuerungs-Dashboard mit Echtzeit-3D-Visualisierung mehrerer Roboter; sein eigener 3D-Viewport ist direkt im 3D-Ansicht-Bildschirm dieser App per WebView eingebettet.
- **[HYDRA-UMC-SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE)** — Desktop-Schwarmleitstand (PySide6) für mehrere Server gleichzeitig, verpackt als eigenständige ausführbare Datei; spricht genau denselben `REMOTE_API.md`-Vertrag wie diese App.
- **[HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL)** — native Android-Steuerungs-App mit biometrischem Login und einer gekoppelten Wear-OS-Begleit-App; spricht genau denselben `REMOTE_API.md`-Vertrag wie diese App.
- **[HYDRA-UMC-DSI](https://github.com/JuanenRac/HYDRA-UMC-DSI)** — native Touch-UI für das eingebaute 7"-DSI-Touchscreen, direkt auf dem CM5 eingebettet.
- **[HYDRA-UMC-BRIDGE-AMR](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-AMR)** — Koordinationsschranke für AGV-/AMR-Flotten über einen echten VDA-5050-MQTT-Publisher.
- **[HYDRA-UMC-BRIDGE-CNC](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-CNC)** — High-Level-Koordinator für CNC-Zellen mit echtem GRBL-Status-/Steuerbyte-Zugriff.
- **[HYDRA-UMC-BRIDGE-DROIDS](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-DROIDS)** — Koordinationsschranke für laufende/humanoide Droiden, mit einem echten Boston-Dynamics-Spot-Befehlssender.
- **[HYDRA-UMC-BRIDGE-LASER](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-LASER)** — Sicherheitskoordinator für Laserzellen, liest 3 echte Schlüssel-/Gehäuse-/Verriegelungs-GPIO-Sicherungen.
- **[HYDRA-UMC-BRIDGE-OPENPNP](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-OPENPNP)** — sicherer High-Level-Koordinator für den Leiterplattenfluss von OpenPnP Pick-and-Place.
- **[HYDRA-UMC-BRIDGE-PRINTER3D](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-PRINTER3D)** — sichere Koordinationsschranke für Moonraker/Klipper-3D-Drucker, mit echten gesicherten Job-Befehlen.
- **[HYDRA-UMC-BRIDGE-ROS2](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-ROS2)** — Sicherheitskoordinator mit einem echten, träge importierten rclpy-ROS-2-Transport.
- **[HYDRA-UMC-BRIDGE-UAV](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-UAV)** — Koordinationsschranke für kameraausgestattete UAVs, mit einem echten MAVLink-Befehlssender.

**Direkt verwandt**
- **[HYDRA-UMC-WATCH](https://github.com/JuanenRac/HYDRA-UMC-WATCH)** — WearOS-Begleit-App mit echten haptischen Alarmen und einem Sprach-Relay zum gekoppelten Telefon; die Apple-Watch-Begleiterin dieser App, für Steuerung und Status auf einen Blick vom Handgelenk aus.
- **[HYDRA-UMC-HIL-BRIDGE](https://github.com/JuanenRac/HYDRA-UMC-HIL-BRIDGE)** — echte Hardware-in-the-Loop-Sicherheitsverriegelung, die Befehle zwischen Simulation und echter Hardware routet; die Bridge, die dieser App die Fernsteuerung des digitalen Zwillings, hardware-in-the-loop, ermöglicht.

**Ebenfalls Teil des Ökosystems**

*Kern-Hardware & Plattform*
- **[HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC)** — das physische Motherboard des Roboterarms: CM5-Host + Dual-Core-STM32H745, koordiniert bis zu 8 Werkzeugarme über CAN-OTA/SPI-OTA.
- **[HYDRA-UMC-OS](https://github.com/JuanenRac/HYDRA-UMC-OS)** — reproduzierbare Raspberry-Pi-OS-Produktschicht für den CM5: schreibgeschützter Agent, validierte Konfiguration/Profile, WiFi-Ersteinrichtung.
- **[HYDRA-UMC-SDK](https://github.com/JuanenRac/HYDRA-UMC-SDK)** — der gemeinsame JSON-Schema-Vertrag und die Sicherheitsschranke, gegen die jede Bridge ihre Befehle validiert.

*Kern-Backend & Clients*
- **[HYDRA-UMC-EDITOR-URDF](https://github.com/JuanenRac/HYDRA-UMC-EDITOR-URDF)** — grafischer Desktop-URDF-Ersteller/-Editor, der fertige Modelle in STUDIOs eigenen Katalog überträgt.

*URTC-Werkzeugplattform*
- **[URTC](https://github.com/JuanenRac/URTC)** — Firmware für die physische Universal-Robot-Tool-Controller-Platine, 25+ Werkzeugprofile über CAN-Bus.
- **[URTC-FLASHER](https://github.com/JuanenRac/URTC-FLASHER)** — Desktop-GUI-Flash-Tool für URTC-Platinen, CAN-OTA plus Full-Chip-SWD/JTAG.
- **[URTC-TESTER](https://github.com/JuanenRac/URTC-TESTER)** — Desktop-Live-CAN-Bus-Diagnosetool für URTC-Platinen, ein Panel pro Werkzeugprofil.
- **[URTC-WEB-STUDIO](https://github.com/JuanenRac/URTC-WEB-STUDIO)** — browserbasierte Alternative zu URTC-TESTER über die Web-Serial-API, ohne lokale Installation.

*Vision-KI-Knoten (Hailo-8)*
- **[HYDRA-UMC-VISION-NODE](https://github.com/JuanenRac/HYDRA-UMC-VISION-NODE)** — Integrationsknoten für die Hailo-8-Vision-Pipeline, mit einer echten stufenweisen Hardware-Bereitschaftsprüfung.
- **[HYDRA-UMC-DETECTION-HEF](https://github.com/JuanenRac/HYDRA-UMC-DETECTION-HEF)** — echte Registry für kompilierte Modelle mit Hailo-Architektur-/Prüfsummen-Safe-Load-Verifizierung.
- **[HYDRA-UMC-VISION-STREAMER](https://github.com/JuanenRac/HYDRA-UMC-VISION-STREAMER)** — echter GStreamer-Pipeline- + MediaMTX-Konfigurationsgenerator mit einer echten HailoRT-Integrationsschranke.
- **[HYDRA-UMC-VISUAL-SERVOING-API](https://github.com/JuanenRac/HYDRA-UMC-VISUAL-SERVOING-API)** — echtes Position-Based-Visual-Servoing-Korrekturgesetz, sicherheitsgesteuert nach vorgelagertem Zonenstatus.
- **[HYDRA-UMC-SAFETY-ZONES](https://github.com/JuanenRac/HYDRA-UMC-SAFETY-ZONES)** — echte Zonenverletzungsprüfung und E-STOP-Anforderung, mit erzwungener Kalibrierungsaktualität.

*Kognitiver KI-Knoten (Hailo-10)*
- **[HYDRA-UMC-COGNITIVE-NODE](https://github.com/JuanenRac/HYDRA-UMC-COGNITIVE-NODE)** — Integrationsknoten für die Hailo-10-Cognitive-Pipeline (LLM-/VLA-/Sprach-Orchestrierung).
- **[HYDRA-UMC-VLA-ENGINE](https://github.com/JuanenRac/HYDRA-UMC-VLA-ENGINE)** — echte Aktions-Token-Kodierung/-Dekodierung und Trajektoriengenerierung für ein Vision-Language-Action-Modell.
- **[HYDRA-UMC-VOICE-UI](https://github.com/JuanenRac/HYDRA-UMC-VOICE-UI)** — echtes Sprach-Frontend (VAD + Intent-Parser) mit einem begrenzten, bestätigungsgesicherten Watch-Relay.
- **[HYDRA-UMC-SEMANTIC-PLANNER](https://github.com/JuanenRac/HYDRA-UMC-SEMANTIC-PLANNER)** — echte regelbasierte Aufgabenzerlegung und semantische Fehlerbehebung über MCU-Fehlercodes.
- **[HYDRA-UMC-DOCS-QA](https://github.com/JuanenRac/HYDRA-UMC-DOCS-QA)** — echte, nur auf der Standardbibliothek basierende TF-IDF-Dokumentensuche über die eigenen Markdown-Dokumente dieses Ökosystems.

*Orchestrierung & Schwarm*
- **[HYDRA-UMC-ORCHESTRATOR](https://github.com/JuanenRac/HYDRA-UMC-ORCHESTRATOR)** — Integrationsknoten mit einem echten gRPC/Protobuf-Health-Report-Vertrag und einer Missions-Zustandsmaschine.
- **[HYDRA-UMC-JOB-DISPATCHER](https://github.com/JuanenRac/HYDRA-UMC-JOB-DISPATCHER)** — echte prioritätsbasierte Job-Queue mit Deduplizierung, über eine echte HTTP-API.
- **[HYDRA-UMC-NODE-HEALING](https://github.com/JuanenRac/HYDRA-UMC-NODE-HEALING)** — echter gRPC-basierter Flotten-Health-Watchdog mit Retry/Backoff und Identitäts-Mismatch-Erkennung.
- **[HYDRA-UMC-PATH-PLANNER-3D](https://github.com/JuanenRac/HYDRA-UMC-PATH-PLANNER-3D)** — echter RRT-basierter 3D-Pfadplaner mit echter Hindernis-/Arbeitsraum-Kollisionsvalidierung.
- **[HYDRA-UMC-SWARM-SYNC](https://github.com/JuanenRac/HYDRA-UMC-SWARM-SYNC)** — echte CRDT-LWW-Element-Map-Zustandssynchronisation, eigenschaftsgetestet auf Multi-Zellen-Konvergenz.

*Digitaler Zwilling & Simulation*
- **[HYDRA-UMC-TWIN](https://github.com/JuanenRac/HYDRA-UMC-TWIN)** — Integrationsknoten für die Digital-Twin-Engine, mit einem echten Versionskompatibilitäts-Sync-Vertrag.
- **[HYDRA-UMC-PHYSICS-REPLICA](https://github.com/JuanenRac/HYDRA-UMC-PHYSICS-REPLICA)** — echte Vorwärtskinematik und Gelenkgrenzenvalidierung über eine echte URDF-Teilmenge.
- **[HYDRA-UMC-SYNTHETIC-DATA-GEN](https://github.com/JuanenRac/HYDRA-UMC-SYNTHETIC-DATA-GEN)** — echter prozeduraler 2D-Szenengenerator mit YOLO/COCO-Annotationsexport.

*Daten & Analytik*
- **[HYDRA-UMC-DATALAKE](https://github.com/JuanenRac/HYDRA-UMC-DATALAKE)** — echter sqlite3-gestützter Zeitreihenspeicher mit einer echten Ingest-/Abfrage-HTTP-API.
- **[HYDRA-UMC-ANOMALY-DETECTOR](https://github.com/JuanenRac/HYDRA-UMC-ANOMALY-DETECTOR)** — echter FFT- + statistischer Basislinien-Anomaliedetektor mit Drift-Überwachung.
- **[HYDRA-UMC-PRODUCTION-REPORTS](https://github.com/JuanenRac/HYDRA-UMC-PRODUCTION-REPORTS)** — echte OEE-/Verfügbarkeitsberechnung über den DATALAKE-Verlauf, mit reproduzierbarem CSV-Export.
- **[HYDRA-UMC-TELEMETRY-COLLECTOR](https://github.com/JuanenRac/HYDRA-UMC-TELEMETRY-COLLECTOR)** — echte CAN/WebSocket-Ingestion-Pipeline in DATALAKE, mit Sequenz-Deduplizierung.

*Industrie-Gateway*
- **[HYDRA-UMC-GATEWAY-INDUSTRIAL](https://github.com/JuanenRac/HYDRA-UMC-GATEWAY-INDUSTRIAL)** — Integrationsknoten, der zu Industrieprotokollen weiterleitet, mit einer echten Befehls-Allowlist-/Backpressure-Schicht.
- **[HYDRA-UMC-OPCUA-SERVER](https://github.com/JuanenRac/HYDRA-UMC-OPCUA-SERVER)** — echter OPC-UA-Adressraum, verifiziert mit einer echten Binärprotokoll-Client-Session.
- **[HYDRA-UMC-MQTT-BROKER](https://github.com/JuanenRac/HYDRA-UMC-MQTT-BROKER)** — echter MQTT-Broker mit optionaler Pro-Client-Authentifizierung und Topic-ACLs.
- **[HYDRA-UMC-MTCONNECT-ADAPTER](https://github.com/JuanenRac/HYDRA-UMC-MTCONNECT-ADAPTER)** — echte MTConnect-`/probe`- und `/current`-XML-Endpunkte mit Degraded-Mode-Ausgabe.

*Ergänzende Tools & Ökosystembetrieb*
- **[HYDRA-UMC-DASHBOARD-AI](https://github.com/JuanenRac/HYDRA-UMC-DASHBOARD-AI)** — Smart-Summaries- und Anomaly-Highlighting-Panels über DATALAKE/ANOMALY-DETECTOR, mit einem ehrlichen statistischen Fallback.
- **[HYDRA-UMC-TOOL-CLI](https://github.com/JuanenRac/HYDRA-UMC-TOOL-CLI)** — Flotten-CLI mit einem echten, stabilen Exit-Code-Vertrag, ein echter Live-Client der eigenen API von HYDRA-UMC-SERVER.
- **[URTC-SMART-RACK](https://github.com/JuanenRac/URTC-SMART-RACK)** — Firmware für ein Platinenmontagegestell mit echter Werkzeug-ID-Dekodierung und Smart-Idle-Vorheizlogik.
- **[URTC-VISION-TOOL](https://github.com/JuanenRac/URTC-VISION-TOOL)** — Firmware plus ein echter Python-Vision-Begleiter für einen Thermal-/RGB-Inspektionswerkzeugkopf.
- **[HYDRA-UMC-UPDATER](https://github.com/JuanenRac/HYDRA-UMC-UPDATER)** — administratives Desktop-Tool, das jedes Repository in diesem Ökosystem entdeckt, klont und aktualisiert.

---

## 📚 Dokumentation & Community

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — der Wi-Fi-Transportvertrag, den diese App mit `server.ts` spricht (Endpunkt für Endpunkt), warum es noch keinen Bluetooth-Pfad gibt, der echte Zweiweg-Discovery-Mechanismus, und die Beziehung dieser App zum Rest des Ökosystems.
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — Technologie-Stack und Coding-Richtlinien für einen Pull Request.
- **[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)** — die in dieser Community erwarteten Verhaltensstandards.
- **[SECURITY.md](SECURITY.md)** — wie man eine Schwachstelle meldet, und die echten Sicherheitsschwerpunkte dieses Projekts.
- **[SUPPORT.md](SUPPORT.md)** — wo man Fragen stellt und Fehler meldet.
- **[LICENSE.md](LICENSE.md)** — die eigene Lizenz dieses Projekts.

## 👤 AUTOR
**JuanenRac** (Electro Hobby 3D)
📧 electrohobby3d@gmail.com
📺 [youtube.com/@electrohobby3d](https://youtube.com/@electrohobby3d)

## 📜 LIZENZ

GNU General Public License v3.0 (GPL-3.0) für den Quellcode - siehe [`LICENSE`](LICENSE).

Die Dokumentation (dieses README und seine eigenen Übersetzungen - `README_spa.md`, `README_ita.md`, `README_fra.md`, `README_deu.md`, `README_zho.md`, `README_jpn.md`) steht unter **Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)** zur Verfügung. Vollständiger Text unter https://creativecommons.org/licenses/by-sa/4.0/.
