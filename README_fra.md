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
- **Découverte réseau** (`lib/network/discovery.dart`) - scan concurrent de `GET /api/hydra-info` sur le(s) sous-réseau(x) local(aux) réel(s) propre(s) de cet appareil, dérivé(s) du propre `NetworkInterface.list()` de `dart:io` plutôt que d'une seule supposition figée, puisque le LAN d'un téléphone a tout autant de chances d'être `192.168.0.x` ou `10.x.x.x` que `192.168.1.x`. Se rabat sur `192.168.1.x` seulement si l'énumération des interfaces elle-même revient vide.
- **Synchronisation des commandes atomiques** (le propre `_sendAtomicCommand()` de `lib/state/robot_view_model.dart`) - chaque écriture (enable/disable/play/pause/stop/jog/valve/pump/speed/vision) utilise le vrai point de terminaison `POST /api/robot/:id/command`, une petite charge utile ciblée plutôt que d'écraser tout l'arbre settings, avec une propagation correcte du robot combiné (`combinedWith`) pour les 5 commandes qui en ont besoin.
- **Synchronisation WebSocket en direct** (`lib/network/hydra_websocket.dart`) - joint toujours `?token=` à l'URL de connexion (le propre upgrade `/ws` de `server.ts` l'exige sans condition), gère à la fois les types de diffusion `"settings"` et `"delta"`, se reconnecte automatiquement en cas de coupure.
- **Tableau de bord** (`lib/ui/dashboard_screen.dart`) - cartes par robot, réactives en temps réel via le propre `ChangeNotifier` de `Provider`, convention de LED (vert clignotant = actif, rouge fixe = inactif) et affichage du robot combiné (affiché uniquement du côté suiveur, résolu par id) correspondant au propre Dashboard Overview de HYDRA-UMC-STUDIO.
- **Contrôle Manuel** (`lib/ui/control_screen.dart`, `lib/ui/widgets/joystick_pad.dart`) - D-pad de jog (avec/sans cible de table XY), curseurs de vitesse/accélération, interrupteurs vanne/pompe, et véritable protection par pression longue sur E-STOP/STOP (un appui rapide ne fait rien à part un retour haptique + visuel, seule une pression maintenue authentique envoie la commande).
- **Caméra** (`lib/ui/camera_screen.dart`, `lib/ui/widgets/mjpeg_view.dart`) - un petit analyseur de flux MJPEG écrit à la main (aucun paquet tiers), un état clair "Camera Disabled" au lieu d'un flux vide silencieux, et un interrupteur pour activer/désactiver le système de vision d'un robot directement depuis le serveur (la commande atomique `"vision"` propre de `server.ts`).
- **Vue 3D** (`lib/ui/three_d_screen.dart`) - intègre le propre viewport 3D en temps réel de HYDRA-UMC-STUDIO dans une WebView (`?hideUI=true&robotId=&token=`), la même approche que l'application Android, pour la même raison (obtient gratuitement la vraie scène 3D actuellement en production). Se rabat sur un placeholder honnête sur les plateformes que `webview_flutter` ne prend pas en charge (la cible de bureau Windows de ce dépôt, utilisée pour la vérification de build).
- **Métriques système** (`lib/state/robot_view_model.dart`) - `GET /api/system/metrics` interrogé toutes les 5s, la même cadence que les 2 autres clients, affiché dans le Dashboard.
- **Interface en 7 langues** (`lib/l10n/`, pipeline standard `flutter gen-l10n`) - anglais, espagnol, français, allemand, italien, japonais et chinois, comme le reste des clients de cet écosystème. Un réglage persistant dans `Réglages > Langue` utilise par défaut la langue du système ; `RobotViewModel.lastError` est un `HydraError` typé plutôt qu'un texte anglais déjà formaté, donc les messages d'erreur de la logique métier (échecs de connexion/commande) sont eux aussi correctement traduits, pas seulement le texte statique des écrans.

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
│   │   └── auth_prefs.dart          # Connexion et jeton persistes (shared_preferences)
│   ├── state/
│   │   └── robot_view_model.dart    # Unique ChangeNotifier ecoute par chaque ecran
│   └── ui/
│       ├── login_screen.dart        # Champs hote/port/utilisateur/mot de passe + "Scan local network"
│       ├── main_screen.dart         # Coquille de navigation inferieure (Dashboard/Control/Camera/3D/Settings)
│       ├── dashboard_screen.dart    # Cartes par robot + barre de metriques systeme
│       ├── control_screen.dart      # Controles jog/vitesse/vanne/pompe/lecture
│       ├── camera_screen.dart       # Visionneuse MJPEG + interrupteur vision on/off
│       ├── three_d_screen.dart      # Integre le propre viewport 3D de STUDIO via WebView
│       ├── settings_screen.dart     # Informations de connexion + deconnexion
│       └── widgets/
│           ├── joystick_pad.dart     # D-pad de jog (deliberement pas un stick analogique, voir l'en-tete du fichier)
│           ├── digital_readout.dart, status_led.dart
│           └── mjpeg_view.dart       # Analyseur de flux MJPEG ecrit a la main
├── ios/                              # Projet Xcode (compiler uniquement depuis macOS)
├── windows/                          # Cible de bureau Windows - verification de build sans un Mac
├── docs/ARCHITECTURE.md
├── test/widget_test.dart, websocket_uri_test.dart  # démarrage + encodage de jeton opaque
├── images/
├── README.md                         # ce fichier (anglais)
└── README_spa.md / README_ita.md / README_fra.md / README_deu.md / README_zho.md / README_jpn.md  # traductions
```

## 🔗 Projets Connexes

Ce projet fait partie d'un écosystème robotique plus large du même auteur (JuanenRac / Electro Hobby 3D), composé de nombreux projets. Cela vaut la peine de le connaître, car une demande pourrait en réalité concerner l'un de ceux-ci plutôt que ce dépôt.

**Directement liés à cette application**
- **[HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER)** — le backend contre lequel s'exécutent la connexion, les commandes atomiques et la synchronisation WebSocket de cette application.
- **[HYDRA-UMC-STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO)** — son viewport 3D en temps réel est intégré directement dans l'écran Vue 3D propre à cette application via WebView.
- **[HYDRA-UMC-SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE)** / **[HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL)** — clients frères parlant exactement le même contrat `REMOTE_API.md` que cette application.
- **[HYDRA-UMC-WATCH](https://github.com/JuanenRac/HYDRA-UMC-WATCH)** — l'app compagnon pour Apple Watch de cette application, pour un contrôle et un état en un coup d'œil depuis le poignet.
- **[HYDRA-UMC-HIL-BRIDGE](https://github.com/JuanenRac/HYDRA-UMC-HIL-BRIDGE)** — le pont qui permet de piloter à distance le jumeau numérique depuis cette application, en hardware-in-the-loop.

**Le reste de l'écosystème**

💠 *Écosystème Central*: [HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC) · [HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER) · [HYDRA-UMC-STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO) · [HYDRA-UMC-SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE) · [HYDRA-UMC-DSI](https://github.com/JuanenRac/HYDRA-UMC-DSI) · [HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL) · [HYDRA-UMC-EDITOR-URDF](https://github.com/JuanenRac/HYDRA-UMC-EDITOR-URDF) · [URTC](https://github.com/JuanenRac/URTC) · [URTC-FLASHER](https://github.com/JuanenRac/URTC-FLASHER) · [URTC-TESTER](https://github.com/JuanenRac/URTC-TESTER) · [URTC-WEB-STUDIO](https://github.com/JuanenRac/URTC-WEB-STUDIO)

👁️ *Nœud de Vision IA (Hailo-8)*: [HYDRA-UMC-VISION-NODE](https://github.com/JuanenRac/HYDRA-UMC-VISION-NODE) · [HYDRA-UMC-VISION-STREAMER](https://github.com/JuanenRac/HYDRA-UMC-VISION-STREAMER) · [HYDRA-UMC-DETECTION-HEF](https://github.com/JuanenRac/HYDRA-UMC-DETECTION-HEF) · [HYDRA-UMC-SAFETY-ZONES](https://github.com/JuanenRac/HYDRA-UMC-SAFETY-ZONES) · [HYDRA-UMC-VISUAL-SERVOING-API](https://github.com/JuanenRac/HYDRA-UMC-VISUAL-SERVOING-API)

🧠 *Nœud Cognitif IA (Hailo-10)*: [HYDRA-UMC-COGNITIVE-NODE](https://github.com/JuanenRac/HYDRA-UMC-COGNITIVE-NODE) · [HYDRA-UMC-VLA-ENGINE](https://github.com/JuanenRac/HYDRA-UMC-VLA-ENGINE) · [HYDRA-UMC-VOICE-UI](https://github.com/JuanenRac/HYDRA-UMC-VOICE-UI) · [HYDRA-UMC-SEMANTIC-PLANNER](https://github.com/JuanenRac/HYDRA-UMC-SEMANTIC-PLANNER) · [HYDRA-UMC-DOCS-QA](https://github.com/JuanenRac/HYDRA-UMC-DOCS-QA)

🐝 *Orchestration et Essaim*: [HYDRA-UMC-ORCHESTRATOR](https://github.com/JuanenRac/HYDRA-UMC-ORCHESTRATOR) · [HYDRA-UMC-SWARM-SYNC](https://github.com/JuanenRac/HYDRA-UMC-SWARM-SYNC) · [HYDRA-UMC-PATH-PLANNER-3D](https://github.com/JuanenRac/HYDRA-UMC-PATH-PLANNER-3D) · [HYDRA-UMC-JOB-DISPATCHER](https://github.com/JuanenRac/HYDRA-UMC-JOB-DISPATCHER) · [HYDRA-UMC-NODE-HEALING](https://github.com/JuanenRac/HYDRA-UMC-NODE-HEALING)

🎮 *Jumeau Numérique et Simulation*: [HYDRA-UMC-TWIN](https://github.com/JuanenRac/HYDRA-UMC-TWIN) · [HYDRA-UMC-PHYSICS-REPLICA](https://github.com/JuanenRac/HYDRA-UMC-PHYSICS-REPLICA) · [HYDRA-UMC-SYNTHETIC-DATA-GEN](https://github.com/JuanenRac/HYDRA-UMC-SYNTHETIC-DATA-GEN)

📊 *Données et Analytique*: [HYDRA-UMC-DATALAKE](https://github.com/JuanenRac/HYDRA-UMC-DATALAKE) · [HYDRA-UMC-TELEMETRY-COLLECTOR](https://github.com/JuanenRac/HYDRA-UMC-TELEMETRY-COLLECTOR) · [HYDRA-UMC-ANOMALY-DETECTOR](https://github.com/JuanenRac/HYDRA-UMC-ANOMALY-DETECTOR) · [HYDRA-UMC-PRODUCTION-REPORTS](https://github.com/JuanenRac/HYDRA-UMC-PRODUCTION-REPORTS)

🏭 *Passerelle Industrielle*: [HYDRA-UMC-GATEWAY-INDUSTRIAL](https://github.com/JuanenRac/HYDRA-UMC-GATEWAY-INDUSTRIAL) · [HYDRA-UMC-OPCUA-SERVER](https://github.com/JuanenRac/HYDRA-UMC-OPCUA-SERVER) · [HYDRA-UMC-MQTT-BROKER](https://github.com/JuanenRac/HYDRA-UMC-MQTT-BROKER) · [HYDRA-UMC-MTCONNECT-ADAPTER](https://github.com/JuanenRac/HYDRA-UMC-MTCONNECT-ADAPTER)

🛠️ *Outils Complémentaires*: [URTC-SMART-RACK](https://github.com/JuanenRac/URTC-SMART-RACK) · [URTC-VISION-TOOL](https://github.com/JuanenRac/URTC-VISION-TOOL) · [HYDRA-UMC-TOOL-CLI](https://github.com/JuanenRac/HYDRA-UMC-TOOL-CLI) · [HYDRA-UMC-DASHBOARD-AI](https://github.com/JuanenRac/HYDRA-UMC-DASHBOARD-AI)

---

## 👤 AUTEUR
**JuanenRac** (Electro Hobby 3D)
📧 electrohobby3d@gmail.com
📺 [youtube.com/@electrohobby3d](https://youtube.com/@electrohobby3d)

## 📜 LICENCE

GNU General Public License v3.0 (GPL-3.0) pour le code source - voir [`LICENSE`](LICENSE).

La documentation (ce README et ses propres traductions - `README_spa.md`, `README_ita.md`, `README_fra.md`, `README_deu.md`, `README_zho.md`, `README_jpn.md`) est disponible sous **Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)**. Texte complet sur https://creativecommons.org/licenses/by-sa/4.0/.
