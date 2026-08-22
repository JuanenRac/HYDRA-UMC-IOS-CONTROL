<p align="center">
  <img src="images/HYDRA_UMC_IOS_CONTROL_BANNER.jpg" alt="HYDRA-UMC iOS Control Banner" width="100%">
</p>

# 📱 HYDRA-UMC CONTROL (iOS)

<p align="center">
  <a href="README.md">🇺🇸 English</a> |
  <a href="README_spa.md">🇪🇸 Español</a> |
  <a href="README_fra.md">🇫🇷 Français</a> |
  🇮🇹 <b>Italiano</b> |
  <a href="README_deu.md">🇩🇪 Deutsch</a>
</p>


<p align="left">
  <img src="https://img.shields.io/badge/Licenza-GPL%203.0-blue.svg" alt="GPL 3.0">
  <img src="https://img.shields.io/badge/Framework-Flutter-02569B.svg" alt="Flutter">
  <img src="https://img.shields.io/badge/Linguaggio-Dart-0175C2.svg" alt="Dart">
  <img src="https://img.shields.io/badge/Piattaforma-iOS-000000.svg" alt="iOS">
</p>


Un'app Flutter (Dart) multipiattaforma che controlla un robot sulla piattaforma [HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC) via Wi-Fi, parlando esattamente lo stesso contratto [`REMOTE_API.md`](https://github.com/JuanenRac/HYDRA-UMC-SERVER/blob/main/docs/REMOTE_API.md) usato da [HYDRA-UMC SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE) e [HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL) - discovery, login, comandi atomici per robot, e sincronizzazione WebSocket in tempo reale contro un'istanza di [HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER) in esecuzione (il backend headless separato dal processo di HYDRA-UMC STUDIO - STUDIO e ora un puro client frontend di quel server, come questa app).

## 🔀 Perché Flutter, non Swift nativo

Questa app punta a iOS/iPadOS, ma è costruita in **Flutter** anziché Swift/SwiftUI: l'ambiente di lavoro di questo repository è esclusivamente Windows, e un progetto Swift nativo si può *scrivere* su Windows ma mai *compilare o eseguire* lì (Xcode e l'SDK iOS sono esclusivi di macOS). Il target desktop Windows proprio di Flutter permette a questa app di essere costruita, eseguita e testata davvero su questa macchina - `flutter analyze` pulito, `flutter build windows` riuscito, `flutter test` superato, e l'`.exe` compilato che si avvia e renderizza senza errori a runtime - invece di scrivere migliaia di righe di Swift alla cieca, senza alcun modo di verificarne alcuna finché non è disponibile un Mac.

**Questo non rimuove la restrizione propria di Apple** - un `.ipa` reale richiede comunque Xcode su un Mac (o un runner CI macOS) per essere compilato e firmato; nulla nella scelta del framework cambia questo. Ciò che Flutter offre è la capacità di verificare ogni altra riga della logica propria di questa app (rete, stato, UI) su questa macchina oggi, e di spedire una base di codice identica a iOS in seguito senza riscriverla.

## 🏗️ Cosa è implementato

