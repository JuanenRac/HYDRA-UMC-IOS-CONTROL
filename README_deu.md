<!-- =============================================================================
HYDRA-UMC-IOS-CONTROL - iOS and iPadOS operator console for a HYDRA-UMC server, written in Flutter
Copyright (C) JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
GPL-3.0-or-later - see LICENSE
============================================================================= -->

<p align="center">
  <img src="images/HYDRA_UMC_BANNER.svg" alt="HYDRA-UMC-IOS-CONTROL banner" width="100%">
</p>

# 🍎 HYDRA-UMC-IOS-CONTROL

<p align="center"><a href="README.md">🇺🇸 English</a> | <a href="README_spa.md">🇪🇸 Español</a> | <a href="README_fra.md">🇫🇷 Français</a> | <a href="README_ita.md">🇮🇹 Italiano</a> | 🇩🇪 <b>Deutsch</b> | <a href="README_zho.md">🇨🇳 简体中文</a> | <a href="README_jpn.md">🇯🇵 日本語</a> | <a href="README_por.md">🇵🇹 Português</a></p>

### Ihre HYDRA-UMC-Roboter auf iPhone oder iPad: den Server finden, die Roboter bewegen und beobachten und mit einem roten Knopf alles stoppen.

<p align="center">
  <img src="https://img.shields.io/badge/License-GPL%203.0--or--later-blue.svg" alt="GPL 3.0 or later">
  <img src="https://img.shields.io/badge/Framework-Flutter-02569B.svg" alt="Framework">
  <img src="https://img.shields.io/badge/Language-Dart-0175C2.svg" alt="Language">
  <img src="https://img.shields.io/badge/Platform-iOS-000000.svg" alt="Platform">
  <img src="https://img.shields.io/badge/Tests-261%20passing-2ea44f.svg" alt="Tests">
  <img src="https://img.shields.io/badge/Version-0.2.9-0f6cbd.svg" alt="Version">
  <img src="https://img.shields.io/badge/Maturity-functional-0F6CBD.svg" alt="Maturity">
</p>

---

