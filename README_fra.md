<p align="center">
  <img src="images/HYDRA_UMC_BANNER.svg" alt="HYDRA-UMC-IOS-CONTROL banner" width="100%">
</p>

# 📱 HYDRA-UMC CONTROL (iOS)

<p align="center">
  <a href="README.md">🇺🇸 English</a> |
  <a href="README_spa.md">🇪🇸 Español</a> |
  🇫🇷 <b>Français</b> |
  <a href="README_ita.md">🇮🇹 Italiano</a> |
  <a href="README_deu.md">🇩🇪 Deutsch</a> |
  <a href="README_zho.md">🇨🇳 简体中文</a> |
  <a href="README_jpn.md">🇯🇵 日本語</a>
</p>


<p align="left">
  <img src="https://img.shields.io/badge/Licence-GPL%203.0-blue.svg" alt="GPL 3.0">
  <img src="https://img.shields.io/badge/Framework-Flutter-02569B.svg" alt="Flutter">
  <img src="https://img.shields.io/badge/Langage-Dart-0175C2.svg" alt="Dart">
  <img src="https://img.shields.io/badge/Plateforme-iOS-000000.svg" alt="iOS">
</p>


Une application Flutter (Dart) multiplateforme qui contrôle un robot de la plateforme [HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC) via Wi-Fi, en parlant exactement le même contrat [`REMOTE_API.md`](https://github.com/JuanenRac/HYDRA-UMC-SERVER/blob/main/docs/REMOTE_API.md) qu'utilisent [HYDRA-UMC SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE) et [HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL) - découverte, connexion, commandes atomiques par robot, et synchronisation WebSocket en direct avec une instance de [HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER) en cours d'exécution (le backend headless séparé du propre processus de HYDRA-UMC STUDIO - STUDIO est désormais un simple client frontend de ce serveur, comme cette app).

## 🔀 Pourquoi Flutter, et non Swift natif

Cette application cible iOS/iPadOS, mais elle est construite en **Flutter** plutôt qu'en Swift/SwiftUI : l'environnement de travail de ce dépôt est exclusivement Windows, et un projet Swift natif peut être *écrit* sous Windows mais jamais *compilé ou exécuté* là (Xcode et le SDK iOS sont exclusifs à macOS). La propre cible de bureau Windows de Flutter permet de construire, exécuter et tester réellement cette application sur cette machine - `flutter analyze` sans erreur, `flutter build windows` réussi, `flutter test` qui passe, et l'`.exe` compilé qui se lance et s'affiche sans erreur d'exécution - au lieu d'écrire des milliers de lignes de Swift à l'aveugle, sans aucun moyen d'en vérifier quoi que ce soit avant qu'un Mac ne soit disponible.

**Cela ne supprime pas la restriction propre d'Apple** - un vrai `.ipa` nécessite toujours Xcode sur un Mac (ou un runner CI macOS) pour être compilé et signé ; rien dans le choix du framework ne change cela. Ce que Flutter apporte, c'est la capacité de vérifier chaque autre ligne de la logique propre de cette application (réseau, état, UI) sur cette machine dès aujourd'hui, et de livrer plus tard une base de code identique vers iOS sans réécriture.

## 🏗️ Ce qui est implémenté

- **Connexion** (`lib/ui/login_screen.dart`, `lib/state/robot_view_model.dart`) - champs modifiables d'IP/port et d'identifiants opérateur plus `POST /api/login` ; aucun compte ni mot de passe n'est prérempli. Un serveur de production exige des identifiants d'amorçage explicitement configurés pour son premier administrateur ; des comptes "operator" supplémentaires à privilège inférieur peuvent être créés depuis Config > Users dans l'interface navigateur. Le jeton de session persiste via `shared_preferences`. Un bouton "Scan local network" (`lib/network/discovery.dart`) trouve les serveurs sans que l'utilisateur ait besoin de connaître l'IP.
- **Découverte réseau** (`lib/network/discovery.dart`) - deux voies indépendantes tournent en même temps depuis la feuille "Scan local network" : mDNS/Bonjour réel (`discoverMdns()`, interroge le service `_hydra._tcp.local` que publie `server.ts` via le paquet `multicast_dns` - cette app est la première des 3 clients distants de l'écosystème à l'ajouter) plus un scan concurrent en force brute de `GET /api/hydra-info` sur le(s) sous-réseau(x) local(aux) réel(s) propre(s) de cet appareil (`scanSubnets()`, dérivé(s) du propre `NetworkInterface.list()` de `dart:io` plutôt que d'une seule supposition figée, puisque le LAN d'un téléphone a tout autant de chances d'être `192.168.0.x` ou `10.x.x.x` que `192.168.1.x`, se rabattant sur `192.168.1.x` seulement si l'énumération des interfaces elle-même revient vide). Que mDNS échoue silencieusement sur un build iOS non habilité est attendu (l'habilitation Multicast Networking d'Apple n'est pas accordée par un simple `flutter build ios`) - le scan de sous-réseau continue de fonctionner indépendamment de toute façon.
- **Verrou biométrique** (`lib/network/biometric_helper.dart`, `lib/ui/biometric_gate_screen.dart`) - Face ID/Touch ID/Windows Hello via `package:local_auth`, un interrupteur optionnel dans `Settings` qui protège la restauration d'une session valide sauvegardée au démarrage (cette app ne stocke jamais de mot de passe en clair, seulement un jeton - adapté du design de reremplissage de mot de passe propre à HYDRA-UMC-ANDROID-CONTROL pour tenir compte de cette différence).
- **Synchronisation des commandes atomiques** (le propre `_sendAtomicCommand()` de `lib/state/robot_view_model.dart`) - chaque écriture (enable/disable/play/pause/stop/jog/valve/pump/speed/vision) utilise le vrai point de terminaison `POST /api/robot/:id/command`, une petite charge utile ciblée plutôt que d'écraser tout l'arbre settings, avec une propagation correcte du robot combiné (`combinedWith`) pour les 5 commandes qui en ont besoin.
- **Synchronisation WebSocket en direct** (`lib/network/hydra_websocket.dart`) - joint toujours `?token=` à l'URL de connexion (le propre upgrade `/ws` de `server.ts` l'exige sans condition), gère à la fois les types de diffusion `"settings"` et `"delta"`, se reconnecte automatiquement en cas de coupure.
- **Tableau de bord** (`lib/ui/dashboard_screen.dart`) - cartes par robot, réactives en temps réel via le propre `ChangeNotifier` de `Provider`, convention de LED (vert clignotant = actif, rouge fixe = inactif) et affichage du robot combiné (affiché uniquement du côté suiveur, résolu par id) correspondant au propre Dashboard Overview de HYDRA-UMC-STUDIO.
- **Contrôle Manuel** (`lib/ui/control_screen.dart`, `lib/ui/widgets/joystick_pad.dart`) - D-pad de jog (avec/sans cible de table XY), curseurs de vitesse/accélération, interrupteurs vanne/pompe, et véritable protection par pression longue sur E-STOP/STOP (un appui rapide ne fait rien à part un retour haptique + visuel, seule une pression maintenue authentique envoie la commande).
- **Caméra** (`lib/ui/camera_screen.dart`, `lib/ui/widgets/mjpeg_view.dart`) - un petit analyseur de flux MJPEG écrit à la main (aucun paquet tiers), un état clair "Camera Disabled" au lieu d'un flux vide silencieux, et un interrupteur pour activer/désactiver le système de vision d'un robot directement depuis le serveur (la commande atomique `"vision"` propre de `server.ts`).
- **Vue 3D** (`lib/ui/three_d_screen.dart`) - intègre le propre viewport 3D en temps réel de HYDRA-UMC-STUDIO dans une WebView (`?hideUI=true&robotId=&token=`), la même approche que l'application Android, pour la même raison (obtient gratuitement la vraie scène 3D actuellement en production). Se rabat sur un placeholder honnête sur les plateformes que `webview_flutter` ne prend pas en charge (la cible de bureau Windows de ce dépôt, utilisée pour la vérification de build).
- **Métriques système** (`lib/state/robot_view_model.dart`) - `GET /api/system/metrics` interrogé toutes les 5s, la même cadence que les 2 autres clients, affiché dans le Dashboard.
- **Interface en 7 langues** (`lib/l10n/`, pipeline standard `flutter gen-l10n`) - anglais, espagnol, français, allemand, italien, japonais et chinois, comme le reste des clients de cet écosystème. Un réglage persistant dans `Réglages > Langue` utilise par défaut la langue du système ; `RobotViewModel.lastError` est un `HydraError` typé plutôt qu'un texte anglais déjà formaté, donc les messages d'erreur de la logique métier (échecs de connexion/commande) sont eux aussi correctement traduits, pas seulement le texte statique des écrans.
- **Cache d'état hors ligne** (`lib/network/state_cache.dart`) - le dernier arbre de réglages connu est persisté sur disque (avec un debounce de 1s), afin que les écrans Dashboard/Contrôle affichent des données réelles, même potentiellement obsolètes, dès le lancement plutôt qu'un état vide pendant que le vrai `connect()` est encore en cours. Remplacé par les données réelles dès que la connexion réussit.
- **Télémétrie** (`lib/ui/telemetry_screen.dart`) - un journal de type terminal, le plus récent en premier, des événements réels de connexion/connexion utilisateur/commande, plafonné à 50 entrées, avec une action pour l'effacer - la même convention « vert Matrix » que l'onglet Télémétrie de HYDRA-UMC-ANDROID-CONTROL.

## 🚀 Compilation

Nécessite le [Flutter SDK](https://docs.flutter.dev/get-started/install) (canal stable). Ce dépôt est compilé/vérifié avec Flutter 3.47.0. Seules `windows/` et `ios/` sont configurées comme plateformes dans ce dépôt (pas de dossiers `android/`, `linux/`, `web/`, ou `macos/`) - Windows existe pour que la logique propre de cette application puisse être compilée et exécutée sans un Mac ; iOS est la véritable cible.

### Scripts de build

```bash
./build.sh     # Git Bash / WSL - flutter pub get + bump de version + flutter build windows
build.bat      # cmd.exe / PowerShell - flutter pub get + bump de version + flutter build windows
```

Les deux produisent `build/windows/x64/runner/Release/hydra_umc_control.exe`, et les deux incrémentent d'abord la version de l'app - voir [Versionnage](#-versionnage) ci-dessous.

### Build manuel

```bash
flutter pub get
flutter analyze          # analyse statique - aucun compilateur necessaire
flutter test             # tests de widgets
dart run tool/bump_version.dart  # incremente la version, comme le font build.sh/build.bat
flutter build windows    # produit build/windows/x64/runner/Release/hydra_umc_control.exe
flutter run -d windows   # ou -d <ios-device-id> depuis un Mac, ou -d chrome pour un apercu web rapide
```

**Compiler le vrai `.ipa` iOS** nécessite Xcode sous macOS - depuis cette machine : `flutter build ipa` (ou ouvrir directement `ios/Runner.xcworkspace` dans Xcode). Cela ne peut pas être fait depuis Windows ; voir "Pourquoi Flutter, et non Swift natif" ci-dessus.

## 🔢 Versionnage

Ce dépôt suit une politique à l'échelle de l'écosystème : la version
s'incrémente automatiquement à **chaque build réel**, sans modifier
manuellement la ligne `version:` de `pubspec.yaml`. `build.sh`/`build.bat`
exécutent `tool/bump_version.dart` avant d'invoquer `flutter build`, en
appliquant :

- **Patch, façon compteur kilométrique (base 10) :** +1 à chaque build ;
  une fois 9 dépassé, il repasse à 0 et minor gagne +1 - ex. `0.0.9` ->
  `0.1.0`. Major n'est jamais modifié automatiquement.
- **Build number** (la partie après `+`) : un simple compteur
  monotone, +1 à chaque build, sans report.

Le même script régénère `lib/app_version.dart` (généré, non modifié à
la main - un simple fichier `const`, pas une nouvelle dépendance
d'exécution comme `package_info_plus`), que l'app lit en temps réel
pour afficher sa propre version sur l'écran **Paramètres**. Voir
[CHANGELOG.md](CHANGELOG.md) pour l'historique des versions.

## 📂 Structure du Dépôt

```text
HYDRA-UMC-IOS-CONTROL/
├── build.bat, build.sh              # flutter pub get + bump de version + flutter build windows
├── tool/
│   └── bump_version.dart            # Script de bump de version, execute par build.bat/build.sh avant chaque build (voir Versionnage ci-dessus)
├── lib/
│   ├── main.dart                    # Point d'entree de l'application, ChangeNotifierProvider + porte de connexion
│   ├── app_version.dart             # GENERE - regenere par tool/bump_version.dart, ne pas modifier a la main
│   ├── models/
│   │   ├── server_info.dart         # Entree de decouverte/connexion - reflete ServerInfo dans les 2 autres clients
│   │   └── hydra_state.dart         # RobotView/ControllerView/HydraState - vues mutables legeres sur l'arbre brut de settings.json
│   ├── network/
│   │   ├── hydra_api_client.dart    # REST : connexion, settings, commande atomique de robot, metriques systeme
│   │   ├── hydra_websocket.dart     # Client de synchronisation en direct via /ws
│   │   ├── discovery.dart           # Scan concurrent du/des sous-reseau(x) local(aux) reel(s) propre(s) de cet appareil contre GET /api/hydra-info
│   │   ├── auth_prefs.dart          # Connexion et jeton persistes (shared_preferences)
│   │   ├── biometric_helper.dart    # Fine enveloppe autour de package:local_auth (porte Face ID/Touch ID)
│   │   └── state_cache.dart         # Porte depuis le StateCache.kt d'Android - dernier état valide connu, persisté entre les lancements
│   ├── state/
│   │   ├── robot_view_model.dart    # Unique ChangeNotifier ecoute par chaque ecran
│   │   └── hydra_error.dart         # Surface d'erreur typée pour RobotViewModel (sans BuildContext propre)
│   ├── l10n/                        # Vraies localisations générées (7 langues) - voir l10n.yaml à la racine du dépôt
│   │   ├── app_localizations.dart   # Classe de base générée
│   │   ├── app_localizations_en.dart, _es.dart, _it.dart, _fr.dart, _de.dart, _ja.dart, _zh.dart
│   │   └── language_prefs.dart      # Préférence de langue persistée (shared_preferences)
│   └── ui/
│       ├── login_screen.dart        # Champs hote/port/utilisateur/mot de passe + "Scan local network"
│       ├── biometric_gate_screen.dart # Affiché par le _RootGate de main.dart pendant que Face ID/Touch ID est en attente
│       ├── main_screen.dart         # Coquille de navigation inferieure (Dashboard/Control/Camera/3D/Settings)
│       ├── dashboard_screen.dart    # Cartes par robot + barre de metriques systeme
│       ├── control_screen.dart      # Controles jog/vitesse/vanne/pompe/lecture
│       ├── camera_screen.dart       # Visionneuse MJPEG + interrupteur vision on/off
│       ├── three_d_screen.dart      # Integre le propre viewport 3D de STUDIO via WebView
│       ├── telemetry_screen.dart    # Porté depuis le TelemetryScreen.kt d'Android
│       ├── settings_screen.dart     # Informations de connexion + deconnexion
│       └── widgets/
│           ├── joystick_pad.dart     # D-pad de jog (deliberement pas un stick analogique, voir l'en-tete du fichier)
│           ├── digital_readout.dart, status_led.dart
│           └── mjpeg_view.dart       # Analyseur de flux MJPEG ecrit a la main
├── ios/                              # Projet Xcode (compiler uniquement depuis macOS)
├── windows/                          # Cible de bureau Windows - verification de build sans un Mac
├── docs/ARCHITECTURE.md
├── test/                             # widget_test, websocket_uri_test, format_uptime_test, localization_test, state_cache_test, telemetry_log_test
├── images/
├── README.md                         # ce fichier (anglais)
└── README_spa.md / README_ita.md / README_fra.md / README_deu.md / README_zho.md / README_jpn.md  # traductions
```

## 🔗 Projets Connexes

Ce projet fait partie de l'écosystème robotique HYDRA-UMC du même auteur (JuanenRac / Electro Hobby 3D). Bon à savoir, car une demande pourrait en réalité concerner l'un de ceux-ci plutôt que ce dépôt.

**Projet Parent**
- **[HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER)** — le vrai backend headless (REST/WebSocket) auquel parle réellement chaque client de contrôle ; le backend contre lequel s'exécutent la connexion, les commandes atomiques et la synchronisation WebSocket propres à cette application.

**Projets Frères** — parlent également à la propre API de HYDRA-UMC-SERVER, chacun en tant que son propre client
- **[HYDRA-UMC-STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO)** — tableau de bord de contrôle web avec visualisation 3D multi-robot en temps réel ; son propre visualiseur 3D est intégré directement dans l'écran Vue 3D de cette application via WebView.
- **[HYDRA-UMC-SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE)** — centre de commande d'essaim de bureau (PySide6) pour plusieurs serveurs à la fois, empaqueté en exécutable autonome ; parle exactement le même contrat `REMOTE_API.md` que cette application.
- **[HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL)** — application de contrôle Android native avec connexion biométrique et un compagnon Wear OS jumelé ; parle exactement le même contrat `REMOTE_API.md` que cette application.
- **[HYDRA-UMC-DSI](https://github.com/JuanenRac/HYDRA-UMC-DSI)** — interface tactile native pour l'écran tactile DSI 7" embarqué, intégrée directement sur le CM5.
- **[HYDRA-UMC-BRIDGE-AMR](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-AMR)** — frontière de coordination pour les flottes AGV/AMR via un éditeur MQTT VDA 5050 réel.
- **[HYDRA-UMC-BRIDGE-CNC](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-CNC)** — coordinateur haut niveau pour cellules CNC avec accès réel au statut/octets de contrôle GRBL.
- **[HYDRA-UMC-BRIDGE-DROIDS](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-DROIDS)** — frontière de coordination pour droïdes à pattes/humanoïdes, avec un véritable émetteur de commandes Boston Dynamics Spot.
- **[HYDRA-UMC-BRIDGE-LASER](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-LASER)** — coordinateur de sécurité pour cellules laser lisant 3 vraies sécurités GPIO de clé/enceinte/verrouillage.
- **[HYDRA-UMC-BRIDGE-OPENPNP](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-OPENPNP)** — coordinateur haut niveau sûr pour le flux de cartes du pick-and-place OpenPnP.
- **[HYDRA-UMC-BRIDGE-PRINTER3D](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-PRINTER3D)** — frontière de coordination sûre pour imprimantes 3D Moonraker/Klipper, avec de vraies commandes de tâche contrôlées.
- **[HYDRA-UMC-BRIDGE-ROS2](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-ROS2)** — coordinateur de sécurité avec un vrai transport ROS 2 rclpy à importation paresseuse.
- **[HYDRA-UMC-BRIDGE-UAV](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-UAV)** — frontière de coordination pour UAV équipés de caméra, avec un véritable émetteur de commandes MAVLink.

**Directement Liés**
- **[HYDRA-UMC-WATCH](https://github.com/JuanenRac/HYDRA-UMC-WATCH)** — application compagnon WearOS avec de vraies alertes haptiques et un relais vocal vers le téléphone jumelé ; la compagne Apple Watch de cette application, pour le contrôle et le statut en un coup d'œil depuis le poignet.
- **[HYDRA-UMC-HIL-BRIDGE](https://github.com/JuanenRac/HYDRA-UMC-HIL-BRIDGE)** — vrai verrouillage de sécurité hardware-in-the-loop routant les commandes entre simulation et matériel réel ; le pont qui permet à cette application de contrôler à distance le jumeau numérique, hardware-in-the-loop.

**Fait Également Partie de l'Écosystème**

*Matériel & Plateforme de Base*
- **[HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC)** — la carte mère physique du bras robotique : hôte CM5 + coprocesseur STM32H745 double cœur, coordonnant jusqu'à 8 bras-outils via CAN-OTA/SPI-OTA.
- **[HYDRA-UMC-OS](https://github.com/JuanenRac/HYDRA-UMC-OS)** — couche produit reproductible sur Raspberry Pi OS pour le CM5 : agent en lecture seule, config/profils validés, provisionnement WiFi de premier contact.
- **[HYDRA-UMC-SDK](https://github.com/JuanenRac/HYDRA-UMC-SDK)** — le contrat JSON-Schema partagé et la barrière de sécurité contre laquelle chaque bridge valide ses commandes.

*Backend Central & Clients*
- **[HYDRA-UMC-EDITOR-URDF](https://github.com/JuanenRac/HYDRA-UMC-EDITOR-URDF)** — créateur/éditeur graphique de bureau pour URDF qui envoie les modèles terminés vers le propre catalogue de STUDIO.

*Plateforme d'Outils URTC*
- **[URTC](https://github.com/JuanenRac/URTC)** — firmware pour la carte physique Universal Robot Tool Controller, plus de 25 profils d'outil sur bus CAN.
- **[URTC-FLASHER](https://github.com/JuanenRac/URTC-FLASHER)** — outil de bureau à interface graphique pour flasher les cartes URTC, CAN-OTA plus SWD/JTAG puce complète.
- **[URTC-TESTER](https://github.com/JuanenRac/URTC-TESTER)** — outil de bureau de diagnostic CAN-bus en direct pour cartes URTC, un panneau par profil d'outil.
- **[URTC-WEB-STUDIO](https://github.com/JuanenRac/URTC-WEB-STUDIO)** — alternative basée navigateur à URTC-TESTER via la Web Serial API, sans installation locale.

*Nœud IA de Vision (Hailo-8)*
- **[HYDRA-UMC-VISION-NODE](https://github.com/JuanenRac/HYDRA-UMC-VISION-NODE)** — hub d'intégration pour le pipeline de vision Hailo-8, avec une vraie vérification de disponibilité matérielle par étape.
- **[HYDRA-UMC-DETECTION-HEF](https://github.com/JuanenRac/HYDRA-UMC-DETECTION-HEF)** — registre réel de modèles compilés avec vérification de chargement sécurisé par architecture Hailo/checksum.
- **[HYDRA-UMC-VISION-STREAMER](https://github.com/JuanenRac/HYDRA-UMC-VISION-STREAMER)** — générateur réel de pipeline GStreamer + config MediaMTX, avec une vraie frontière d'intégration HailoRT.
- **[HYDRA-UMC-VISUAL-SERVOING-API](https://github.com/JuanenRac/HYDRA-UMC-VISUAL-SERVOING-API)** — vraie loi de correction Position-Based Visual Servoing, verrouillée sur l'état de zone en amont.
- **[HYDRA-UMC-SAFETY-ZONES](https://github.com/JuanenRac/HYDRA-UMC-SAFETY-ZONES)** — vraie vérification de violation de zone et demande d'E-STOP, avec application de la fraîcheur de calibration.

*Nœud IA Cognitif (Hailo-10)*
- **[HYDRA-UMC-COGNITIVE-NODE](https://github.com/JuanenRac/HYDRA-UMC-COGNITIVE-NODE)** — hub d'intégration pour le pipeline cognitif Hailo-10 (orchestration LLM/VLA/voix).
- **[HYDRA-UMC-VLA-ENGINE](https://github.com/JuanenRac/HYDRA-UMC-VLA-ENGINE)** — vrai encodage/décodage de jetons d'action et génération de trajectoire pour un modèle Vision-Language-Action.
- **[HYDRA-UMC-VOICE-UI](https://github.com/JuanenRac/HYDRA-UMC-VOICE-UI)** — vrai front-end vocal (VAD + analyseur d'intention) avec un relais Watch borné et soumis à confirmation.
- **[HYDRA-UMC-SEMANTIC-PLANNER](https://github.com/JuanenRac/HYDRA-UMC-SEMANTIC-PLANNER)** — vraie décomposition de tâches basée sur des règles et récupération sémantique d'erreurs sur les codes d'erreur MCU.
- **[HYDRA-UMC-DOCS-QA](https://github.com/JuanenRac/HYDRA-UMC-DOCS-QA)** — vraie recherche documentaire TF-IDF (bibliothèque standard uniquement) sur les propres documents Markdown de cet écosystème.

*Orchestration & Essaim*
- **[HYDRA-UMC-ORCHESTRATOR](https://github.com/JuanenRac/HYDRA-UMC-ORCHESTRATOR)** — hub d'intégration avec un vrai contrat de rapport de santé gRPC/Protobuf et une machine à états de mission.
- **[HYDRA-UMC-JOB-DISPATCHER](https://github.com/JuanenRac/HYDRA-UMC-JOB-DISPATCHER)** — vraie file de tâches basée sur la priorité avec déduplication, via une vraie API HTTP.
- **[HYDRA-UMC-NODE-HEALING](https://github.com/JuanenRac/HYDRA-UMC-NODE-HEALING)** — vrai chien de garde de santé de flotte basé sur gRPC, avec retry/backoff et détection d'incohérence d'identité.
- **[HYDRA-UMC-PATH-PLANNER-3D](https://github.com/JuanenRac/HYDRA-UMC-PATH-PLANNER-3D)** — vrai planificateur de trajectoire 3D basé sur RRT, avec vraie validation des collisions obstacle/espace de travail.
- **[HYDRA-UMC-SWARM-SYNC](https://github.com/JuanenRac/HYDRA-UMC-SWARM-SYNC)** — vraie synchronisation d'état CRDT LWW-Element-Map, testée par propriétés pour la convergence multi-cellule.

*Jumeau Numérique & Simulation*
- **[HYDRA-UMC-TWIN](https://github.com/JuanenRac/HYDRA-UMC-TWIN)** — hub d'intégration pour le moteur de jumeau numérique, avec un vrai contrat de synchronisation par compatibilité de version.
- **[HYDRA-UMC-PHYSICS-REPLICA](https://github.com/JuanenRac/HYDRA-UMC-PHYSICS-REPLICA)** — vraie cinématique directe et validation des limites articulaires sur un vrai sous-ensemble URDF.
- **[HYDRA-UMC-SYNTHETIC-DATA-GEN](https://github.com/JuanenRac/HYDRA-UMC-SYNTHETIC-DATA-GEN)** — vrai générateur procédural de scènes 2D avec export d'annotations YOLO/COCO.

*Données & Analytique*
- **[HYDRA-UMC-DATALAKE](https://github.com/JuanenRac/HYDRA-UMC-DATALAKE)** — vrai magasin de séries temporelles basé sur sqlite3, avec une vraie API HTTP d'ingestion/requête.
- **[HYDRA-UMC-ANOMALY-DETECTOR](https://github.com/JuanenRac/HYDRA-UMC-ANOMALY-DETECTOR)** — vrai détecteur d'anomalies FFT + ligne de base statistique, avec surveillance de dérive.
- **[HYDRA-UMC-PRODUCTION-REPORTS](https://github.com/JuanenRac/HYDRA-UMC-PRODUCTION-REPORTS)** — vrai calcul OEE/disponibilité sur l'historique de DATALAKE, avec export CSV reproductible.
- **[HYDRA-UMC-TELEMETRY-COLLECTOR](https://github.com/JuanenRac/HYDRA-UMC-TELEMETRY-COLLECTOR)** — vrai pipeline d'ingestion CAN/WebSocket vers DATALAKE, avec déduplication par séquence.

*Passerelle Industrielle*
- **[HYDRA-UMC-GATEWAY-INDUSTRIAL](https://github.com/JuanenRac/HYDRA-UMC-GATEWAY-INDUSTRIAL)** — hub d'intégration relayant vers les protocoles industriels, avec une vraie couche de liste blanche de commandes/contre-pression.
- **[HYDRA-UMC-OPCUA-SERVER](https://github.com/JuanenRac/HYDRA-UMC-OPCUA-SERVER)** — vrai espace d'adressage OPC-UA, vérifié avec une vraie session client du protocole binaire.
- **[HYDRA-UMC-MQTT-BROKER](https://github.com/JuanenRac/HYDRA-UMC-MQTT-BROKER)** — vrai broker MQTT avec authentification par client optionnelle et ACL de sujets.
- **[HYDRA-UMC-MTCONNECT-ADAPTER](https://github.com/JuanenRac/HYDRA-UMC-MTCONNECT-ADAPTER)** — vrais points de terminaison XML MTConnect `/probe` et `/current`, avec sortie en mode dégradé.

*Outils Complémentaires & Opérations de l'Écosystème*
- **[HYDRA-UMC-DASHBOARD-AI](https://github.com/JuanenRac/HYDRA-UMC-DASHBOARD-AI)** — panneaux Smart Summaries et Anomaly Highlighting sur DATALAKE/ANOMALY-DETECTOR, avec un repli statistique honnête.
- **[HYDRA-UMC-TOOL-CLI](https://github.com/JuanenRac/HYDRA-UMC-TOOL-CLI)** — CLI de flotte avec un vrai contrat de codes de sortie stable, un vrai client en direct de la propre API de HYDRA-UMC-SERVER.
- **[URTC-SMART-RACK](https://github.com/JuanenRac/URTC-SMART-RACK)** — firmware pour un rack de montage de cartes avec décodage réel d'ID d'outil et logique de préchauffage Smart Idle.
- **[URTC-VISION-TOOL](https://github.com/JuanenRac/URTC-VISION-TOOL)** — firmware plus un vrai compagnon de vision Python pour une tête d'outil d'inspection thermique/RGB.
- **[HYDRA-UMC-UPDATER](https://github.com/JuanenRac/HYDRA-UMC-UPDATER)** — outil administratif de bureau qui découvre, clone et met à jour chaque dépôt de cet écosystème.

---

## 📚 Documentation & Communauté

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — le contrat de transport Wi-Fi que cette app parle avec `server.ts` (endpoint par endpoint), pourquoi il n'y a toujours aucune voie Bluetooth, le vrai mécanisme de découverte à deux voies, et la relation de cette app avec le reste de l'écosystème.
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — pile technologique et lignes directrices de codage pour une pull request.
- **[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)** — les normes de comportement attendues dans cette communauté.
- **[SECURITY.md](SECURITY.md)** — comment signaler une vulnérabilité, et les véritables axes de sécurité de ce projet.
- **[SUPPORT.md](SUPPORT.md)** — où poser des questions et signaler des bugs.
- **[LICENSE.md](LICENSE.md)** — la licence propre de ce projet.

## 👤 AUTEUR
**JuanenRac** (Electro Hobby 3D)
📧 electrohobby3d@gmail.com
📺 [youtube.com/@electrohobby3d](https://youtube.com/@electrohobby3d)

## 📜 LICENCE

GNU General Public License v3.0 (GPL-3.0) pour le code source - voir [`LICENSE`](LICENSE).

La documentation (ce README et ses propres traductions - `README_spa.md`, `README_ita.md`, `README_fra.md`, `README_deu.md`, `README_zho.md`, `README_jpn.md`) est disponible sous **Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)**. Texte complet sur https://creativecommons.org/licenses/by-sa/4.0/.