- **Login** (`lib/ui/login_screen.dart`, `lib/state/robot_view_model.dart`) - campi modificabili di IP/porta del server più `POST /api/login` contro `admin`/`admin` (precompilato - l'account predefinito che ogni server di questo ecosistema genera da solo al suo primo avvio in assoluto; un server può anche avere account "operator" aggiuntivi a privilegio inferiore, creati da Config > Users nella UI del browser), token di sessione persistito tra gli avvii tramite `shared_preferences`. Un pulsante "Scan local network" (`lib/network/discovery.dart`) trova i server senza che l'utente debba già conoscere l'IP.
- **Discovery di rete** (`lib/network/discovery.dart`) - scansione concorrente di `GET /api/hydra-info` attraverso la(e) sottorete(i) locale(i) reale(i) propria(e) di questo dispositivo, derivata dal `NetworkInterface.list()` proprio di `dart:io` invece di un'unica ipotesi fissa, dato che la LAN di un telefono ha altrettante probabilità di essere `192.168.0.x` o `10.x.x.x` quanto `192.168.1.x`. Ricade su `192.168.1.x` solo se l'enumerazione delle interfacce stessa risulta vuota.
- **Sincronizzazione comandi atomici** (il `_sendAtomicCommand()` proprio di `lib/state/robot_view_model.dart`) - ogni scrittura (enable/disable/play/pause/stop/jog/valve/pump/speed/vision) usa l'endpoint reale `POST /api/robot/:id/command`, un payload piccolo e mirato invece di sovrascrivere l'intero albero settings, con propagazione corretta del robot combinato (`combinedWith`) per i 5 comandi che ne hanno bisogno.
- **Sincronizzazione WebSocket in tempo reale** (`lib/network/hydra_websocket.dart`) - allega sempre `?token=` all'URL di connessione (l'upgrade `/ws` proprio di `server.ts` lo richiede incondizionatamente), gestisce sia i tipi di broadcast `"settings"` che `"delta"`, si riconnette automaticamente alla caduta.
- **Dashboard** (`lib/ui/dashboard_screen.dart`) - schede per robot, reattive in tempo reale tramite il `ChangeNotifier` proprio di `Provider`, convenzione LED (verde pulsante = attivo, rosso fisso = inattivo) e visualizzazione robot combinato (mostrata solo sul lato follower, risolta per id) che corrisponde alla propria Dashboard Overview di HYDRA-UMC-STUDIO.
- **Controllo Manuale** (`lib/ui/control_screen.dart`, `lib/ui/widgets/joystick_pad.dart`) - D-pad di jog (con/senza target tavola XY), slider velocità/accelerazione, interruttori valvola/pompa, e protezione reale a pressione prolungata su E-STOP/STOP (un tocco rapido non fa nulla se non un feedback aptico + visivo, solo una pressione sostenuta genuina invia il comando).
- **Camera** (`lib/ui/camera_screen.dart`, `lib/ui/widgets/mjpeg_view.dart`) - un piccolo parser dello stream MJPEG scritto a mano (nessun pacchetto di terze parti), uno stato chiaro "Camera Disabled" invece di un feed vuoto silenzioso, e un interruttore per attivare/disattivare il sistema di visione di un robot direttamente dal server (il comando atomico `"vision"` proprio di `server.ts`).
- **Vista 3D** (`lib/ui/three_d_screen.dart`) - incorpora il viewport 3D in tempo reale proprio di HYDRA-UMC-STUDIO in una WebView (`?hideUI=true&robotId=&token=`), lo stesso approccio dell'app Android, per lo stesso motivo (ottiene gratuitamente la scena 3D reale, attualmente in produzione). Ricade su un placeholder onesto sulle piattaforme che `webview_flutter` non supporta (il target desktop Windows di questo repository, usato per la verifica della build).
- **Metriche di sistema** (`lib/state/robot_view_model.dart`) - `GET /api/system/metrics` interrogato ogni 5s, la stessa cadenza degli altri 2 client, mostrato nella Dashboard.

## 🚀 Compilazione

