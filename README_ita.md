<!-- =============================================================================
HYDRA-UMC-IOS-CONTROL - iOS and iPadOS operator console for a HYDRA-UMC server, written in Flutter
Copyright (C) JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
GPL-3.0-or-later - see LICENSE
============================================================================= -->

<p align="center">
  <img src="images/HYDRA_UMC_BANNER.svg" alt="HYDRA-UMC-IOS-CONTROL banner" width="100%">
</p>

# 🍎 HYDRA-UMC-IOS-CONTROL

<p align="center"><a href="README.md">🇺🇸 English</a> | <a href="README_spa.md">🇪🇸 Español</a> | <a href="README_fra.md">🇫🇷 Français</a> | 🇮🇹 <b>Italiano</b> | <a href="README_deu.md">🇩🇪 Deutsch</a> | <a href="README_zho.md">🇨🇳 简体中文</a> | <a href="README_jpn.md">🇯🇵 日本語</a> | <a href="README_por.md">🇵🇹 Português</a></p>

### I tuoi robot HYDRA-UMC su iPhone o iPad: trova il server, muovi e guarda i robot e ferma tutto con un pulsante rosso.

<p align="center">
  <img src="https://img.shields.io/badge/License-GPL%203.0--or--later-blue.svg" alt="GPL 3.0 or later">
  <img src="https://img.shields.io/badge/Framework-Flutter-02569B.svg" alt="Framework">
  <img src="https://img.shields.io/badge/Language-Dart-0175C2.svg" alt="Language">
  <img src="https://img.shields.io/badge/Platform-iOS-000000.svg" alt="Platform">
  <img src="https://img.shields.io/badge/Tests-220%20passing-2ea44f.svg" alt="Tests">
  <img src="https://img.shields.io/badge/Version-0.2.7-0f6cbd.svg" alt="Version">
  <img src="https://img.shields.io/badge/Maturity-functional-0F6CBD.svg" alt="Maturity">
</p>

---

Un'app Flutter (Dart) multipiattaforma che controlla un robot sulla piattaforma [HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC) via Wi-Fi, parlando esattamente lo stesso contratto [`REMOTE_API.md`](https://github.com/JuanenRac/HYDRA-UMC-SERVER/blob/main/docs/REMOTE_API.md) usato da [HYDRA-UMC SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE) e [HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL) - discovery, login, comandi atomici per robot, e sincronizzazione WebSocket in tempo reale contro un'istanza di [HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER) in esecuzione (il backend headless separato dal processo di HYDRA-UMC STUDIO - STUDIO e ora un puro client frontend di quel server, come questa app).

