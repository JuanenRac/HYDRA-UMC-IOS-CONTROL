<p align="center">
  <img src="images/HYDRA_UMC_BANNER.svg" alt="HYDRA-UMC-IOS-CONTROL banner" width="100%">
</p>

# 📱 HYDRA-UMC CONTROL (iOS)

<p align="center">
  <a href="README.md">🇺🇸 English</a> |
  <a href="README_spa.md">🇪🇸 Español</a> |
  <a href="README_fra.md">🇫🇷 Français</a> |
  🇮🇹 <b>Italiano</b> |
  <a href="README_deu.md">🇩🇪 Deutsch</a> |
  <a href="README_zho.md">🇨🇳 简体中文</a> |
  <a href="README_jpn.md">🇯🇵 日本語</a>
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

- **Login** (`lib/ui/login_screen.dart`, `lib/state/robot_view_model.dart`) - campi modificabili di IP/porta e credenziali operatore più `POST /api/login`; nessun account o password è precompilato. Un server di produzione richiede credenziali bootstrap configurate esplicitamente per il primo amministratore; account "operator" aggiuntivi a privilegio inferiore possono essere creati da Config > Users nell'interfaccia browser. Il token di sessione persiste tramite `shared_preferences`. Un pulsante "Scan local network" (`lib/network/discovery.dart`) trova i server senza che l'utente debba già conoscere l'IP.
- **Discovery di rete** (`lib/network/discovery.dart`) - due percorsi indipendenti girano insieme dal foglio "Scan local network": mDNS/Bonjour reale (`discoverMdns()`, interroga il servizio `_hydra._tcp.local` pubblicato da `server.ts` tramite il pacchetto `multicast_dns` - questa app è la prima dei 3 client remoti dell'ecosistema ad aggiungerlo) più una scansione concorrente a forza bruta di `GET /api/hydra-info` attraverso la(e) sottorete(i) locale(i) reale(i) propria(e) di questo dispositivo (`scanSubnets()`, derivata dal `NetworkInterface.list()` proprio di `dart:io` invece di un'unica ipotesi fissa, dato che la LAN di un telefono ha altrettante probabilità di essere `192.168.0.x` o `10.x.x.x` quanto `192.168.1.x`, ricadendo su `192.168.1.x` solo se l'enumerazione delle interfacce stessa risulta vuota). Che mDNS fallisca silenziosamente su una build iOS senza l'entitlement è previsto (l'entitlement Multicast Networking di Apple non è concesso da una `flutter build ios` normale) - la scansione di sottorete continua a funzionare in modo indipendente comunque.
- **Blocco biometrico** (`lib/network/biometric_helper.dart`, `lib/ui/biometric_gate_screen.dart`) - Face ID/Touch ID/Windows Hello tramite `package:local_auth`, un interruttore opzionale in `Settings` che protegge il ripristino di una sessione salvata valida all'avvio (questa app non salva mai una password in chiaro, solo un token - adattato dal design di reinserimento password proprio di HYDRA-UMC-ANDROID-CONTROL a questa differenza).
- **Sincronizzazione comandi atomici** (il `_sendAtomicCommand()` proprio di `lib/state/robot_view_model.dart`) - ogni scrittura (enable/disable/play/pause/stop/jog/valve/pump/speed/vision) usa l'endpoint reale `POST /api/robot/:id/command`, un payload piccolo e mirato invece di sovrascrivere l'intero albero settings, con propagazione corretta del robot combinato (`combinedWith`) per i 5 comandi che ne hanno bisogno.
- **Sincronizzazione WebSocket in tempo reale** (`lib/network/hydra_websocket.dart`) - allega sempre `?token=` all'URL di connessione (l'upgrade `/ws` proprio di `server.ts` lo richiede incondizionatamente), gestisce sia i tipi di broadcast `"settings"` che `"delta"`, si riconnette automaticamente alla caduta.
- **Dashboard** (`lib/ui/dashboard_screen.dart`) - schede per robot, reattive in tempo reale tramite il `ChangeNotifier` proprio di `Provider`, convenzione LED (verde pulsante = attivo, rosso fisso = inattivo) e visualizzazione robot combinato (mostrata solo sul lato follower, risolta per id) che corrisponde alla propria Dashboard Overview di HYDRA-UMC-STUDIO.
- **Controllo Manuale** (`lib/ui/control_screen.dart`, `lib/ui/widgets/joystick_pad.dart`) - D-pad di jog (con/senza target tavola XY), slider velocità/accelerazione, interruttori valvola/pompa, e protezione reale a pressione prolungata su E-STOP/STOP (un tocco rapido non fa nulla se non un feedback aptico + visivo, solo una pressione sostenuta genuina invia il comando).
- **Camera** (`lib/ui/camera_screen.dart`, `lib/ui/widgets/mjpeg_view.dart`) - un piccolo parser dello stream MJPEG scritto a mano (nessun pacchetto di terze parti), uno stato chiaro "Camera Disabled" invece di un feed vuoto silenzioso, e un interruttore per attivare/disattivare il sistema di visione di un robot direttamente dal server (il comando atomico `"vision"` proprio di `server.ts`).
- **Vista 3D** (`lib/ui/three_d_screen.dart`) - incorpora il viewport 3D in tempo reale proprio di HYDRA-UMC-STUDIO in una WebView (`?hideUI=true&robotId=&token=`), lo stesso approccio dell'app Android, per lo stesso motivo (ottiene gratuitamente la scena 3D reale, attualmente in produzione). Ricade su un placeholder onesto sulle piattaforme che `webview_flutter` non supporta (il target desktop Windows di questo repository, usato per la verifica della build).
- **Metriche di sistema** (`lib/state/robot_view_model.dart`) - `GET /api/system/metrics` interrogato ogni 5s, la stessa cadenza degli altri 2 client, mostrato nella Dashboard.
- **UI in 7 lingue** (`lib/l10n/`, pipeline standard `flutter gen-l10n`) - inglese, spagnolo, francese, tedesco, italiano, giapponese e cinese, come il resto dei client di questo ecosistema. Un'impostazione persistente in `Impostazioni > Lingua` usa come predefinita la lingua di sistema; `RobotViewModel.lastError` è un `HydraError` tipizzato invece di testo inglese già formattato, quindi anche i messaggi di errore della logica di business (errori di accesso/connessione/comando) vengono tradotti correttamente, non solo il testo statico delle schermate.
- **Cache di stato offline** (`lib/network/state_cache.dart`) - l'ultimo albero di impostazioni noto viene salvato su disco (con debounce di 1s), così le schermate Dashboard/Controllo mostrano dati reali, anche se potenzialmente non aggiornati, subito all'avvio invece di uno stato vuoto mentre il vero `connect()` è ancora in corso. Sostituito dai dati reali non appena la connessione ha successo.
- **Telemetria** (`lib/ui/telemetry_screen.dart`) - un registro in stile terminale, più recente per primo, di eventi reali di connessione/accesso/comando, limitato a 50 voci, con un'azione per cancellarlo - la stessa convenzione "verde Matrix" della scheda Telemetria di HYDRA-UMC-ANDROID-CONTROL.

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
  volta superato 9 si resetta a 0 e minor sale di +1 - es. `0.0.9` ->
  `0.1.0`. Major non viene mai toccato automaticamente.
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
│   │   ├── auth_prefs.dart          # Connessione e token persistiti (shared_preferences)
│   │   ├── biometric_helper.dart    # Wrapper sottile su package:local_auth (gate Face ID/Touch ID)
│   │   └── state_cache.dart         # Portato dallo StateCache.kt di Android - ultimo stato valido noto, persistito tra gli avvii
│   ├── state/
│   │   ├── robot_view_model.dart    # Unico ChangeNotifier ascoltato da ogni schermata
│   │   └── hydra_error.dart         # Superficie di errore tipizzata per RobotViewModel (senza un proprio BuildContext)
│   ├── l10n/                        # Localizzazioni reali generate (7 lingue) - vedi l10n.yaml nella radice del repo
│   │   ├── app_localizations.dart   # Classe base generata
│   │   ├── app_localizations_en.dart, _es.dart, _it.dart, _fr.dart, _de.dart, _ja.dart, _zh.dart
│   │   └── language_prefs.dart      # Override della lingua persistito (shared_preferences)
│   └── ui/
│       ├── login_screen.dart        # Campi host/porta/utente/password + "Scan local network"
│       ├── biometric_gate_screen.dart # Mostrata da _RootGate di main.dart mentre Face ID/Touch ID è in sospeso
│       ├── main_screen.dart         # Shell di navigazione inferiore (Dashboard/Control/Camera/3D/Settings)
│       ├── dashboard_screen.dart    # Schede per robot + barra metriche di sistema
│       ├── control_screen.dart      # Controlli jog/velocità/valvola/pompa/riproduzione
│       ├── camera_screen.dart       # Visualizzatore MJPEG + interruttore visione on/off
│       ├── three_d_screen.dart      # Incorpora il viewport 3D proprio di STUDIO via WebView
│       ├── telemetry_screen.dart    # Portato dal TelemetryScreen.kt di Android
│       ├── settings_screen.dart     # Informazioni di connessione + disconnessione
│       └── widgets/
│           ├── joystick_pad.dart     # D-pad di jog (deliberatamente non uno stick analogico, vedi intestazione del file)
│           ├── digital_readout.dart, status_led.dart
│           └── mjpeg_view.dart       # Parser dello stream MJPEG scritto a mano
├── ios/                              # Progetto Xcode (compilare solo da macOS)
├── windows/                          # Target desktop Windows - verifica della build senza un Mac
├── docs/ARCHITECTURE.md
├── test/                             # widget_test, websocket_uri_test, format_uptime_test, localization_test, state_cache_test, telemetry_log_test
├── images/
├── README.md                         # questo file (inglese)
└── README_spa.md / README_ita.md / README_fra.md / README_deu.md / README_zho.md / README_jpn.md  # traduzioni
```

## 🔗 Progetti Correlati

Questo progetto fa parte dell'ecosistema robotico HYDRA-UMC dello stesso autore (JuanenRac / Electro Hobby 3D). Vale la pena conoscerlo, poiché una richiesta potrebbe in realtà riguardare uno di questi invece di questo repository.

**Progetto Padre**
- **[HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER)** — il vero backend headless (REST/WebSocket) con cui parla davvero ogni client di controllo; il backend contro cui girano il login, i comandi atomici e la sincronizzazione WebSocket propri di questa app.

**Progetti Fratelli** — parlano anch'essi con la stessa API di HYDRA-UMC-SERVER, ciascuno come proprio client
- **[HYDRA-UMC-STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO)** — dashboard di controllo web con visualizzazione 3D multi-robot in tempo reale; il proprio viewport 3D è incorporato direttamente nella schermata Vista 3D di questa app tramite WebView.
- **[HYDRA-UMC-SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE)** — centro di comando sciame desktop (PySide6) per più server contemporaneamente, pacchettizzato come eseguibile standalone; parla esattamente lo stesso contratto `REMOTE_API.md` di questa app.
- **[HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL)** — app di controllo nativa per Android con login biometrico e un companion Wear OS abbinato; parla esattamente lo stesso contratto `REMOTE_API.md` di questa app.
- **[HYDRA-UMC-DSI](https://github.com/JuanenRac/HYDRA-UMC-DSI)** — interfaccia touch nativa per il touchscreen DSI da 7" a bordo, incorporata direttamente nel CM5.
- **[HYDRA-UMC-BRIDGE-AMR](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-AMR)** — barriera di coordinamento per flotte AGV/AMR tramite un publisher MQTT VDA 5050 reale.
- **[HYDRA-UMC-BRIDGE-CNC](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-CNC)** — coordinatore ad alto livello per celle CNC con accesso reale a stato/byte di controllo GRBL.
- **[HYDRA-UMC-BRIDGE-DROIDS](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-DROIDS)** — barriera di coordinamento per droidi con zampe/umanoidi, con un vero mittente di comandi per Boston Dynamics Spot.
- **[HYDRA-UMC-BRIDGE-LASER](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-LASER)** — coordinatore di sicurezza per celle laser che legge 3 salvaguardie GPIO reali di chiave/involucro/interblocco.
- **[HYDRA-UMC-BRIDGE-OPENPNP](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-OPENPNP)** — coordinatore ad alto livello sicuro per il flusso schede del pick-and-place OpenPnP.
- **[HYDRA-UMC-BRIDGE-PRINTER3D](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-PRINTER3D)** — barriera di coordinamento sicura per stampanti 3D Moonraker/Klipper, con comandi di lavoro reali e controllati.
- **[HYDRA-UMC-BRIDGE-ROS2](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-ROS2)** — coordinatore di sicurezza con un vero trasporto ROS 2 rclpy, importato in modo lazy.
- **[HYDRA-UMC-BRIDGE-UAV](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-UAV)** — barriera di coordinamento per UAV dotati di fotocamera, con un vero mittente di comandi MAVLink.

**Direttamente Correlati**
- **[HYDRA-UMC-WATCH](https://github.com/JuanenRac/HYDRA-UMC-WATCH)** — app companion WearOS con avvisi aptici reali e un relay vocale verso il telefono abbinato; la companion Apple Watch di questa app, per controllo e stato a colpo d'occhio dal polso.
- **[HYDRA-UMC-HIL-BRIDGE](https://github.com/JuanenRac/HYDRA-UMC-HIL-BRIDGE)** — vero interblocco di sicurezza hardware-in-the-loop che instrada i comandi tra simulazione e hardware reale; il bridge che consente a questa app di controllare da remoto il gemello digitale, hardware-in-the-loop.

**Fa Anche Parte dell'Ecosistema**

*Hardware e Piattaforma di Base*
- **[HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC)** — la scheda madre fisica del braccio robotico: host CM5 + coprocessore STM32H745 dual-core, che coordina fino a 8 bracci utensile via CAN-OTA/SPI-OTA.
- **[HYDRA-UMC-OS](https://github.com/JuanenRac/HYDRA-UMC-OS)** — livello prodotto riproducibile su Raspberry Pi OS per il CM5: agente in sola lettura, config/profili validati, provisioning WiFi al primo contatto.
- **[HYDRA-UMC-SDK](https://github.com/JuanenRac/HYDRA-UMC-SDK)** — il contratto JSON-Schema condiviso e la barriera di sicurezza contro cui ogni bridge valida i propri comandi.

*Backend Centrale e Client*
- **[HYDRA-UMC-EDITOR-URDF](https://github.com/JuanenRac/HYDRA-UMC-EDITOR-URDF)** — creatore/editor grafico desktop di URDF che invia i modelli finiti al catalogo di STUDIO.

*Piattaforma Strumenti URTC*
- **[URTC](https://github.com/JuanenRac/URTC)** — firmware per la scheda fisica dell'Universal Robot Tool Controller, oltre 25 profili utensile su bus CAN.
- **[URTC-FLASHER](https://github.com/JuanenRac/URTC-FLASHER)** — strumento desktop con GUI per il flashing delle schede URTC, CAN-OTA più SWD/JTAG a chip intero.
- **[URTC-TESTER](https://github.com/JuanenRac/URTC-TESTER)** — strumento desktop di diagnostica CAN-bus dal vivo per schede URTC, un pannello per profilo utensile.
- **[URTC-WEB-STUDIO](https://github.com/JuanenRac/URTC-WEB-STUDIO)** — alternativa basata su browser a URTC-TESTER tramite la Web Serial API, senza installazione locale.

*Nodo IA Visione (Hailo-8)*
- **[HYDRA-UMC-VISION-NODE](https://github.com/JuanenRac/HYDRA-UMC-VISION-NODE)** — hub di integrazione per la pipeline di visione Hailo-8, con un vero controllo di prontezza hardware per fase.
- **[HYDRA-UMC-DETECTION-HEF](https://github.com/JuanenRac/HYDRA-UMC-DETECTION-HEF)** — registro reale di modelli compilati con verifica di caricamento sicuro per architettura Hailo/checksum.
- **[HYDRA-UMC-VISION-STREAMER](https://github.com/JuanenRac/HYDRA-UMC-VISION-STREAMER)** — generatore reale di pipeline GStreamer + config MediaMTX, con una vera barriera di integrazione HailoRT.
- **[HYDRA-UMC-VISUAL-SERVOING-API](https://github.com/JuanenRac/HYDRA-UMC-VISUAL-SERVOING-API)** — vera legge di correzione Position-Based Visual Servoing, con cancello di sicurezza sullo stato di zona a monte.
- **[HYDRA-UMC-SAFETY-ZONES](https://github.com/JuanenRac/HYDRA-UMC-SAFETY-ZONES)** — vero controllo di violazione zona e richiesta E-STOP, con imposizione della freschezza di calibrazione.

*Nodo IA Cognitivo (Hailo-10)*
- **[HYDRA-UMC-COGNITIVE-NODE](https://github.com/JuanenRac/HYDRA-UMC-COGNITIVE-NODE)** — hub di integrazione per la pipeline cognitiva Hailo-10 (orchestrazione LLM/VLA/voce).
- **[HYDRA-UMC-VLA-ENGINE](https://github.com/JuanenRac/HYDRA-UMC-VLA-ENGINE)** — vera codifica/decodifica di token d'azione e generazione di traiettoria per un modello Vision-Language-Action.
- **[HYDRA-UMC-VOICE-UI](https://github.com/JuanenRac/HYDRA-UMC-VOICE-UI)** — vero front-end vocale (VAD + parser di intenti) con un relay verso Watch limitato e soggetto a conferma.
- **[HYDRA-UMC-SEMANTIC-PLANNER](https://github.com/JuanenRac/HYDRA-UMC-SEMANTIC-PLANNER)** — vera scomposizione dei task basata su regole e recupero semantico degli errori sui codici errore MCU.
- **[HYDRA-UMC-DOCS-QA](https://github.com/JuanenRac/HYDRA-UMC-DOCS-QA)** — vera ricerca documentale TF-IDF (solo libreria standard) sui documenti Markdown di questo ecosistema.

*Orchestrazione e Sciame*
- **[HYDRA-UMC-ORCHESTRATOR](https://github.com/JuanenRac/HYDRA-UMC-ORCHESTRATOR)** — hub di integrazione con un vero contratto di health-report gRPC/Protobuf e una macchina a stati di missione.
- **[HYDRA-UMC-JOB-DISPATCHER](https://github.com/JuanenRac/HYDRA-UMC-JOB-DISPATCHER)** — vera coda di lavori basata su priorità con deduplicazione, su una vera API HTTP.
- **[HYDRA-UMC-NODE-HEALING](https://github.com/JuanenRac/HYDRA-UMC-NODE-HEALING)** — vero watchdog di salute della flotta basato su gRPC, con retry/backoff e rilevamento di discrepanza d'identità.
- **[HYDRA-UMC-PATH-PLANNER-3D](https://github.com/JuanenRac/HYDRA-UMC-PATH-PLANNER-3D)** — vero pianificatore di percorsi 3D basato su RRT, con vera validazione delle collisioni ostacolo/spazio di lavoro.
- **[HYDRA-UMC-SWARM-SYNC](https://github.com/JuanenRac/HYDRA-UMC-SWARM-SYNC)** — vera sincronizzazione di stato CRDT LWW-Element-Map, con property test per la convergenza multi-cella.

*Gemello Digitale e Simulazione*
- **[HYDRA-UMC-TWIN](https://github.com/JuanenRac/HYDRA-UMC-TWIN)** — hub di integrazione per il motore di gemello digitale, con un vero contratto di sincronizzazione per compatibilità di versione.
- **[HYDRA-UMC-PHYSICS-REPLICA](https://github.com/JuanenRac/HYDRA-UMC-PHYSICS-REPLICA)** — vera cinematica diretta e validazione dei limiti articolari su un vero sottoinsieme URDF.
- **[HYDRA-UMC-SYNTHETIC-DATA-GEN](https://github.com/JuanenRac/HYDRA-UMC-SYNTHETIC-DATA-GEN)** — vero generatore procedurale di scene 2D con esportazione di annotazioni YOLO/COCO.

*Dati e Analisi*
- **[HYDRA-UMC-DATALAKE](https://github.com/JuanenRac/HYDRA-UMC-DATALAKE)** — vero archivio di serie temporali basato su sqlite3, con una vera API HTTP di ingestione/query.
- **[HYDRA-UMC-ANOMALY-DETECTOR](https://github.com/JuanenRac/HYDRA-UMC-ANOMALY-DETECTOR)** — vero rilevatore di anomalie FFT + baseline statistica, con monitoraggio della deriva.
- **[HYDRA-UMC-PRODUCTION-REPORTS](https://github.com/JuanenRac/HYDRA-UMC-PRODUCTION-REPORTS)** — vero calcolo OEE/disponibilità sullo storico di DATALAKE, con esportazione CSV riproducibile.
- **[HYDRA-UMC-TELEMETRY-COLLECTOR](https://github.com/JuanenRac/HYDRA-UMC-TELEMETRY-COLLECTOR)** — vera pipeline di ingestione CAN/WebSocket verso DATALAKE, con deduplicazione per sequenza.

*Gateway Industriale*
- **[HYDRA-UMC-GATEWAY-INDUSTRIAL](https://github.com/JuanenRac/HYDRA-UMC-GATEWAY-INDUSTRIAL)** — hub di integrazione che inoltra ai protocolli industriali, con un vero livello di allowlist dei comandi/backpressure.
- **[HYDRA-UMC-OPCUA-SERVER](https://github.com/JuanenRac/HYDRA-UMC-OPCUA-SERVER)** — vero spazio di indirizzi OPC-UA, verificato con una vera sessione client del protocollo binario.
- **[HYDRA-UMC-MQTT-BROKER](https://github.com/JuanenRac/HYDRA-UMC-MQTT-BROKER)** — vero broker MQTT con autenticazione opzionale per client e ACL sui topic.
- **[HYDRA-UMC-MTCONNECT-ADAPTER](https://github.com/JuanenRac/HYDRA-UMC-MTCONNECT-ADAPTER)** — veri endpoint XML `/probe` e `/current` di MTConnect, con output in modalità degradata.

*Strumenti Complementari e Operazioni dell'Ecosistema*
- **[HYDRA-UMC-DASHBOARD-AI](https://github.com/JuanenRac/HYDRA-UMC-DASHBOARD-AI)** — pannelli Smart Summaries e Anomaly Highlighting su DATALAKE/ANOMALY-DETECTOR, con un fallback statistico onesto.
- **[HYDRA-UMC-TOOL-CLI](https://github.com/JuanenRac/HYDRA-UMC-TOOL-CLI)** — CLI di flotta con un vero e stabile contratto di exit-code, un client live reale della stessa API di HYDRA-UMC-SERVER.
- **[URTC-SMART-RACK](https://github.com/JuanenRac/URTC-SMART-RACK)** — firmware per un rack di montaggio schede con decodifica reale dell'ID utensile e logica di preriscaldamento Smart Idle.
- **[URTC-VISION-TOOL](https://github.com/JuanenRac/URTC-VISION-TOOL)** — firmware più un vero companion di visione Python per una testa utensile di ispezione termica/RGB.
- **[HYDRA-UMC-UPDATER](https://github.com/JuanenRac/HYDRA-UMC-UPDATER)** — strumento amministrativo desktop che scopre, clona e aggiorna ogni repository di questo ecosistema.
- **[HYDRA-UMC-OS-REBUILDER](https://github.com/JuanenRac/HYDRA-UMC-OS-REBUILDER)** — strumento desktop Windows/Linux che costruisce un'immagine della CM5 pronta da scrivere, precaricata con le versioni più aggiornate dell'ecosistema, con configurazione di primo avvio Wi-Fi/utente/SSH in stile Raspberry Pi Imager.

---

## 📚 Documentazione e Comunità

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — il contratto di trasporto Wi-Fi che questa app parla con `server.ts` (endpoint per endpoint), perché non esiste ancora una via Bluetooth, il vero meccanismo di discovery a due vie, e la relazione di questa app con il resto dell'ecosistema.
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — stack tecnologico e linee guida di codifica per una pull request.
- **[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)** — gli standard di comportamento attesi in questa comunità.
- **[SECURITY.md](SECURITY.md)** — come segnalare una vulnerabilità, e le reali aree di attenzione sulla sicurezza di questo progetto.
- **[SUPPORT.md](SUPPORT.md)** — dove porre domande e segnalare bug.
- **[LICENSE.md](LICENSE.md)** — la licenza propria di questo progetto.

## 👤 AUTORE
**JuanenRac** (Electro Hobby 3D)
📧 electrohobby3d@gmail.com
📺 [youtube.com/@electrohobby3d](https://youtube.com/@electrohobby3d)

## 📜 LICENZA

GNU General Public License v3.0 (GPL-3.0) per il codice sorgente - vedi [`LICENSE`](LICENSE).

La documentazione (questo README e le sue proprie traduzioni - `README_spa.md`, `README_ita.md`, `README_fra.md`, `README_deu.md`, `README_zho.md`, `README_jpn.md`) è disponibile sotto **Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)**. Testo completo su https://creativecommons.org/licenses/by-sa/4.0/.