Eine plattformübergreifende Flutter-App (Dart), die einen Roboter der [HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC)-Plattform über Wi-Fi steuert und dabei genau denselben [`REMOTE_API.md`](https://github.com/JuanenRac/HYDRA-UMC-SERVER/blob/main/docs/REMOTE_API.md)-Vertrag spricht, den auch [HYDRA-UMC SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE) und [HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL) verwenden - Discovery, Login, atomare Befehle pro Roboter, und Live-WebSocket-Synchronisation mit einer laufenden [HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER)-Instanz (das eigenständige Backend, das aus dem Prozess von HYDRA-UMC STUDIO ausgegliedert wurde - STUDIO ist jetzt ein reiner Frontend-Client dieses Servers, genau wie diese App).

> **Stand von Sicherheit (Safety) und Security:** Dieses Ökosystem ist kein zertifiziertes Sicherheitssystem. Es gibt noch keinen Hardware-E-STOP-Pfad, keine von der Firmware durchgesetzten Grenzen oder Verriegelungen und keinen verifizierten Bewegungsbefehl; Firmware-Images werden mit CRC-32 und einer Ed25519-Signatur geprüft, und ein Release-Build verweigert die veröffentlichten Entwicklungsschlüssel (die Werkzeugköpfe und Erweiterungsplatinen hinter dem Relais laufen noch mit URTC-Bootloadern, die statt einer Signatur ein HMAC-SHA256 mit gemeinsamem Schlüssel verwenden); TLS und gegenseitiges TLS sind optional und standardmäßig aus; noch keine eigene Platine wurde bestückt oder getestet. Lesen Sie die [Sicherheitsbasis](https://github.com/JuanenRac/HYDRA-UMC-DOCS/blob/main/docs/SECURITY_BASELINE.md) und das [Bedrohungsmodell](https://github.com/JuanenRac/HYDRA-UMC-DOCS/blob/main/docs/THREAT_MODEL.md), bevor Sie sich für die Sicherheit einer Person auf eine Aussage hier verlassen.

---

## 📋 Auf einen Blick

| | |
|---|---|
| Version | `0.2.9` |
| Reifegrad | Funktionsfähig |
| Tests | 261 (`flutter test`) |
| Technik | Flutter 3.x / Dart |
| Ziel | Ein iPhone oder iPad |
| Auf echter Hardware | Noch nicht: für diese Version ist kein Lauf auf echter Hardware vermerkt |

**Springe zu:** [Überblick](#-überblick) · [Architektur](#-architektur) · [Funktionen](#-funktionen) · [Sicherheit und Schutz](#-sicherheit-und-schutz) · [Schnittstellen](#-schnittstellen) · [Konfiguration](#-konfiguration) · [Schnellstart](#-schnellstart) · [Tests](#-tests) · [Fehlerbehebung](#-fehlerbehebung) · [Struktur des Repositorys](#-struktur-des-repositorys) · [Verwandte Projekte](#-verwandte-projekte)

## 🚦 Projektstatus

Jede Zeile ist ein Teil dieses Repositorys, und die Ampel sagt, wie weit er heute ist. Sie beruht auf dem, was das Repository zeigen kann (Tests, Builds, Läufe), nicht auf dem, was geplant ist.

🟢 Fertig und überprüft · 🟡 Funktioniert, mit bekannten Grenzen · 🟠 Teilweise fertig oder noch nicht überprüft · 🔴 Nicht gemacht oder funktioniert nicht

| Bereich | Stand | Was das hier bedeutet |
|---|---|---|
| Software | 🟡 | Funktioniert für seinen Hauptzweck; die Ehrlichkeitsprüfung oben nennt, was noch fehlt |
| Tests | 🟢 | 261 automatische Tests, bei jeder Änderung ausgeführt |
| Echte Hardware | 🔴 | Noch nicht: für diese Version ist kein Lauf auf echter Hardware vermerkt |
| Dokumentation | 🟢 | README in acht Sprachen, bei jeder Änderung gegen das Manifest geprüft |

## 🎯 Überblick

Ansichten der App: **Anmeldung** (Serveradresse, Konto, ein Scan des lokalen Netzes), **Übersicht** (eine Karte je Roboter mit Live-LED und Zustand des Rechenmoduls), **Steuerung** (Handbewegungsfeld, Geschwindigkeit, Ventile und Pumpen, Reservierung des Roboters, PLAY mit optionaler Rückfrage), **Kamera** (MJPEG live), **3D-Ansicht** (die echte STUDIO-Szene), **Telemetrie** (ein Protokoll im Terminalstil) und **Einstellungen** (Sprache, biometrische Sperre, Schalter). Ein roter **STOPP**-Knopf steht in der Leiste jedes Tabs.

## 🧩 Rolle in HYDRA-UMC

**HYDRA-UMC-IOS-CONTROL** ist die Bedienkonsole von HYDRA-UMC für iPhone und iPad. Sie ist in Flutter geschrieben, damit sich ihre Logik unter Windows bauen, ausführen und testen lässt; der iOS-Build selbst braucht weiterhin Xcode auf einem Mac. Sie findet einen HYDRA-UMC-SERVER im lokalen Netz, meldet sich an, zeigt und bewegt die Roboter, überwacht ihre Kameras und eine 3D-Ansicht und stoppt mit einem Tipp alles, mit demselben Fernsteuerungsvertrag wie die SUITE und die Android-App. Sie ist kein Sicherheitsgerät.

## 🏛️ Architektur

<p align="center">
  <img src="images/architecture.svg" alt="HYDRA-UMC-IOS-CONTROL architecture" width="100%">
</p>

### Warum Flutter, nicht natives Swift

Diese App zielt auf iOS/iPadOS ab, ist aber in **Flutter** statt Swift/SwiftUI gebaut: Die Arbeitsumgebung für dieses Repository ist ausschließlich Windows, und ein natives Swift-Projekt kann unter Windows *geschrieben*, aber niemals dort *kompiliert oder ausgeführt* werden (Xcode und das iOS-SDK sind ausschließlich macOS vorbehalten). Das eigene Windows-Desktop-Target von Flutter erlaubt es, diese App auf dieser Maschine wirklich zu bauen, auszuführen und zu testen - `flutter analyze` sauber, `flutter build windows` erfolgreich, `flutter test` bestanden, und die kompilierte `.exe` startet und rendert ohne Laufzeitfehler - statt Tausende Zeilen Swift blind zu schreiben, ohne jede Möglichkeit, irgendetwas davon zu verifizieren, bis ein Mac verfügbar ist.

**Dies hebt Apples eigene Beschränkung nicht auf** - eine echte `.ipa` erfordert weiterhin Xcode auf einem Mac (oder einen macOS-CI-Runner) zum Kompilieren und Signieren; an der Framework-Wahl ändert das nichts. Was Flutter bringt, ist die Möglichkeit, jede andere Zeile der eigenen Logik dieser App (Netzwerk, Zustand, UI) noch heute auf dieser Maschine zu verifizieren und später eine identische Codebasis ohne Neuschreiben nach iOS auszuliefern.

## ✨ Funktionen

- **Login** (`lib/ui/login_screen.dart`, `lib/state/robot_view_model.dart`) - editierbare Server-IP/Port- und Bediener-Zugangsdatenfelder plus `POST /api/login`; kein Konto und kein Passwort sind vorausgefüllt. Ein Produktionsserver verlangt ausdrücklich konfigurierte Bootstrap-Zugangsdaten für seinen ersten Administrator; zusätzliche, niedriger privilegierte "operator"-Konten können über Config > Users in der Browser-UI angelegt werden. Das Sitzungstoken bleibt über Neustarts hinweg im iOS-Schlüsselbund (`flutter_secure_storage`) erhalten; Host und Port liegen in `shared_preferences`. Ein "Scan local network"-Button (`lib/network/discovery.dart`) findet Server, ohne dass der Benutzer die IP bereits kennen muss.
- **Netzwerk-Discovery** (`lib/network/discovery.dart`) - zwei unabhängige Wege laufen gleichzeitig vom "Scan local network"-Blatt aus: echtes mDNS/Bonjour (`discoverMdns()`, fragt den `_hydra._tcp.local`-Dienst ab, den `server.ts` über das `multicast_dns`-Paket veröffentlicht - diese App ist die erste der 3 entfernten Clients des Ökosystems, die das hinzufügt) plus ein gleichzeitiger Brute-Force-Scan von `GET /api/hydra-info` über das/die eigene(n) reale(n) lokale(n) Subnetz(e) dieses Geräts (`scanSubnets()`, abgeleitet von `dart:io`s eigenem `NetworkInterface.list()` statt einer einzigen fest angenommenen Vermutung, da das LAN eines Telefons ebenso gut `192.168.0.x` oder `10.x.x.x` wie `192.168.1.x` sein kann, fällt nur dann auf `192.168.1.x` zurück, wenn die Aufzählung der Schnittstellen selbst leer ausfällt). Dass mDNS auf einem nicht berechtigten iOS-Build still fehlschlägt, ist erwartet (Apples eigene Multicast-Networking-Berechtigung wird von einem einfachen `flutter build ios` nicht gewährt) - der Subnetz-Scan funktioniert trotzdem unabhängig weiter.
- **Biometrische Zugangssperre** (`lib/network/biometric_helper.dart`, `lib/ui/biometric_gate_screen.dart`) - Face ID/Touch ID/Windows Hello über `package:local_auth`, ein optionaler Schalter in `Settings`, der die Wiederherstellung einer bereits gültigen gespeicherten Sitzung beim Start absichert (diese App speichert nie ein Klartext-Passwort, nur ein Token - angepasst vom eigenen Passwort-Wiederbefüllungs-Design von HYDRA-UMC-ANDROID-CONTROL an diesen Unterschied).
- **Atomare Befehlssynchronisation** (das eigene `_sendAtomicCommand()` von `lib/state/robot_view_model.dart`) - jede Schreiboperation (play/pause/stop/jog/valve/pump/speed/vision) nutzt den echten `POST /api/robot/:id/command`-Endpunkt, eine kleine gezielte Payload statt den gesamten settings-Baum zu überschreiben, mit korrekter Propagation des kombinierten Roboters (`combinedWith`) für die 5 Befehle, die dies benötigen.
- **Live-WebSocket-Synchronisation** (`lib/network/hydra_websocket.dart`) - sendet das Token als `hydra.bearer`-Subprotokoll und nie in der Verbindungs-URL (`server.ts` lehnt `/ws?token=` standardmäßig ab), verarbeitet sowohl `"settings"`- als auch `"delta"`-Broadcast-Typen, verbindet sich bei Abbruch automatisch neu.
- **Dashboard** (`lib/ui/dashboard_screen.dart`) - Karten pro Roboter, in Echtzeit reaktiv über das eigene `ChangeNotifier` von `Provider`, LED-Konvention (grün pulsierend = aktiv, rot durchgehend = inaktiv) und Anzeige des kombinierten Roboters (nur auf der Follower-Seite angezeigt, per id aufgelöst) passend zum eigenen Dashboard Overview von HYDRA-UMC-STUDIO.
- **Manuelle Steuerung** (`lib/ui/control_screen.dart`, `lib/ui/widgets/joystick_pad.dart`) - Jog-D-Pad (mit/ohne XY-Tisch-Ziel), Geschwindigkeits-/Beschleunigungsregler, Ventil-/Pumpen-Schalter, und der globale **STOP** (`lib/ui/widgets/stop_all.dart`): ein Antippen, kein langes Drücken und keine Bestätigung, er hält alle Roboter an (`POST /api/stop-all`) und sitzt in der oberen Leiste jedes Tabs, auch im Steuerungs-Tab. Die Antwort wird Roboter für Roboter angezeigt (Warnung, wenn ein Roboter ausfiel oder der Stopp nicht gespeichert wurde; von einem anderen Konto reservierte Roboter sind markiert), ein Netzwerkfehler wird einmal wiederholt, ein Server über seinem Anfragelimit oder ohne diese Route wird mit dem Stopp je Roboter beantwortet, und antwortet niemand, bleibt ein dauerhafter Hinweis „STOP nicht bestätigt“ stehen, bis ein späterer STOP eine Antwort bekommt. Der runde Stopp je Roboter behält seinen Long-Press-Schutz.
- **Reservierungen und Sicherheitsgrenzen** (`lib/ui/widgets/access_panel.dart`, `lib/models/access.dart`, `lib/network/hydra_api_client.dart`, `lib/state/robot_view_model.dart`) - Der Control-Bildschirm zeigt, wer den gewählten Roboter hält (niemand, dieses Gerät, dasselbe Konto auf einem anderen Gerät oder ein anderes Konto), und bietet **Reservieren** und **Freigeben** sowie die Liste aller Reservierungen des Servers (`GET /api/claims`). Das Gerät behält pro Installation eine Controller-ID und sendet sie bei jeder Reservierung, Freigabe, Jog-Schaltung und jedem Befehl mit (Body und Header `X-Controller-Id`); die Reservierung gehört also dem Konto und diesem Telefon, nicht dem ganzen Konto. Die Ablehnungen des Servers werden unterschieden: von einem anderen Konto reserviert, von deinem Konto auf einem anderen Gerät oder Fenster, Controller-ID erforderlich und Jog nicht scharf. Die Grenzen des Robotermodells kommen von `GET /api/safety-limits`: Ein Jog-Schritt über dem Limit wird nicht gesendet, und die Warnungen des Servers werden angezeigt. Verlangt der Administrator es, muss **Jog scharfschalten** (mit Countdown) gedrückt werden, bevor der Joystick den Roboter bewegt; die Schaltung endet von selbst, mit STOP oder bei der Freigabe. Reservierungen sind optional: Ein Roboter, den niemand reserviert hat, wird wie bisher gesteuert. Nur für einen **Administrator** erscheint bei einem Roboter, den jemand anderes hält, eine Schaltfläche **Steuerung übernehmen**; sie fragt nach einer Bestätigung und reserviert den Roboter dann mit `force: true` (der Server akzeptiert das nur von Administratoren und prüft die Rolle erneut). Schreibzugriffe sind bedingt: jeder trägt die Revision des Roboters, die diese App zuletzt gesehen hat (`If-Match`, `lib/models/contract_v2.dart`); hat inzwischen jemand anderes den Roboter geändert, antwortet der Server mit 412, nichts wird ausgeführt, der Roboter wird neu gelesen und die Meldung sagt es (Standard prüft Reservierungen, Tisch und einmalige Befehle; Streng prüft alles außer STOP; Aus prüft nichts; die Wahl steht in der Liste der Reservierungen; STOP wird nie geprüft). Der Jog des XY-Tischs ist ein einziger atomarer Befehl `table` (ein älterer Server bekommt die Jogs, die er versteht), der Server schickt die Reservierungen über den WebSocket, sodass der Control-Bildschirm nicht abfragt, solange sie ankommen, und Administratoren lesen das Audit-Protokoll (`lib/ui/widgets/audit_dialog.dart`) mit zweifach geprüfter SHA-256-Kette, vom Server und auf dem Gerät, und können dessen Zeilen als `.jsonl` kopieren.
- **Optionale Schalter** - zwei Schalter, beide standardmäßig aus: *Befehle bei gespeicherten Daten sperren* (Einstellungen) hält jeden Befehl außer STOP zurück, solange der Bildschirm die gespeicherte Kopie des Roboterzustands statt des Livezustands zeigt, und *Mobilfunk- und VPN-Netze nicht durchsuchen* (Anmeldebildschirm) lässt diese Schnittstellen beim Subnetz-Scan aus. Die Jog-Tasten des D-Pads sind mindestens 44 pt groß und werden von VoiceOver mit Achse und Richtung angesagt; das Kamerabild wird geschlossen, solange die App im Hintergrund ist.
- **Vor PLAY nachfragen** - standardmäßig an, in den Einstellungen abschaltbar: Vor dem Start einer Bahn zeigt die App den Roboter, seine aufgezeichneten Punkte, die Geschwindigkeit und wer ihn reserviert hat (ein von jemand anderem reservierter Roboter weist darauf hin, dass der Server den Befehl ablehnt). Ein Roboter, der schon spielt, wird nicht erneut gefragt. Die Wahl bleibt gespeichert.
- **Kamera** (`lib/ui/camera_screen.dart`, `lib/ui/widgets/mjpeg_view.dart`) - ein kleiner, handgeschriebener MJPEG-Stream-Parser (kein Drittanbieter-Paket), ein klarer "Camera Disabled"-Zustand statt eines stillschweigend leeren Feeds, und ein Schalter, um das Vision-System eines Roboters direkt vom Server aus ein-/auszuschalten (der eigene atomare `"vision"`-Befehl von `server.ts`).
- **3D-Ansicht** (`lib/ui/three_d_screen.dart`) - bettet das eigene Echtzeit-3D-Viewport von HYDRA-UMC-STUDIO in eine WebView ein (`?hideUI=true&robotId=#token=`), derselbe Ansatz wie bei der Android-App, aus demselben Grund (bekommt die echte, aktuell ausgelieferte 3D-Szene kostenlos). Fällt auf einen ehrlichen Platzhalter zurück bei Plattformen, die `webview_flutter` nicht unterstützt (das Windows-Desktop-Target dieses Repositorys, verwendet zur Build-Verifikation).
- **Systemmetriken** (`lib/state/robot_view_model.dart`) - `GET /api/system/metrics` alle 5s abgefragt, dieselbe Kadenz wie bei den anderen 2 Clients, im Dashboard angezeigt.
- **UI in 8 Sprachen** (`lib/l10n/`, Standard-`flutter gen-l10n`-Pipeline) - Englisch, Spanisch, Französisch, Deutsch, Italienisch, Japanisch, Chinesisch und Portugiesisch, wie bei den übrigen Clients dieses Ökosystems. Eine gespeicherte Einstellung unter `Einstellungen > Sprache` verwendet standardmäßig die Systemsprache; `RobotViewModel.lastError` ist ein typisierter `HydraError` statt vorformatiertem englischem Text, sodass auch die Fehlermeldungen der Geschäftslogik (Anmelde-/Verbindungs-/Befehlsfehler) korrekt lokalisiert werden, nicht nur der statische Bildschirmtext.
- **Offline-Statuscache** (`lib/network/state_cache.dart`) - der zuletzt bekannte Einstellungsbaum wird zusammen mit dem echten Speicherzeitpunkt auf der Platte gespeichert (mit 1s Debounce), sodass Dashboard/Steuerung sofort beim Start echte, wenn auch möglicherweise veraltete, Roboterdaten zeigen statt eines leeren Zustands, während der echte `connect()`-Roundtrip noch läuft. Ein echter, sichtbarer Hinweis (kein stilles Raten) zeigt "Zwischengespeicherte Daten von HH:mm", solange das gilt. Wird ersetzt, sobald der echte Abruf erfolgreich ist.
- **Telemetrie** (`lib/ui/telemetry_screen.dart`) - ein Terminal-artiges, neueste-zuerst-Protokoll echter Verbindungs-/Anmelde-/Befehlsereignisse, begrenzt auf 50 Einträge, mit einer Aktion zum Löschen - dieselbe "Matrix-Grün"-Konvention wie der eigene Telemetrie-Tab von HYDRA-UMC-ANDROID-CONTROL.
- **Sprachassistent in der App** (`lib/ui/voice_assistant_dialog.dart`) - ein Mikrofonsymbol in der App-Leiste öffnet einen Dialog zum Eintippen einer Frage oder eines Befehls, gesendet an `HYDRA-UMC-VOICE-UI` über dieselbe reale `POST /api/voice/turn`-Route, die der eigene Sprachassistent-Button und das Uhr-Relay von HYDRA-UMC-ANDROID-CONTROL verwenden. Lädt niemals Audio hoch - vorerst nur Text, da die native Spracherkennung von iOS das Speech-Framework benötigt, das diese reine Windows-Entwicklungsumgebung nicht gegen ein echtes Gerät/Xcode kompilieren oder verifizieren kann. Eine Antwort löst nie direkt einen Roboterbefehl aus.

## 🔒 Sicherheit und Schutz

| Bedrohung | Abwehr | Wo |
|---|---|---|
| Ein vom Telefon gestohlenes Token | Token, Benutzername und Erneuerungstoken liegen in `flutter_secure_storage` (dem iOS-Schlüsselbund); nur Host, Port und Einstellungen gehen in `shared_preferences`; die App speichert nie ein Klartextpasswort | `network/auth_prefs.dart` |
| Zugangsdaten in der gespeicherten Kopie des Zustands | Die auf die Platte geschriebene Kopie des letzten Zustands wird in jeder Tiefe von den Schlüsseln `ipUsername` und `ipPassword` befreit und beim Abmelden gelöscht | `network/state_cache.dart` |
| Das Token in einem Protokoll oder in der Adresse des WebSockets | Das Token steht im Subprotokoll `hydra.bearer` des WebSockets und nie in dessen Adresse; die eingebettete 3D-Ansicht erhält es im Adressfragment (`#token=`), das nicht an den Server geht; ein Test prüft beides | `network/hydra_websocket.dart`, `util/viewer_url.dart` |
| Jemand mit dem entsperrten Telefon | Eine optionale biometrische Sperre (Face ID, Touch ID) schützt das Wiederherstellen einer gespeicherten Sitzung beim Start; das Kamerabild wird geschlossen, solange die App im Hintergrund ist | `network/biometric_helper.dart`, `ui/biometric_gate_screen.dart` |
| Ein Roboter, den zwei Personen bewegen, ein versehentliches PLAY oder ein Stopp, der nicht ankommt | Der Roboter wird vor dem Verfahren reserviert und der Bildschirm sagt, wer ihn hält; PLAY fragt standardmäßig zuerst und zeigt Roboter, Punkte, Geschwindigkeit und den Reservierenden; der globale STOPP wird einmal wiederholt, fällt auf einen Stopp je Roboter zurück und behält ein dauerhaftes Banner „STOPP nicht bestätigt“, wenn nichts antwortete | `models/access.dart`, `util/play_confirmation.dart`, `ui/widgets/stop_all.dart` |

**Was sie nie tut:** einen physischen Not-Halt ersetzen oder den Verkehr selbst verschlüsseln: Die App versucht einmal HTTPS, wenn eine unverschlüsselte HTTP-Sonde keine Antwort bekommt, und hat weder Zertifikats-Pinning noch einen Schutz vor unverschlüsseltem Verkehr außerhalb des lokalen Netzes. Der STOPP ist der Software-Stopp des Servers.

## 🔌 Schnittstellen

| Topic oder Route | Was es trägt |
|---|---|
| `POST /api/login`, `/api/logout`, `/api/refresh` | Anmelden, Abmelden und Sitzung erneuern |
| `GET /api/hydra-info` | erkennt einen echten Server; genutzt vom Subnetz-Scan und der manuellen Adresse, mit einem Wiederholversuch über HTTPS |
| `GET /api/settings`, `/api/system/metrics`, `/api/safety-limits`, `/api/claims` | Zustand der Roboter, das Rechenmodul (alle 5 s), die Sicherheitsgrenzen jedes Modells und die Reservierungen |
| `POST /api/robot/{id}/command`, `/claim`, `/release`, jog arming | ein kleiner Befehl für einen Roboter, seine Reservierung und das Scharfschalten einer Handbewegung, mit bedingten Schreibvorgängen nach Roboterrevision |
| `POST /api/stop-all` | der globale STOPP: alle Roboter, beantwortet Roboter für Roboter |
| `GET /api/audit`, `POST /api/voice/turn`, `GET /api/camera/{id}/stream` | das Audit-Protokoll (Administratoren, mit eigener SHA-256-Kettenprüfung), ein getippter Sprachzug und der MJPEG-Strom einer Kamera |
| WebSocket `hydra.bearer`, mDNS `_hydra._tcp.local` | Live-Zustandsänderungen (Nachrichten `settings` und `delta`, Wiederverbindung nach 3 s bis 30 s, ein Ping alle 20 s) und die Bonjour-Ankündigung des Servers |

## ⚙️ Konfiguration

Die App hat keine Konfigurationsdatei: Alles wird auf dem Bildschirm eingestellt und auf dem Gerät gespeichert. Standardwerte kommen aus dem Code.

| Variable | Standard | Was sie festlegt |
|---|---|---|
| Einstellungen > Vor PLAY nachfragen | an | zeigt Roboter, Punkte, Geschwindigkeit und den Reservierenden, bevor eine Bahn startet |
| Einstellungen > Befehle bei gespeicherten Daten sperren | aus | hält jeden Befehl außer STOPP zurück, solange der Bildschirm die gespeicherte Kopie statt des Live-Zustands zeigt |
| Anmeldung > Mobilfunk- und VPN-Netze nicht scannen | aus | lässt diese Schnittstellen beim Subnetz-Scan aus (32 Hosts gleichzeitig, Port 3000, sofern keine andere eingegeben wird) |
| Einstellungen > Biometrische Sperre | aus | verlangt Face ID oder Touch ID, bevor beim Start eine gespeicherte Sitzung wiederhergestellt wird |
| Einstellungen > Sprache | die Systemsprache | eine der acht Sprachen der App (`lib/l10n/`), über Starts hinweg gespeichert |

## 🚀 Schnellstart

Benötigt das stabile Flutter-SDK (Dart 3.13 oder neuer). Windows führt Logik und Tests aus; ein echter iPhone-Build braucht Xcode auf einem Mac.

```bash
flutter pub get                  # downloads the packages
flutter test                     # runs the unit tests on this machine
./build-test.sh                  # non-mutating build check (build-test.bat on Windows)
flutter build ios --no-codesign  # a real iOS build; only on a Mac with Xcode
```

## 🧪 Tests

261 automatische Tests laufen mit `flutter test`. Sie brauchen weder Hardware noch etwas außerhalb dieses Rechners.

Die CI führt `HYDRA_UMC_CI=1 python tools/ci_validate.py` aus; das prüft das Manifest, die Dokumente, die acht READMEs und die Bilder.

## 🏗️ Build und Veröffentlichung

Erfordert das [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable-Kanal). Dieses Repository wird gegen Flutter 3.47.0 gebaut/verifiziert. Nur `windows/` und `ios/` sind in diesem Repository als Plattformen konfiguriert (keine `android/`-, `linux/`-, `web/`- oder `macos/`-Ordner) - Windows existiert, damit die eigene Logik dieser App ohne Mac gebaut und ausgeführt werden kann; iOS ist das eigentliche Ziel.

### Build-Skripte

```bash
./build.sh     # Git Bash / WSL - flutter pub get + flutter build windows
build.bat      # cmd.exe / PowerShell - flutter pub get + flutter build windows
```

Beide erzeugen `build/windows/x64/runner/Release/hydra_umc_control.exe`, und beide erhöhen zuerst die App-Version - siehe [Versionierung](#versionierung) unten.

### Manueller Build

```bash
flutter pub get
flutter analyze          # statische Analyse - kein Compiler notwendig
flutter test             # Widget-Tests
dart run tool/bump_version.dart  # erhöht die Version, genau wie build.sh/build.bat
flutter build windows    # erzeugt build/windows/x64/runner/Release/hydra_umc_control.exe
flutter run -d windows   # oder -d <ios-device-id> von einem Mac aus
```

**Die echte iOS-`.ipa` kompilieren** erfordert Xcode unter macOS - von dieser Maschine aus: `flutter build ipa` (oder `ios/Runner.xcworkspace` direkt in Xcode öffnen). Dies kann nicht von Windows aus erledigt werden; siehe "Warum Flutter, nicht natives Swift" oben.

### Versionierung

Dieses Repository folgt einer Richtlinie für das gesamte Ökosystem: Bauen ändert die Version nie. Der explizite `bump`-Befehl (`python tools/hydra_project_tool.py bump`) führt `tool/bump_version.dart` aus und wendet dabei an:

- **Build-Nummer** (der Teil nach `+`): ein einfacher monotoner
  Zähler, +1 bei jedem Bump, ohne Übertrag.

Dasselbe Skript regeneriert `lib/app_version.dart` (generiert, nicht
manuell bearbeitet - eine einfache `const`-Datei, keine neue
Laufzeit-Abhängigkeit wie `package_info_plus`), die die App zur
Laufzeit liest, um ihre eigene Version auf dem **Einstellungen**-Bildschirm
anzuzeigen. Siehe [CHANGELOG.md](CHANGELOG.md) für die Versionshistorie.

## 🩺 Fehlerbehebung

| Du siehst | Weil | Tu |
|---|---|---|
| „Sitzung nicht autorisiert – bitte neu anmelden“ | Der Server hat das Token abgelehnt (der WebSocket wurde mit Code 1008 geschlossen) oder es ist abgelaufen | Melde dich neu an |
| „STOPP vom Server nicht bestätigt“ | Nichts hat den globalen STOPP innerhalb seines kurzen Zeitlimits beantwortet, oder der Server konnte den Stopp-Zustand nicht speichern | Tippe erneut; bleibt das Banner, benutze den physischen Not-Halt |
| Der Roboter ist von einem anderen Konto oder von deinem Konto auf einem anderen Gerät reserviert | Eine Reservierung gehört zum Konto und zum Gerät (eine Controller-ID je Installation) | Nutze dieses Gerät oder gib die Reservierung dort frei |
| „Gespeicherte Daten von HH:mm werden angezeigt“ | Der Server ist nicht erreichbar und der Bildschirm zeigt die gespeicherte Kopie des letzten Zustands; bei aktivem Befehle bei gespeicherten Daten sperren wird jeder Befehl außer STOPP zurückgehalten | Prüfe Server und WLAN; der Bildschirm wird von selbst wieder live, sobald die Verbindung zurückkehrt |
| „Handbewegung abgelehnt: Der Schritt liegt über dem Limit“ | Der Schritt liegt über dem Limit, das der Server für dieses Robotermodell setzt (`GET /api/safety-limits`) | Nutze einen kleineren Schritt; es wurde nichts gesendet |
| „Lokales Netz scannen“ findet keinen Server | Auf einem echten iPhone braucht Bonjour eine Berechtigung, die ein einfacher Build nicht enthält, und der Scan kann Mobilfunk- und VPN-Netze auslassen | Verbinde dich mit demselben WLAN wie der Server oder gib Adresse und Port von Hand ein |

## 📂 Struktur des Repositorys

<p align="center">
  <img src="images/repository-structure.svg" alt="Repository structure of HYDRA-UMC-IOS-CONTROL" width="100%">
</p>

<details>
<summary>Textversion des Baums</summary>

```text
HYDRA-UMC-IOS-CONTROL/
├── lib/                                                              Quellcode
│   ├── main.dart                                                     App-Einstiegspunkt, ChangeNotifierProvider + Login-Gate
│   ├── app_version.dart                                              GENERIERT - von bump_manifest_version.py neu erzeugt, nicht manuell bearbeiten
│   ├── models/                                                       Datenmodelle und reine Regeln
│   ├── network/                                                      REST-Client, WebSocket und Erkennung
│   ├── state/                                                        der Zustand, den jede Ansicht beobachtet
│   ├── l10n/                                                         Echte generierte Lokalisierungen (8 Sprachen) - siehe l10n.yaml im Repo-Root
│   ├── util/                                                         Hilfsfunktionen ohne eigenen Bildschirm
│   └── ui/                                                           Ansichten und Widgets
├── ios/                                                              Xcode-Projekt (nur von macOS aus kompilieren)
├── windows/                                                          Windows-Desktop-Target - Build-Verifikation ohne Mac
├── tools/                                                            Projektwerkzeuge und CI-Prüfungen
├── test/                                                             die Unit-Tests der Logik
├── images/                                                           Banner und Bilder der README
├── .github/                                                          CI-Workflow und Issue-Vorlagen
├── build.bat / build.sh                                              flutter pub get, dann flutter build windows; ändert nie die Version
├── docs/ARCHITECTURE.md                                              Architektur des Projekts
├── pubspec.yaml / pubspec.lock / l10n.yaml / analysis_options.yaml   Die Flutter-Paketdefinition mit ihren festgelegten Versionen, die Einstellungen des l10n-Generators und die Lint-Regeln
├── CHANGELOG.md                                                      was sich in jeder Version geändert hat
├── build-test.sh                                                     Build-Prüfung ohne Änderungen
├── bump_manifest_version.py                                          gleicht die Manifest-Version an
├── hydra-umc.project.json                                            Manifest: Version, Reifegrad, Familie
└── test.sh                                                           Build-Prüfung ohne Änderungen (flutter test führt die Unit-Tests aus)
```

</details>

## 🗺️ Roadmap und bekannte Grenzen

Im CI gibt es keinen Build für iPhone oder iPad: `flutter build ios` braucht Xcode auf einem Mac, daher wurde die App nur unter Windows ausgeführt und getestet. Die Bonjour-Erkennung braucht eine Berechtigung, die ein einfacher Build nicht enthält; auf einem echten iPhone findet also der Subnetz-Scan den Server. Es gibt noch keine Spracherkennung auf dem Gerät (der Sprachassistent nimmt getippten Text), keine TLS-Einstellungen und kein Bluetooth.

## 🌍 Sprachen

Diese README und die Dokumente des Repositorys gibt es in acht Sprachen: Englisch, Spanisch, Deutsch, Französisch, Italienisch, Japanisch, Chinesisch und Portugiesisch (Portugal). Sie entstehen gemeinsam, und die CI prüft, dass die acht Dateien dieselben Abschnitte und dieselben Links haben.

## 🔗 Verwandte Projekte

Dieses Projekt ist Teil des HYDRA-UMC-Robotik-Ökosystems desselben Autors (JuanenRac / Electro Hobby 3D). Gut zu wissen, da eine Anfrage eigentlich eines dieser Projekte betreffen könnte statt dieses Repositorys.

**Übergeordnetes Projekt**
- **[HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER)** — das reale Headless-Backend (REST/WebSocket), mit dem jeder Steuerungsclient tatsächlich spricht; das Backend, gegen das der eigene Login, die atomaren Befehle und die WebSocket-Synchronisierung dieser App laufen.

**Geschwisterprojekte** — sprechen ebenfalls mit der eigenen API von HYDRA-UMC-SERVER, jeweils als eigener Client
- **[HYDRA-UMC-STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO)** — Web-Steuerungs-Dashboard mit Echtzeit-3D-Visualisierung mehrerer Roboter; sein eigener 3D-Viewport ist direkt im 3D-Ansicht-Bildschirm dieser App per WebView eingebettet.
- **[HYDRA-UMC-SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE)** — Desktop-Schwarmleitstand (PySide6) für mehrere Server gleichzeitig, verpackt als eigenständige ausführbare Datei; spricht genau denselben `REMOTE_API.md`-Vertrag wie diese App.
- **[HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL)** — native Android-Steuerungs-App mit biometrischem Login und einer gekoppelten Wear-OS-Begleit-App; spricht genau denselben `REMOTE_API.md`-Vertrag wie diese App.
- **[HYDRA-UMC-DSI](https://github.com/JuanenRac/HYDRA-UMC-DSI)** — native Touch-UI für das eingebaute 7"-DSI-Touchscreen, direkt auf dem CM5 eingebettet.
- **[HYDRA-UMC-BRIDGE-AMR](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-AMR)** — Koordinationsschranke für AGV-/AMR-Flotten über einen VDA-5050-MQTT-Publisher (nur gegen eine emulierte Flotte getestet).
- **[HYDRA-UMC-BRIDGE-CNC](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-CNC)** — High-Level-Koordinator für CNC-Zellen mit GRBL-Status-/Steuerbyte-Zugriff (nur gegen einen Emulator getestet).
- **[HYDRA-UMC-BRIDGE-DROIDS](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-DROIDS)** — Koordinationsschranke für laufende/humanoide Droiden, mit einem Boston-Dynamics-Spot-Befehlssender (nur gegen einen Emulator getestet).
- **[HYDRA-UMC-BRIDGE-LASER](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-LASER)** — Koordinator für Laserzellen, liest 3 Schlüssel-/Gehäuse-/Verriegelungs-GPIO-Signale (nur gegen einen simulierten Chip getestet; kann keinen Laser scharfschalten oder auslösen).
- **[HYDRA-UMC-BRIDGE-OPENPNP](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-OPENPNP)** — sicherer High-Level-Koordinator für den Leiterplattenfluss von OpenPnP Pick-and-Place.
- **[HYDRA-UMC-BRIDGE-PRINTER3D](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-PRINTER3D)** — sichere Koordinationsschranke für Moonraker/Klipper-3D-Drucker, mit echten gesicherten Job-Befehlen.
- **[HYDRA-UMC-BRIDGE-ROS2](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-ROS2)** — Koordinator mit einem träge importierten rclpy-ROS-2-Transport (noch nicht gegen eine ROS-2-Installation ausgeführt).
- **[HYDRA-UMC-BRIDGE-UAV](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-UAV)** — Koordinationsschranke für kameraausgestattete UAVs, mit einem MAVLink-Befehlssender (nur gegen einen Emulator getestet).

**Direkt verwandt**
- **[HYDRA-UMC-WATCH](https://github.com/JuanenRac/HYDRA-UMC-WATCH)** — WearOS-Begleit-App mit haptischen Alarmmustern und einem Sprach-Relay zum gekoppelten Telefon (noch nicht auf einer physischen Uhr ausgeführt); die Handgelenk-Begleiterin von HYDRA-UMC-ANDROID-CONTROL (nur WearOS - diese iOS-App hat noch kein Apple-Watch-Gegenstück).
- **[HYDRA-UMC-HIL-BRIDGE](https://github.com/JuanenRac/HYDRA-UMC-HIL-BRIDGE)** — Hardware-in-the-Loop-Router mit einer Software-Kollisionsverriegelung zwischen Simulation und echter Hardware (ohne echte Hardware getestet); die Bridge, die dieser App die Fernsteuerung des digitalen Zwillings, hardware-in-the-loop, ermöglicht.

**Ebenfalls Teil des Ökosystems**

*Kern-Hardware & Plattform*
- **[HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC)** — der Entwurf des Motherboards des Roboterarms: CM5-Host + Dual-Core-STM32H745, gedacht zur Koordination von bis zu 8 Werkzeugarmen über CAN-OTA/SPI-OTA (Firmware in einer frühen Phase; noch keine bestückte Platine).
- **[HYDRA-UMC-OS](https://github.com/JuanenRac/HYDRA-UMC-OS)** — reproduzierbare Raspberry-Pi-OS-Produktschicht für den CM5: schreibgeschützter Agent, validierte Konfiguration/Profile, WiFi-Ersteinrichtung.
- **[HYDRA-UMC-SDK](https://github.com/JuanenRac/HYDRA-UMC-SDK)** — der gemeinsame JSON-Schema-Vertrag und die Software-Auftragsschranke, gegen die jede Bridge ihre Befehle validiert (keine zertifizierte Sicherheitsfunktion).
- **[HYDRA-UMC-CONNECTOR-HUB](https://github.com/JuanenRac/HYDRA-UMC-CONNECTOR-HUB)** — deklaratives Adapter-Manifest-Register und Validator für Konnektoren externer Maschinen; erweitert die eigene Vertragsidee des SDK auf externe Maschinen, ohne die Industrie-Gateway-Projekte zu ersetzen.

*Kern-Backend & Clients*
- **[HYDRA-UMC-EDITOR-URDF](https://github.com/JuanenRac/HYDRA-UMC-EDITOR-URDF)** — grafischer Desktop-URDF-Ersteller/-Editor, der fertige Modelle in STUDIOs eigenen Katalog überträgt.
- **[HYDRA-UMC-EDITOR-STL](https://github.com/JuanenRac/HYDRA-UMC-EDITOR-STL)** — Desktop-STL-Modelleditor, der echte Teile im selben Modellkatalog transformiert/ersetzt/entfernt/hinzufügt, den auch HYDRA-UMC-EDITOR-URDF bearbeitet.

*URTC-Werkzeugplattform*
- **[URTC](https://github.com/JuanenRac/URTC)** — Firmware für die physische Universal-Robot-Tool-Controller-Platine, 25+ Werkzeugprofile über CAN-Bus.
- **[URTC-FLASHER](https://github.com/JuanenRac/URTC-FLASHER)** — Desktop-GUI-Flash-Tool für URTC-Platinen, CAN-OTA plus Full-Chip-SWD/JTAG.
- **[URTC-TESTER](https://github.com/JuanenRac/URTC-TESTER)** — Desktop-Live-CAN-Bus-Diagnosetool für URTC-Platinen, ein Panel pro Werkzeugprofil.
- **[URTC-WEB-STUDIO](https://github.com/JuanenRac/URTC-WEB-STUDIO)** — browserbasierte Alternative zu URTC-TESTER über die Web-Serial-API, ohne lokale Installation.
- **[URTC-GATEWAY](https://github.com/JuanenRac/URTC-GATEWAY)** — Gateway vor dem CAN-Bus von URTC: Liste erlaubter Kennungen, Ratenbegrenzung und Sitzungsschlüssel; Software auf dem Computer getestet, noch nicht an einem echten Bus.

*Vision-KI-Knoten (Hailo-8)*
- **[HYDRA-UMC-VISION-NODE](https://github.com/JuanenRac/HYDRA-UMC-VISION-NODE)** — Integrationsknoten für die Hailo-8-Vision-Pipeline, mit einer echten stufenweisen Hardware-Bereitschaftsprüfung.
- **[HYDRA-UMC-DETECTION-HEF](https://github.com/JuanenRac/HYDRA-UMC-DETECTION-HEF)** — echte Registry für kompilierte Modelle mit Hailo-Architektur-/Prüfsummen-Safe-Load-Verifizierung.
- **[HYDRA-UMC-VISION-STREAMER](https://github.com/JuanenRac/HYDRA-UMC-VISION-STREAMER)** — echter GStreamer-Pipeline- + MediaMTX-Konfigurationsgenerator mit einer echten HailoRT-Integrationsschranke.
- **[HYDRA-UMC-VISUAL-SERVOING-API](https://github.com/JuanenRac/HYDRA-UMC-VISUAL-SERVOING-API)** — Position-Based-Visual-Servoing-Korrekturgesetz mit Freigabe abhängig vom Zonenstatus; noch keine Posenschätzung per Kamera.
- **[HYDRA-UMC-SAFETY-ZONES](https://github.com/JuanenRac/HYDRA-UMC-SAFETY-ZONES)** — v0-Logik für Zonenverletzung, Kalibrierungsaktualität und E-STOP-Anforderung, die Objektpositionen aus einer Datei nimmt; kein Detektor speist sie, und noch kein physischer E-STOP ist angeschlossen.

*Kognitiver KI-Knoten (Hailo-10)*
- **[HYDRA-UMC-COGNITIVE-NODE](https://github.com/JuanenRac/HYDRA-UMC-COGNITIVE-NODE)** — Integrationsknoten für die Hailo-10-Cognitive-Pipeline (LLM-/VLA-/Sprach-Orchestrierung).
- **[HYDRA-UMC-VLA-ENGINE](https://github.com/JuanenRac/HYDRA-UMC-VLA-ENGINE)** — echte Aktions-Token-Kodierung/-Dekodierung und Trajektoriengenerierung für ein Vision-Language-Action-Modell.
- **[HYDRA-UMC-VOICE-UI](https://github.com/JuanenRac/HYDRA-UMC-VOICE-UI)** — echtes Sprach-Frontend (VAD + Intent-Parser) mit einem begrenzten, bestätigungsgesicherten Watch-Relay.
- **[HYDRA-UMC-SEMANTIC-PLANNER](https://github.com/JuanenRac/HYDRA-UMC-SEMANTIC-PLANNER)** — echte regelbasierte Aufgabenzerlegung und semantische Fehlerbehebung über MCU-Fehlercodes.
- **[HYDRA-UMC-DOCS-QA](https://github.com/JuanenRac/HYDRA-UMC-DOCS-QA)** — echte, nur auf der Standardbibliothek basierende TF-IDF-Dokumentensuche über die eigenen Markdown-Dokumente dieses Ökosystems.
- **[HYDRA-UMC-LOCAL-TECHNICIAN](https://github.com/JuanenRac/HYDRA-UMC-LOCAL-TECHNICIAN)** — lokaler, richtlinien-gesteuerter KI-Wartungstechniker für das Ökosystem selbst - beobachtet, diagnostiziert und schlägt Korrekturen vor; die zwei höchsten Risikostufen sind absichtlich noch nicht implementiert.

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
- **[HYDRA-UMC-OS-REBUILDER](https://github.com/JuanenRac/HYDRA-UMC-OS-REBUILDER)** — Windows/Linux-Desktop-Tool, das ein flashbereites CM5-Image baut, vorgeladen mit den aktuellsten Versionen des Ökosystems, mit Ersteinrichtungs-Konfiguration für WLAN/Benutzer/SSH im Stil von Raspberry Pi Imager.
- **[HYDRA-UMC-OPS-AGENT](https://github.com/JuanenRac/HYDRA-UMC-OPS-AGENT)** — Wartungsvorfall-Koordinator: eine Edge-Rolle mit niedrigem Privileg sammelt einen bereinigten Inventar-/Gesundheits-Snapshot, eine Control-Plane-Rolle rendert ihn schreibgeschützt und bittet einen KI-Anbieter um einen Diagnosevorschlag - wendet nie einen Patch an und stellt nie etwas bereit.
- **[HYDRA-UMC-DEV-SERVER](https://github.com/JuanenRac/HYDRA-UMC-DEV-SERVER)** — reproduzierbarer Entwicklungshost (Raspberry Pi 5 / CM5), der den Quellcode des Ökosystems vorhält und begrenzte Build-/Test-Aufgaben über eine dauerhafte Warteschlange ausführt; eine dedizierte Entwicklerrolle, ausdrücklich kein operativer CM5.

## 📚 Dokumentation

Hier steht mehr:

* [docs/SOURCE_MAP.md](docs/SOURCE_MAP.md) - jede Quelldatei der App mit einer Zeile dazu, was sie tut
* **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — der Wi-Fi-Transportvertrag, den diese App mit `server.ts` spricht (Endpunkt für Endpunkt), warum es noch keinen Bluetooth-Pfad gibt, der echte Zweiweg-Discovery-Mechanismus, und die Beziehung dieser App zum Rest des Ökosystems.
* [Sicherheitsgrundlage des Ökosystems](https://github.com/JuanenRac/HYDRA-UMC-DOCS/blob/main/docs/SECURITY_BASELINE.md)
* [Bedrohungsmodell des Ökosystems](https://github.com/JuanenRac/HYDRA-UMC-DOCS/blob/main/docs/THREAT_MODEL.md)
* [Änderungsprotokoll dieses Repositorys](CHANGELOG.md)
* [Lizenz dieses Repositorys](LICENSE.md)

## 🤝 Mitwirken und Community

* Führe vor einem Pull Request `HYDRA_UMC_CI=1 py -3 tools/ci_validate.py` (oder `HYDRA_UMC_CI=1 python3 tools/ci_validate.py`) aus: Es muss `CI_VALIDATION=PASS` ausgeben. Führe dafür nicht `build.sh` oder `build.bat` aus; Bauen ist keine Prüfung.
* Die acht READMEs entstehen aus einer einzigen Quelle in HYDRA-UMC-DOCS; bearbeite sie nicht von Hand. Ändere die Quelle und schreibe sie mit `tools/make_readmes.py` neu.
* Behaupte in einer README nichts, was nicht gelaufen ist: Schreibe „simuliert“ oder „nicht auf Hardware erprobt“, wo das stimmt.
* Siehe [CONTRIBUTING.md](CONTRIBUTING.md), den [Verhaltenskodex](CODE_OF_CONDUCT.md), [SECURITY.md](SECURITY.md) und [SUPPORT.md](SUPPORT.md).

## 👤 AUTOR

**JuanenRac (Electro Hobby 3D)** · electrohobby3d@gmail.com

## 📜 LIZENZ

GPL-3.0-or-later - [LICENSE](LICENSE).