> **Stato di sicurezza (safety e security):** questo ecosistema non è un sistema di sicurezza certificato. Non esiste ancora un percorso E-STOP hardware, né limiti o interblocchi imposti dal firmware, né un comando di movimento verificato; le immagini firmware sono controllate con CRC-32 e una firma Ed25519, e una compilazione di rilascio rifiuta le chiavi di sviluppo pubblicate (le teste utensile e le schede di espansione dietro il relè usano ancora i bootloader di URTC, che accettano un HMAC-SHA256 a chiave condivisa invece di una firma); TLS e TLS reciproco sono opzionali e disattivati per impostazione predefinita; nessuna scheda propria è stata ancora assemblata o provata. Leggi la [base di sicurezza](https://github.com/JuanenRac/HYDRA-UMC-DOCS/blob/main/docs/SECURITY_BASELINE.md) e il [modello delle minacce](https://github.com/JuanenRac/HYDRA-UMC-DOCS/blob/main/docs/THREAT_MODEL.md) prima di fidarti di qualsiasi affermazione qui per la sicurezza di una persona.

---

## 📋 In breve

| | |
|---|---|
| Versione | `0.2.7` |
| Maturità | Funzionale |
| Test | 220 (`flutter test`) |
| Tecnologia | Flutter 3.x / Dart |
| Destinazione | Un iPhone o iPad |
| Su hardware reale | Non ancora: per questa versione non risulta alcuna esecuzione su hardware reale |

**Vai a:** [Panoramica](#-panoramica) · [Architettura](#-architettura) · [Funzionalità](#-funzionalità) · [Sicurezza e protezione](#-sicurezza-e-protezione) · [Interfacce](#-interfacce) · [Configurazione](#-configurazione) · [Avvio rapido](#-avvio-rapido) · [Test](#-test) · [Risoluzione dei problemi](#-risoluzione-dei-problemi) · [Struttura del repository](#-struttura-del-repository) · [Progetti correlati](#-progetti-correlati)

## 🚦 Stato del progetto

Ogni riga è una parte di questo repository e il semaforo dice a che punto è oggi. È scritta in base a ciò che il repository può mostrare (test, compilazioni, esecuzioni), non a ciò che è previsto.

🟢 Fatto e verificato · 🟡 Funziona, con limiti noti · 🟠 Fatto a metà o non ancora verificato · 🔴 Non fatto o non funzionante

| Area | Stato | Cosa significa qui |
|---|---|---|
| Software | 🟡 | Funziona per il suo scopo principale; la verifica di onestà qui sopra elenca ciò che manca ancora |
| Test | 🟢 | 220 test automatici, eseguiti a ogni modifica |
| Hardware reale | 🔴 | Non ancora: per questa versione non risulta alcuna esecuzione su hardware reale |
| Documentazione | 🟢 | README in otto lingue, verificato rispetto al manifesto a ogni modifica |

## 🎯 Panoramica

Schermate dell'app: **accesso** (indirizzo del server, account, una scansione della rete locale), **pannello** (una scheda per robot con il suo LED dal vivo e la salute del modulo di calcolo), **controllo** (croce di movimento, velocità, valvole e pompe, prenotazione del robot, PLAY con una domanda facoltativa prima), **telecamera** (MJPEG dal vivo), **vista 3D** (la scena reale di STUDIO), **telemetria** (un registro in stile terminale) e **impostazioni** (lingua, blocco biometrico, interruttori). Un pulsante rosso **STOP** è nella barra di ogni scheda.

## 🧩 Ruolo in HYDRA-UMC

**HYDRA-UMC-IOS-CONTROL** è la console operatore di HYDRA-UMC per iPhone e iPad. È scritta in Flutter così che la sua logica si possa compilare, eseguire e testare su Windows; la compilazione iOS richiede comunque Xcode su un Mac. Trova un HYDRA-UMC-SERVER sulla rete locale, accede, mostra e muove i robot, guarda le loro telecamere e una vista 3D, e ferma tutto con un tocco, con lo stesso contratto remoto della SUITE e dell'app Android. Non è un dispositivo di sicurezza.

## 🏛️ Architettura

<p align="center">
  <img src="images/architecture.svg" alt="HYDRA-UMC-IOS-CONTROL architecture" width="100%">
</p>

### Perché Flutter, non Swift nativo

Questa app punta a iOS/iPadOS, ma è costruita in **Flutter** anziché Swift/SwiftUI: l'ambiente di lavoro di questo repository è esclusivamente Windows, e un progetto Swift nativo si può *scrivere* su Windows ma mai *compilare o eseguire* lì (Xcode e l'SDK iOS sono esclusivi di macOS). Il target desktop Windows proprio di Flutter permette a questa app di essere costruita, eseguita e testata davvero su questa macchina - `flutter analyze` pulito, `flutter build windows` riuscito, `flutter test` superato, e l'`.exe` compilato che si avvia e renderizza senza errori a runtime - invece di scrivere migliaia di righe di Swift alla cieca, senza alcun modo di verificarne alcuna finché non è disponibile un Mac.

**Questo non rimuove la restrizione propria di Apple** - un `.ipa` reale richiede comunque Xcode su un Mac (o un runner CI macOS) per essere compilato e firmato; nulla nella scelta del framework cambia questo. Ciò che Flutter offre è la capacità di verificare ogni altra riga della logica propria di questa app (rete, stato, UI) su questa macchina oggi, e di spedire una base di codice identica a iOS in seguito senza riscriverla.

## ✨ Funzionalità

- **Login** (`lib/ui/login_screen.dart`, `lib/state/robot_view_model.dart`) - campi modificabili di IP/porta e credenziali operatore più `POST /api/login`; nessun account o password è precompilato. Un server di produzione richiede credenziali bootstrap configurate esplicitamente per il primo amministratore; account "operator" aggiuntivi a privilegio inferiore possono essere creati da Config > Users nell'interfaccia browser. Il token di sessione persiste nel portachiavi iOS (`flutter_secure_storage`); host e porta sono conservati con `shared_preferences`. Un pulsante "Scan local network" (`lib/network/discovery.dart`) trova i server senza che l'utente debba già conoscere l'IP.
- **Discovery di rete** (`lib/network/discovery.dart`) - due percorsi indipendenti girano insieme dal foglio "Scan local network": mDNS/Bonjour reale (`discoverMdns()`, interroga il servizio `_hydra._tcp.local` pubblicato da `server.ts` tramite il pacchetto `multicast_dns` - questa app è la prima dei 3 client remoti dell'ecosistema ad aggiungerlo) più una scansione concorrente a forza bruta di `GET /api/hydra-info` attraverso la(e) sottorete(i) locale(i) reale(i) propria(e) di questo dispositivo (`scanSubnets()`, derivata dal `NetworkInterface.list()` proprio di `dart:io` invece di un'unica ipotesi fissa, dato che la LAN di un telefono ha altrettante probabilità di essere `192.168.0.x` o `10.x.x.x` quanto `192.168.1.x`, ricadendo su `192.168.1.x` solo se l'enumerazione delle interfacce stessa risulta vuota). Che mDNS fallisca silenziosamente su una build iOS senza l'entitlement è previsto (l'entitlement Multicast Networking di Apple non è concesso da una `flutter build ios` normale) - la scansione di sottorete continua a funzionare in modo indipendente comunque.
- **Blocco biometrico** (`lib/network/biometric_helper.dart`, `lib/ui/biometric_gate_screen.dart`) - Face ID/Touch ID/Windows Hello tramite `package:local_auth`, un interruttore opzionale in `Settings` che protegge il ripristino di una sessione salvata valida all'avvio (questa app non salva mai una password in chiaro, solo un token - adattato dal design di reinserimento password proprio di HYDRA-UMC-ANDROID-CONTROL a questa differenza).
- **Sincronizzazione comandi atomici** (il `_sendAtomicCommand()` proprio di `lib/state/robot_view_model.dart`) - ogni scrittura (play/pause/stop/jog/valve/pump/speed/vision) usa l'endpoint reale `POST /api/robot/:id/command`, un payload piccolo e mirato invece di sovrascrivere l'intero albero settings, con propagazione corretta del robot combinato (`combinedWith`) per i 5 comandi che ne hanno bisogno.
- **Sincronizzazione WebSocket in tempo reale** (`lib/network/hydra_websocket.dart`) - invia il token come sottoprotocollo `hydra.bearer` e mai nell'URL di connessione (`server.ts` rifiuta `/ws?token=` per impostazione predefinita), gestisce sia i tipi di broadcast `"settings"` che `"delta"`, si riconnette automaticamente alla caduta.
- **Dashboard** (`lib/ui/dashboard_screen.dart`) - schede per robot, reattive in tempo reale tramite il `ChangeNotifier` proprio di `Provider`, convenzione LED (verde pulsante = attivo, rosso fisso = inattivo) e visualizzazione robot combinato (mostrata solo sul lato follower, risolta per id) che corrisponde alla propria Dashboard Overview di HYDRA-UMC-STUDIO.
- **Controllo Manuale** (`lib/ui/control_screen.dart`, `lib/ui/widgets/joystick_pad.dart`) - D-pad di jog (con/senza target tavola XY), slider velocità/accelerazione, interruttori valvola/pompa, e lo **STOP** globale (`lib/ui/widgets/stop_all.dart`): un solo tocco, senza pressione prolungata né conferma, ferma tutti i robot (`POST /api/stop-all`) e sta nella barra superiore di ogni scheda, anche in quella di Controllo. La risposta è mostrata robot per robot (avviso se un robot è fallito o l'arresto non è stato salvato; i robot riservati da un altro account sono segnalati), un errore di rete viene ritentato una volta, un server oltre il suo limite di richieste o senza quella route riceve l'arresto robot per robot, e se nessuno risponde resta un avviso permanente «STOP non confermato» finché uno STOP successivo non ottiene risposta. Il pulsante rotondo di arresto per robot mantiene la sua protezione a pressione prolungata.
- **Prenotazioni e limiti di sicurezza** (`lib/ui/widgets/access_panel.dart`, `lib/models/access.dart`, `lib/network/hydra_api_client.dart`, `lib/state/robot_view_model.dart`) - La schermata Control mostra chi tiene il robot selezionato (nessuno, questo dispositivo, lo stesso account su un altro dispositivo o un altro account) e offre **Prenota** e **Rilascia**, oltre all’elenco di tutte le prenotazioni del server (`GET /api/claims`). Il dispositivo conserva un identificativo di controller per installazione e lo invia con ogni prenotazione, rilascio, armamento del jog e comando (corpo e intestazione `X-Controller-Id`): la prenotazione appartiene quindi all’account e a questo dispositivo, non a tutto l’account. I rifiuti del server sono distinti: prenotato da un altro account, dal tuo account su un altro dispositivo o finestra, identificativo di controller richiesto e jog non armato. I limiti del modello del robot si leggono da `GET /api/safety-limits`: un passo di jog oltre il limite non viene inviato e gli avvisi del server sono mostrati. Quando l’amministratore lo richiede, bisogna premere **Arma il jog** (con conto alla rovescia) prima che il joystick muova il robot; l’armamento termina da solo, con STOP o al rilascio. Le prenotazioni sono facoltative: un robot che nessuno ha prenotato si comanda come prima. Solo per un **amministratore** compare un pulsante **Prendi il controllo** su un robot detenuto da un altro; chiede conferma e poi prenota il robot con `force: true` (il server lo accetta solo dagli amministratori e ricontrolla il ruolo). Le scritture sono condizionali: ognuna porta la revisione del robot che questa app ha visto per ultima (`If-Match`, `lib/models/contract_v2.dart`); se nel frattempo qualcun altro ha modificato il robot, il server risponde 412, non viene applicato nulla, il robot viene riletto e il messaggio lo dice (Standard verifica prenotazioni, tavola e comandi singoli; Rigoroso verifica tutto tranne STOP; Disattivato non verifica nulla; la scelta è nell'elenco delle prenotazioni; STOP non è mai verificato). Il jog della tavola XY è un unico comando atomico `table` (un server più vecchio riceve i jog che capisce), il server invia le prenotazioni sul WebSocket così la schermata Control smette di interrogare mentre arrivano, e gli amministratori leggono il registro di audit (`lib/ui/widgets/audit_dialog.dart`) con la catena SHA-256 verificata due volte, dal server e sul dispositivo, e possono copiarne le righe come `.jsonl`.
- **Interruttori opzionali** - due interruttori, entrambi spenti per impostazione predefinita: *Blocca i comandi sui dati salvati* (Impostazioni) trattiene ogni comando tranne lo STOP finché lo schermo mostra la copia salvata dello stato dei robot e non lo stato reale, e *Non scansionare reti dati mobili né VPN* (schermata di accesso) esclude quelle interfacce dalla scansione della sottorete. I pulsanti del D-pad di jog misurano almeno 44 pt e VoiceOver li annuncia con asse e direzione; l'immagine della telecamera viene chiusa mentre l'app è in background.
- **Chiedere prima di PLAY** - attivo per impostazione predefinita, si disattiva nelle Impostazioni: prima di avviare una traiettoria l'app mostra il robot, i suoi punti registrati, la velocità e chi lo ha prenotato (un robot prenotato da un altro segnala che il server rifiuterà il comando). Un robot già in riproduzione non viene richiesto di nuovo. La scelta viene conservata.
- **Camera** (`lib/ui/camera_screen.dart`, `lib/ui/widgets/mjpeg_view.dart`) - un piccolo parser dello stream MJPEG scritto a mano (nessun pacchetto di terze parti), uno stato chiaro "Camera Disabled" invece di un feed vuoto silenzioso, e un interruttore per attivare/disattivare il sistema di visione di un robot direttamente dal server (il comando atomico `"vision"` proprio di `server.ts`).
- **Vista 3D** (`lib/ui/three_d_screen.dart`) - incorpora il viewport 3D in tempo reale proprio di HYDRA-UMC-STUDIO in una WebView (`?hideUI=true&robotId=#token=`), lo stesso approccio dell'app Android, per lo stesso motivo (ottiene gratuitamente la scena 3D reale, attualmente in produzione). Ricade su un placeholder onesto sulle piattaforme che `webview_flutter` non supporta (il target desktop Windows di questo repository, usato per la verifica della build).
- **Metriche di sistema** (`lib/state/robot_view_model.dart`) - `GET /api/system/metrics` interrogato ogni 5s, la stessa cadenza degli altri 2 client, mostrato nella Dashboard.
- **UI in 8 lingue** (`lib/l10n/`, pipeline standard `flutter gen-l10n`) - inglese, spagnolo, francese, tedesco, italiano, giapponese, cinese e portoghese, come il resto dei client di questo ecosistema. Un'impostazione persistente in `Impostazioni > Lingua` usa come predefinita la lingua di sistema; `RobotViewModel.lastError` è un `HydraError` tipizzato invece di testo inglese già formattato, quindi anche i messaggi di errore della logica di business (errori di accesso/connessione/comando) vengono tradotti correttamente, non solo il testo statico delle schermate.
- **Cache di stato offline** (`lib/network/state_cache.dart`) - l'ultimo albero di impostazioni noto viene salvato su disco (con debounce di 1s) insieme al vero istante di salvataggio, così le schermate Dashboard/Controllo mostrano dati reali, anche se potenzialmente non aggiornati, subito all'avvio invece di uno stato vuoto mentre il vero `connect()` è ancora in corso. Un banner reale e visibile (non una semplice supposizione silenziosa) mostra "dati in cache dalle HH:mm" finché ciò resta vero. Sostituito dai dati reali non appena la connessione ha successo.
- **Telemetria** (`lib/ui/telemetry_screen.dart`) - un registro in stile terminale, più recente per primo, di eventi reali di connessione/accesso/comando, limitato a 50 voci, con un'azione per cancellarlo - la stessa convenzione "verde Matrix" della scheda Telemetria di HYDRA-UMC-ANDROID-CONTROL.
- **Assistente Vocale in App** (`lib/ui/voice_assistant_dialog.dart`) - un'icona del microfono nella barra dell'app apre una finestra di dialogo per digitare una domanda o un ordine, inviata a `HYDRA-UMC-VOICE-UI` tramite la stessa rotta reale `POST /api/voice/turn` usata dal pulsante vocale in-app e dal relay con l'orologio abbinato di HYDRA-UMC-ANDROID-CONTROL. Non carica mai l'audio - solo testo per ora, poiché il riconoscimento vocale nativo di iOS richiede il framework Speech, che questo ambiente di sviluppo solo-Windows non può compilare né verificare su un dispositivo reale/Xcode. Una risposta non emette mai un comando robot direttamente.

## 🔒 Sicurezza e protezione

| Minaccia | Difesa | Dove |
|---|---|---|
| Un token rubato dal telefono | Il token, il nome utente e il token di rinnovo sono conservati con `flutter_secure_storage` (il portachiavi iOS); solo host, porta e preferenze vanno in `shared_preferences`; l'app non salva mai una password in chiaro | `network/auth_prefs.dart` |
| Credenziali nella copia salvata dello stato | La copia dell'ultimo stato scritta su disco perde le chiavi `ipUsername` e `ipPassword` a qualsiasi profondità, e viene cancellata all'uscita | `network/state_cache.dart` |
| Il token in un registro o nell'indirizzo del WebSocket | Il token va nel sottoprotocollo `hydra.bearer` del WebSocket e mai nel suo indirizzo; la vista 3D incorporata lo riceve nel frammento dell'indirizzo (`#token=`), che non viene inviato al server; un test verifica entrambe le cose | `network/hydra_websocket.dart`, `util/viewer_url.dart` |
| Qualcuno con il telefono sbloccato | Un blocco biometrico facoltativo (Face ID, Touch ID) condiziona il ripristino di una sessione salvata all'avvio; l'immagine della telecamera si chiude mentre l'app è in background | `network/biometric_helper.dart`, `ui/biometric_gate_screen.dart` |
| Un robot mosso da due persone, un PLAY premuto per errore o uno stop che non arriva | Il robot viene prenotato prima di muoverlo e lo schermo dice chi lo detiene; PLAY chiede prima per impostazione predefinita e mostra il robot, i suoi punti, la velocità e chi lo ha prenotato; lo STOP globale è ritentato una volta, ricade su uno stop per robot e mantiene un banner persistente «STOP non confermato» se nessuno ha risposto | `models/access.dart`, `util/play_confirmation.dart`, `ui/widgets/stop_all.dart` |

**Cosa non fa mai:** sostituire un arresto di emergenza fisico, né cifrare da sola il traffico: l'app prova HTTPS una volta quando una sonda HTTP in chiaro non riceve risposta, e non ha il pinning dei certificati né una protezione dal traffico in chiaro fuori dalla rete locale. Lo STOP è lo stop software del server.

## 🔌 Interfacce

| Topic o rotta | Cosa porta |
|---|---|
| `POST /api/login`, `/api/logout`, `/api/refresh` | accedere, uscire e rinnovare la sessione |
| `GET /api/hydra-info` | riconosce un vero server; usato dalla scansione della sottorete e dall'indirizzo manuale, con un nuovo tentativo in HTTPS |
| `GET /api/settings`, `/api/system/metrics`, `/api/safety-limits`, `/api/claims` | lo stato dei robot, il modulo di calcolo (ogni 5 s), i limiti di sicurezza di ogni modello e le prenotazioni |
| `POST /api/robot/{id}/command`, `/claim`, `/release`, jog arming | un piccolo comando per un robot, la sua prenotazione e l'armamento di un movimento manuale, con scritture condizionali per revisione del robot |
| `POST /api/stop-all` | lo STOP globale: tutti i robot, con risposta robot per robot |
| `GET /api/audit`, `POST /api/voice/turn`, `GET /api/camera/{id}/stream` | il registro di audit (amministratori, con il proprio controllo della catena SHA-256), un turno vocale scritto e il flusso MJPEG di una telecamera |
| WebSocket `hydra.bearer`, mDNS `_hydra._tcp.local` | cambiamenti di stato in tempo reale (messaggi `settings` e `delta`, riconnessione dopo 3 s fino a 30 s, un ping ogni 20 s) e l'annuncio Bonjour del server |

## ⚙️ Configurazione

L'app non ha un file di configurazione: tutto si imposta sullo schermo e si salva sul dispositivo. I valori predefiniti vengono dal codice.

| Variabile | Predefinito | Cosa imposta |
|---|---|---|
| Impostazioni > Chiedi prima di PLAY | attivato | mostra il robot, i suoi punti, la velocità e chi lo ha prenotato prima che parta una traiettoria |
| Impostazioni > Blocca i comandi sui dati salvati | disattivato | trattiene ogni comando tranne STOP finché lo schermo mostra la copia salvata dello stato invece di quello in tempo reale |
| Accesso > Non scansionare reti dati mobili né VPN | disattivato | lascia fuori quelle interfacce dalla scansione della sottorete (32 host alla volta, porta 3000 salvo che ne digiti un'altra) |
| Impostazioni > Blocco biometrico | disattivato | chiede Face ID o Touch ID prima di ripristinare una sessione salvata all'avvio |
| Impostazioni > Lingua | la lingua del sistema | una delle otto lingue dell'app (`lib/l10n/`), mantenuta tra gli avvii |

## 🚀 Avvio rapido

Richiede l'SDK Flutter stabile (Dart 3.13 o successivo). Windows esegue la logica e i test; una vera compilazione per iPhone richiede Xcode su un Mac.

```bash
flutter pub get                  # downloads the packages
flutter test                     # runs the unit tests on this machine
./build-test.sh                  # non-mutating build check (build-test.bat on Windows)
flutter build ios --no-codesign  # a real iOS build; only on a Mac with Xcode
```

## 🧪 Test

220 test automatici si eseguono con `flutter test`. Non richiedono hardware né nulla al di fuori di questa macchina.

La CI esegue `HYDRA_UMC_CI=1 python tools/ci_validate.py`, che controlla il manifesto, i documenti, gli otto README e le immagini.

## 🏗️ Compilazione e rilascio

Richiede il [Flutter SDK](https://docs.flutter.dev/get-started/install) (canale stable). Questo repository è compilato/verificato contro Flutter 3.47.0. Solo `windows/` e `ios/` sono configurate come piattaforme in questo repository (nessuna cartella `android/`, `linux/`, `web/`, o `macos/`) - Windows esiste affinché la logica propria di questa app possa essere compilata ed eseguita senza un Mac; iOS è l'obiettivo reale.

### Script di build

```bash
./build.sh     # Git Bash / WSL - flutter pub get + flutter build windows
build.bat      # cmd.exe / PowerShell - flutter pub get + flutter build windows
```

Entrambi producono `build/windows/x64/runner/Release/hydra_umc_control.exe`, ed entrambi non cambiano la versione dell'app - vedi [Versioning](#-versioning) più sotto.

### Build manuale

```bash
flutter pub get
flutter analyze          # analisi statica - nessun compilatore necessario
flutter test             # widget test
dart run tool/bump_version.dart  # incrementa la versione, come fanno build.sh/build.bat
flutter build windows    # produce build/windows/x64/runner/Release/hydra_umc_control.exe
flutter run -d windows   # oppure -d <ios-device-id> da un Mac
```

**Compilare il vero `.ipa` iOS** richiede Xcode su macOS - da quella macchina: `flutter build ipa` (oppure aprire `ios/Runner.xcworkspace` direttamente in Xcode). Questo non si può fare da Windows; vedi "Perché Flutter, non Swift nativo" sopra.

### Versioning

Questo repository segue una politica a livello di ecosistema: compilare non cambia mai la versione. Il comando `bump` esplicito (`python tools/hydra_project_tool.py bump`) esegue `tool/bump_version.dart`, che applica:

- **Patch, stile contachilometri (base 10):** +1 a ogni bump; una
  volta superato 9 si resetta a 0 e minor sale di +1 - es. `0.0.9` ->
  `0.1.0`. Major non viene mai toccato automaticamente.
- **Build number** (la parte dopo `+`): un contatore monotono semplice,
  +1 a ogni bump, senza riporto.

Lo stesso script rigenera `lib/app_version.dart` (generato, non
modificato a mano - un semplice file `const`, non una nuova dipendenza
a runtime come `package_info_plus`), che l'app legge a runtime per
mostrare la propria versione nella schermata **Impostazioni**. Vedi
[CHANGELOG.md](CHANGELOG.md) per la cronologia delle versioni.

## 🩺 Risoluzione dei problemi

| Vedi | Perché | Fai |
|---|---|---|
| «Sessione non autorizzata: accedi di nuovo» | Il server ha rifiutato il token (il WebSocket è stato chiuso con il codice 1008) o è scaduto | Accedi di nuovo |
| «STOP non confermato dal server» | Nulla ha risposto allo STOP globale entro il suo breve limite di tempo, o il server non ha potuto salvare lo stato di arresto | Premilo di nuovo; se il banner resta, usa l'arresto di emergenza fisico |
| Il robot è prenotato da un altro account, o dal tuo account su un altro dispositivo | Una prenotazione appartiene all'account e al dispositivo (un id controller per installazione) | Usa quel dispositivo, o rilascia lì la prenotazione |
| «Dati salvati delle HH:mm» | Il server è irraggiungibile e lo schermo mostra la copia salvata dell'ultimo stato; con Blocca i comandi sui dati salvati attivo, ogni comando tranne STOP è trattenuto | Controlla il server e il Wi-Fi; lo schermo torna in tempo reale da solo quando la connessione torna |
| «Movimento rifiutato: il passo supera il limite» | Il passo supera il limite che il server imposta per questo modello di robot (`GET /api/safety-limits`) | Usa un passo più piccolo; non è stato inviato nulla |
| «Scansiona rete locale» non trova nessun server | Su un vero iPhone Bonjour richiede un'autorizzazione che una compilazione semplice non ha, e la scansione può escludere le reti dati mobili e VPN | Collegati allo stesso Wi-Fi del server, o digita a mano indirizzo e porta |

## 📂 Struttura del repository

<p align="center">
  <img src="images/repository-structure.svg" alt="Repository structure of HYDRA-UMC-IOS-CONTROL" width="100%">
</p>

<details>
<summary>Versione testuale dell'albero</summary>

```text
HYDRA-UMC-IOS-CONTROL/
├── lib/                                                              codice sorgente
│   ├── main.dart                                                     Punto di ingresso dell'app, ChangeNotifierProvider + gate di login
│   ├── app_version.dart                                              GENERATO - rigenerato da tool/bump_version.dart, non modificare a mano
│   ├── models/                                                       modelli di dati e regole pure
│   ├── network/                                                      client REST, WebSocket e individuazione
│   ├── state/                                                        lo stato che ogni schermata ascolta
│   ├── l10n/                                                         Localizzazioni reali generate (8 lingue) - vedi l10n.yaml nella radice del repo
│   ├── util/                                                         Utilità senza schermata propria
│   └── ui/                                                           schermate e widget
├── tool/                                                             strumento per le versioni
├── ios/                                                              Progetto Xcode (compilare solo da macOS)
├── windows/                                                          Target desktop Windows - verifica della build senza un Mac
├── tools/                                                            strumenti del progetto e controlli della CI
├── test/                                                             i test unitari della logica
├── images/                                                           banner e immagini del README
├── .github/                                                          workflow di CI e modelli di segnalazione
├── build.bat / build.sh                                              flutter pub get, poi flutter build windows; non cambia mai la versione
├── docs/ARCHITECTURE.md                                              architettura del progetto
├── pubspec.yaml / pubspec.lock / l10n.yaml / analysis_options.yaml   La definizione del pacchetto Flutter e le sue versioni bloccate, le impostazioni del generatore l10n e le regole di lint
├── CHANGELOG.md                                                      cosa è cambiato in ogni versione
├── build-test.sh                                                     controllo di build senza modifiche
├── bump_manifest_version.py                                          sincronizza la versione del manifesto
├── hydra-umc.project.json                                            manifesto: versione, maturità, famiglia
└── test.sh                                                           controllo di build senza modifiche (flutter test esegue i test unitari)
```

</details>

## 🗺️ Roadmap e limiti noti

Nella CI non c'è una compilazione per iPhone o iPad: `flutter build ios` richiede Xcode su un Mac, quindi l'app è stata eseguita e testata solo su Windows. La scoperta Bonjour richiede un'autorizzazione che una compilazione semplice non ha, quindi su un vero iPhone è la scansione della sottorete a trovare il server. Non c'è ancora il riconoscimento vocale sul dispositivo (l'assistente vocale accetta testo digitato), né impostazioni TLS né Bluetooth.

## 🌍 Lingue

Questo README e i documenti del repository esistono in otto lingue: inglese, spagnolo, tedesco, francese, italiano, giapponese, cinese e portoghese (Portogallo). Sono scritti insieme e la CI verifica che gli otto file abbiano le stesse sezioni e gli stessi link.

## 🔗 Progetti correlati

Questo progetto fa parte dell'ecosistema robotico HYDRA-UMC dello stesso autore (JuanenRac / Electro Hobby 3D). Vale la pena conoscerlo, poiché una richiesta potrebbe in realtà riguardare uno di questi invece di questo repository.

**Progetto Padre**
- **[HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER)** — il vero backend headless (REST/WebSocket) con cui parla davvero ogni client di controllo; il backend contro cui girano il login, i comandi atomici e la sincronizzazione WebSocket propri di questa app.

**Progetti Fratelli** — parlano anch'essi con la stessa API di HYDRA-UMC-SERVER, ciascuno come proprio client
- **[HYDRA-UMC-STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO)** — dashboard di controllo web con visualizzazione 3D multi-robot in tempo reale; il proprio viewport 3D è incorporato direttamente nella schermata Vista 3D di questa app tramite WebView.
- **[HYDRA-UMC-SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE)** — centro di comando sciame desktop (PySide6) per più server contemporaneamente, pacchettizzato come eseguibile standalone; parla esattamente lo stesso contratto `REMOTE_API.md` di questa app.
- **[HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL)** — app di controllo nativa per Android con login biometrico e un companion Wear OS abbinato; parla esattamente lo stesso contratto `REMOTE_API.md` di questa app.
- **[HYDRA-UMC-DSI](https://github.com/JuanenRac/HYDRA-UMC-DSI)** — interfaccia touch nativa per il touchscreen DSI da 7" a bordo, incorporata direttamente nel CM5.
- **[HYDRA-UMC-BRIDGE-AMR](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-AMR)** — barriera di coordinamento per flotte AGV/AMR tramite un publisher MQTT VDA 5050 (testato solo contro una flotta emulata).
- **[HYDRA-UMC-BRIDGE-CNC](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-CNC)** — coordinatore ad alto livello per celle CNC con accesso a stato/byte di controllo GRBL (testato solo contro un emulatore).
- **[HYDRA-UMC-BRIDGE-DROIDS](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-DROIDS)** — barriera di coordinamento per droidi con zampe/umanoidi, con un mittente di comandi per Boston Dynamics Spot (testato solo contro un emulatore).
- **[HYDRA-UMC-BRIDGE-LASER](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-LASER)** — coordinatore per celle laser che legge 3 segnali GPIO di chiave/involucro/interblocco (testato solo contro un chip simulato; non può armare né far partire un laser).
- **[HYDRA-UMC-BRIDGE-OPENPNP](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-OPENPNP)** — coordinatore ad alto livello sicuro per il flusso schede del pick-and-place OpenPnP.
- **[HYDRA-UMC-BRIDGE-PRINTER3D](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-PRINTER3D)** — barriera di coordinamento sicura per stampanti 3D Moonraker/Klipper, con comandi di lavoro reali e controllati.
- **[HYDRA-UMC-BRIDGE-ROS2](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-ROS2)** — coordinatore con un trasporto ROS 2 rclpy importato in modo lazy (non ancora eseguito contro un'installazione ROS 2).
- **[HYDRA-UMC-BRIDGE-UAV](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-UAV)** — barriera di coordinamento per UAV dotati di fotocamera, con un mittente di comandi MAVLink (testato solo contro un emulatore).

**Direttamente Correlati**
- **[HYDRA-UMC-WATCH](https://github.com/JuanenRac/HYDRA-UMC-WATCH)** — app companion WearOS con schemi di avviso aptico e un relay vocale verso il telefono abbinato (non ancora eseguita su un orologio fisico); la companion da polso di HYDRA-UMC-ANDROID-CONTROL (solo WearOS: questa app iOS non ha ancora un equivalente per Apple Watch).
- **[HYDRA-UMC-HIL-BRIDGE](https://github.com/JuanenRac/HYDRA-UMC-HIL-BRIDGE)** — router hardware-in-the-loop con un interblocco software di collisione tra simulazione e hardware reale (testato senza hardware reale); il bridge che consente a questa app di controllare da remoto il gemello digitale, hardware-in-the-loop.

**Fa Anche Parte dell'Ecosistema**

*Hardware e Piattaforma di Base*
- **[HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC)** — il progetto della scheda madre del braccio robotico: host CM5 + coprocessore STM32H745 dual-core, pensato per coordinare fino a 8 bracci utensile via CAN-OTA/SPI-OTA (firmware in fase iniziale; nessuna scheda assemblata per ora).
- **[HYDRA-UMC-OS](https://github.com/JuanenRac/HYDRA-UMC-OS)** — livello prodotto riproducibile su Raspberry Pi OS per il CM5: agente in sola lettura, config/profili validati, provisioning WiFi al primo contatto.
- **[HYDRA-UMC-SDK](https://github.com/JuanenRac/HYDRA-UMC-SDK)** — il contratto JSON-Schema condiviso e la barriera software di controllo dei job contro cui ogni bridge valida i propri comandi (non è una funzione di sicurezza certificata).
- **[HYDRA-UMC-CONNECTOR-HUB](https://github.com/JuanenRac/HYDRA-UMC-CONNECTOR-HUB)** — registro dichiarativo e validatore di manifesti adattatore per connettori di macchine esterne; estende la propria idea di contratto dell'SDK alle macchine esterne senza sostituire i progetti di gateway industriale.

*Backend Centrale e Client*
- **[HYDRA-UMC-EDITOR-URDF](https://github.com/JuanenRac/HYDRA-UMC-EDITOR-URDF)** — creatore/editor grafico desktop di URDF che invia i modelli finiti al catalogo di STUDIO.
- **[HYDRA-UMC-EDITOR-STL](https://github.com/JuanenRac/HYDRA-UMC-EDITOR-STL)** — editor desktop di modelli STL, che trasforma/sostituisce/rimuove/aggiunge veri pezzi nello stesso catalogo di modelli modificato anche da HYDRA-UMC-EDITOR-URDF.

*Piattaforma Strumenti URTC*
- **[URTC](https://github.com/JuanenRac/URTC)** — firmware per la scheda fisica dell'Universal Robot Tool Controller, oltre 25 profili utensile su bus CAN.
- **[URTC-FLASHER](https://github.com/JuanenRac/URTC-FLASHER)** — strumento desktop con GUI per il flashing delle schede URTC, CAN-OTA più SWD/JTAG a chip intero.
- **[URTC-TESTER](https://github.com/JuanenRac/URTC-TESTER)** — strumento desktop di diagnostica CAN-bus dal vivo per schede URTC, un pannello per profilo utensile.
- **[URTC-WEB-STUDIO](https://github.com/JuanenRac/URTC-WEB-STUDIO)** — alternativa basata su browser a URTC-TESTER tramite la Web Serial API, senza installazione locale.
- **[URTC-GATEWAY](https://github.com/JuanenRac/URTC-GATEWAY)** — gateway davanti al bus CAN di URTC: elenco di identificatori consentiti, limite di frequenza e chiave di sessione; software provato su computer, non ancora su un bus reale.

*Nodo IA Visione (Hailo-8)*
- **[HYDRA-UMC-VISION-NODE](https://github.com/JuanenRac/HYDRA-UMC-VISION-NODE)** — hub di integrazione per la pipeline di visione Hailo-8, con un vero controllo di prontezza hardware per fase.
- **[HYDRA-UMC-DETECTION-HEF](https://github.com/JuanenRac/HYDRA-UMC-DETECTION-HEF)** — registro reale di modelli compilati con verifica di caricamento sicuro per architettura Hailo/checksum.
- **[HYDRA-UMC-VISION-STREAMER](https://github.com/JuanenRac/HYDRA-UMC-VISION-STREAMER)** — generatore reale di pipeline GStreamer + config MediaMTX, con una vera barriera di integrazione HailoRT.
- **[HYDRA-UMC-VISUAL-SERVOING-API](https://github.com/JuanenRac/HYDRA-UMC-VISUAL-SERVOING-API)** — legge di correzione Position-Based Visual Servoing con autorizzazione condizionata allo stato di zona; ancora nessuna stima di posa da telecamera.
- **[HYDRA-UMC-SAFETY-ZONES](https://github.com/JuanenRac/HYDRA-UMC-SAFETY-ZONES)** — logica v0 di violazione zona, freschezza di calibrazione e richiesta E-STOP che legge le posizioni degli oggetti da un file; nessun rilevatore la alimenta e nessun E-STOP fisico è ancora collegato.

*Nodo IA Cognitivo (Hailo-10)*
- **[HYDRA-UMC-COGNITIVE-NODE](https://github.com/JuanenRac/HYDRA-UMC-COGNITIVE-NODE)** — hub di integrazione per la pipeline cognitiva Hailo-10 (orchestrazione LLM/VLA/voce).
- **[HYDRA-UMC-VLA-ENGINE](https://github.com/JuanenRac/HYDRA-UMC-VLA-ENGINE)** — vera codifica/decodifica di token d'azione e generazione di traiettoria per un modello Vision-Language-Action.
- **[HYDRA-UMC-VOICE-UI](https://github.com/JuanenRac/HYDRA-UMC-VOICE-UI)** — vero front-end vocale (VAD + parser di intenti) con un relay verso Watch limitato e soggetto a conferma.
- **[HYDRA-UMC-SEMANTIC-PLANNER](https://github.com/JuanenRac/HYDRA-UMC-SEMANTIC-PLANNER)** — vera scomposizione dei task basata su regole e recupero semantico degli errori sui codici errore MCU.
- **[HYDRA-UMC-DOCS-QA](https://github.com/JuanenRac/HYDRA-UMC-DOCS-QA)** — vera ricerca documentale TF-IDF (solo libreria standard) sui documenti Markdown di questo ecosistema.
- **[HYDRA-UMC-LOCAL-TECHNICIAN](https://github.com/JuanenRac/HYDRA-UMC-LOCAL-TECHNICIAN)** — tecnico di manutenzione IA locale e con cancelli di policy per l'ecosistema stesso - osserva, diagnostica e propone correzioni; i due livelli di rischio più alti non sono deliberatamente ancora implementati.

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
- **[HYDRA-UMC-OPS-AGENT](https://github.com/JuanenRac/HYDRA-UMC-OPS-AGENT)** — coordinatore di incidenti di manutenzione: un ruolo edge a basso privilegio raccoglie uno snapshot di inventario/salute sanificato, un ruolo control-plane lo rende in sola lettura e chiede a un provider di IA di suggerire una diagnosi - non applica mai una patch né distribuisce nulla.
- **[HYDRA-UMC-DEV-SERVER](https://github.com/JuanenRac/HYDRA-UMC-DEV-SERVER)** — host di sviluppo riproducibile (Raspberry Pi 5 / CM5) che conserva il codice sorgente dell'ecosistema ed esegue attività delimitate di build/test tramite una coda durevole; un ruolo di sviluppo dedicato, esplicitamente distinto da un CM5 operativo.

## 📚 Documentazione

Dove leggere di più:

* [docs/SOURCE_MAP.md](docs/SOURCE_MAP.md) - ogni file sorgente dell'app con una riga su ciò che fa
* **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — il contratto di trasporto Wi-Fi che questa app parla con `server.ts` (endpoint per endpoint), perché non esiste ancora una via Bluetooth, il vero meccanismo di discovery a due vie, e la relazione di questa app con il resto dell'ecosistema.
* [Base di sicurezza dell'ecosistema](https://github.com/JuanenRac/HYDRA-UMC-DOCS/blob/main/docs/SECURITY_BASELINE.md)
* [Modello delle minacce dell'ecosistema](https://github.com/JuanenRac/HYDRA-UMC-DOCS/blob/main/docs/THREAT_MODEL.md)
* [Registro delle modifiche di questo repository](CHANGELOG.md)
* [Licenza di questo repository](LICENSE.md)

## 🤝 Contribuire e comunità

* Prima di una pull request esegui `HYDRA_UMC_CI=1 py -3 tools/ci_validate.py` (oppure `HYDRA_UMC_CI=1 python3 tools/ci_validate.py`): deve stampare `CI_VALIDATION=PASS`. Non eseguire `build.sh` né `build.bat` per questa verifica; compilare non è verificare.
* I otto README sono scritti da un'unica fonte in HYDRA-UMC-DOCS; non modificarli a mano. Cambia la fonte e riscrivili con `tools/make_readmes.py`.
* Non affermare in un README ciò che non è stato eseguito: scrivi «simulato» o «non provato su hardware» quando è la verità.
* Vedi [CONTRIBUTING.md](CONTRIBUTING.md), il [codice di condotta](CODE_OF_CONDUCT.md), [SECURITY.md](SECURITY.md) e [SUPPORT.md](SUPPORT.md).

## 👤 AUTORE

**JuanenRac (Electro Hobby 3D)** · electrohobby3d@gmail.com

## 📜 LICENZA

GPL-3.0-or-later - [LICENSE](LICENSE).