Richiede il [Flutter SDK](https://docs.flutter.dev/get-started/install) (canale stable). Questo repository è compilato/verificato contro Flutter 3.47.0. Solo `windows/` e `ios/` sono configurate come piattaforme in questo repository (nessuna cartella `android/`, `linux/`, `web/`, o `macos/`) - Windows esiste affinché la logica propria di questa app possa essere compilata ed eseguita senza un Mac; iOS è l'obiettivo reale.

### Script di build

```bash
./build.sh     # Git Bash / WSL - flutter pub get + bump versione + flutter build windows
build.bat      # cmd.exe / PowerShell - flutter pub get + bump versione + flutter build windows
```

Entrambi producono `build/windows/x64/runner/Release/hydra_umc_control.exe`, ed entrambi incrementano prima la versione dell'app - vedi [Versioning](#-versioning) più sotto.

### Build manuale

```bash
flutter pub get
flutter analyze          # analisi statica - nessun compilatore necessario
flutter test             # widget test
dart run tool/bump_version.dart  # incrementa la versione, come fanno build.sh/build.bat
flutter build windows    # produce build/windows/x64/runner/Release/hydra_umc_control.exe
flutter run -d windows   # oppure -d <ios-device-id> da un Mac, oppure -d chrome per un'anteprima web rapida
```

**Compilare il vero `.ipa` iOS** richiede Xcode su macOS - da quella macchina: `flutter build ipa` (oppure aprire `ios/Runner.xcworkspace` direttamente in Xcode). Questo non si può fare da Windows; vedi "Perché Flutter, non Swift nativo" sopra.

## 🔢 Versioning

Questo repository segue una politica ecosistema-wide: la versione viene
incrementata automaticamente a **ogni build reale**, senza modificare a
mano la riga `version:` di `pubspec.yaml`. `build.sh`/`build.bat`
eseguono `tool/bump_version.dart` prima di invocare `flutter build`,
applicando:

- **Patch, stile contachilometri (base 10):** +1 a ogni build; una
  volta superato 9 si resetta a 0 e minor sale di +1 - es. `1.0.9` ->
  `1.1.0`. Major non viene mai toccato automaticamente.
- **Build number** (la parte dopo `+`): un contatore monotono semplice,
  +1 a ogni build, senza riporto.

Lo stesso script rigenera `lib/app_version.dart` (generato, non
modificato a mano - un semplice file `const`, non una nuova dipendenza
a runtime come `package_info_plus`), che l'app legge a runtime per
mostrare la propria versione nella schermata **Impostazioni**. Vedi
[CHANGELOG.md](CHANGELOG.md) per la cronologia delle versioni.

## 📂 Struttura del Repository

```text
HYDRA-UMC-IOS-CONTROL/
├── build.bat, build.sh              # flutter pub get + bump versione + flutter build windows
├── tool/
│   └── bump_version.dart            # Script di bump versione, eseguito da build.bat/build.sh prima di ogni build (vedi Versioning sopra)
├── lib/
│   ├── main.dart                    # Punto di ingresso dell'app, ChangeNotifierProvider + gate di login
│   ├── app_version.dart             # GENERATO - rigenerato da tool/bump_version.dart, non modificare a mano
│   ├── models/
│   │   ├── server_info.dart         # Voce di discovery/connessione - rispecchia ServerInfo negli altri 2 client
│   │   └── hydra_state.dart         # RobotView/ControllerView/HydraState - viste mutabili sottili sull'albero grezzo di settings.json
│   ├── network/
│   │   ├── hydra_api_client.dart    # REST: login, settings, comando atomico robot, metriche di sistema
│   │   ├── hydra_websocket.dart     # Client di sincronizzazione live via /ws
│   │   ├── discovery.dart           # Scansione concorrente della/e sottorete/i locale/i reale/i propria/e di questo dispositivo contro GET /api/hydra-info
│   │   └── auth_prefs.dart          # Connessione e token persistiti (shared_preferences)
│   ├── state/
│   │   └── robot_view_model.dart    # Unico ChangeNotifier ascoltato da ogni schermata
│   └── ui/
│       ├── login_screen.dart        # Campi host/porta/utente/password + "Scan local network"
│       ├── main_screen.dart         # Shell di navigazione inferiore (Dashboard/Control/Camera/3D/Settings)
│       ├── dashboard_screen.dart    # Schede per robot + barra metriche di sistema
│       ├── control_screen.dart      # Controlli jog/velocità/valvola/pompa/riproduzione
│       ├── camera_screen.dart       # Visualizzatore MJPEG + interruttore visione on/off
│       ├── three_d_screen.dart      # Incorpora il viewport 3D proprio di STUDIO via WebView
│       ├── settings_screen.dart     # Informazioni di connessione + disconnessione
│       └── widgets/
│           ├── joystick_pad.dart     # D-pad di jog (deliberatamente non uno stick analogico, vedi intestazione del file)
│           ├── digital_readout.dart, status_led.dart
│           └── mjpeg_view.dart       # Parser dello stream MJPEG scritto a mano
├── ios/                              # Progetto Xcode (compilare solo da macOS)
├── windows/                          # Target desktop Windows - verifica della build senza un Mac
├── docs/ARCHITECTURE.md
├── test/widget_test.dart
├── images/
├── README.md                         # questo file (inglese)
└── README_spa.md / README_ita.md / README_fra.md / README_deu.md  # traduzioni
```

## 🔗 Progetti Correlati

Questo progetto fa parte di un ecosistema robotico più ampio dello stesso autore (JuanenRac / Electro Hobby 3D). Vale la pena conoscerlo, poiché una richiesta potrebbe in realtà riguardare uno di questi anziché questo repository:

**Piattaforma HYDRA-UMC** — la cella di micro-fabbrica multi-robot
- **[HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC)** — la scheda madre stessa: host Raspberry Pi CM5 + coprocessore real-time STM32H745 dual-core, che orchestra fino a 8 bracci robotici distribuiti via CAN-OTA/SPI-OTA. Hardware + firmware propri, GPL-3.0/CERN-OHL-S v2/CC BY-SA 4.0.
- **[HYDRA-UMC STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO)** — dashboard di controllo basata sul web per HYDRA-UMC: visualizzazione 3D multi-robot, registrazione di cinematica/traiettorie, flashing e testing CAN-OTA per l'intera piattaforma. React + Vite + Three.js.
- **[HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER)** — il backend headless (Node/Express/WebSocket) che prima era integrato nel processo stesso di HYDRA-UMC STUDIO. Gestisce l'API REST/WS di controllo robot, la persistenza di settings.json, l'autenticazione JWT e la discovery mDNS; STUDIO ora è un client frontend statico puro che comunica con esso via rete.
- **[HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL)** — app di controllo Android per HYDRA-UMC via Wi-Fi/Bluetooth. App reale e funzionante - set completo di funzionalità di controllo remoto, autenticazione JWT, archiviazione crittografata delle credenziali.
- **HYDRA-UMC-IOS-CONTROL** *(questo repository)* — app di controllo iOS/iPadOS per HYDRA-UMC via Wi-Fi, costruita in Flutter (multipiattaforma, verificabile su Windows senza un Mac; il packaging finale dell'`.ipa` richiede comunque Xcode). App reale e funzionante - stesso set di funzionalità dell'app Android.
- **[HYDRA-UMC-SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE)** — centro di comando desktop (Python/PySide6) per sciami: discovery di rete multi-controller, sincronizzazione bidirezionale in tempo reale, viewport 3D robot reale, spazio di lavoro agganciabile in stile Photoshop. Reale e funzionante, non un placeholder.
- **[HYDRA-UMC-EDITOR-URDF](https://github.com/JuanenRac/HYDRA-UMC-EDITOR-URDF)** — creatore/editor grafico desktop (Python/PySide6) per il catalogo modelli proprio di questo progetto: estrae file sorgente da GitHub o da una cartella locale, valida la fattibilità dei gradi di libertà (DOF), modifica colore/scala/cinematica con un'anteprima 3D live, e invia il risultato finito a un server STUDIO in esecuzione. Reale e funzionante, non un placeholder.
- **[HYDRA-UMC-DSI](https://github.com/JuanenRac/HYDRA-UMC-DSI)** — UI touch nativa in Flutter per il touchscreen DSI da 5"/7" proprio di HYDRA-UMC (1280×720, stessa risoluzione in entrambe le dimensioni) sul Compute Module 5, che controlla questo stesso server direttamente dalla scheda. Scaffold reale e funzionante con tutte le 6 schermate del catalogo (dashboard, controllo manuale, camera, vista 3D semplificata, metriche di sistema, login) collegate al server live; la build reale del target Linux non è ancora stata eseguita su hardware reale (ambiente di lavoro finora solo Windows - vedere il README di quel progetto).

**Piattaforma URTC** — il controller della testa utensile che ogni braccio robotico HYDRA-UMC porta
- **[URTC](https://github.com/JuanenRac/URTC)** — Universal Robot Tool Controller: controller della testa utensile su bus CAN basato su STM32F303, 25 profili utensile completamente implementati, aggiornamento firmware CAN-OTA.
- **[URTC Flasher](https://github.com/JuanenRac/URTC-FLASHER)** — strumento desktop di flashing CAN-OTA + chip completo via SWD/JTAG per schede URTC (Windows/Linux).
- **[URTC Tester](https://github.com/JuanenRac/URTC-TESTER)** — strumento desktop di diagnostica live via bus CAN per schede URTC, un pannello per profilo utensile (Windows/Linux).
- **[URTC Web Studio](https://github.com/JuanenRac/URTC-WEB-STUDIO)** — alternativa basata su browser ai 2 strumenti desktop sopra (Web Serial API + SLCAN), nessuna installazione locale necessaria.

---

## 👤 Autore

**JuanenRac** (Electro Hobby 3D)
📧 electrohobby3d@gmail.com
📺 youtube.com/@electrohobby3d

---

## 📜 Licenza

GNU General Public License v3.0 (GPL-3.0) per il codice sorgente - vedi [`LICENSE`](LICENSE).

La documentazione (questo README e le sue proprie traduzioni - `README_spa.md`, `README_ita.md`, `README_fra.md`, `README_deu.md`) è disponibile sotto **Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)**. Testo completo su https://creativecommons.org/licenses/by-sa/4.0/.
