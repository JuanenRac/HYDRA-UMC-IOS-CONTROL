<!-- =============================================================================
HYDRA-UMC-IOS-CONTROL - iOS and iPadOS operator console for a HYDRA-UMC server, written in Flutter
Copyright (C) JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
GPL-3.0-or-later - see LICENSE
============================================================================= -->

<p align="center">
  <img src="images/HYDRA_UMC_BANNER.svg" alt="HYDRA-UMC-IOS-CONTROL banner" width="100%">
</p>

# 🍎 HYDRA-UMC-IOS-CONTROL

<p align="center"><a href="README.md">🇺🇸 English</a> | <a href="README_spa.md">🇪🇸 Español</a> | 🇫🇷 <b>Français</b> | <a href="README_ita.md">🇮🇹 Italiano</a> | <a href="README_deu.md">🇩🇪 Deutsch</a> | <a href="README_zho.md">🇨🇳 简体中文</a> | <a href="README_jpn.md">🇯🇵 日本語</a> | <a href="README_por.md">🇵🇹 Português</a></p>

### Vos robots HYDRA-UMC sur un iPhone ou un iPad : trouvez le serveur, déplacez et surveillez les robots, et arrêtez tout avec un bouton rouge.

<p align="center">
  <img src="https://img.shields.io/badge/License-GPL%203.0--or--later-blue.svg" alt="GPL 3.0 or later">
  <img src="https://img.shields.io/badge/Framework-Flutter-02569B.svg" alt="Framework">
  <img src="https://img.shields.io/badge/Language-Dart-0175C2.svg" alt="Language">
  <img src="https://img.shields.io/badge/Platform-iOS-000000.svg" alt="Platform">
  <img src="https://img.shields.io/badge/Tests-254%20passing-2ea44f.svg" alt="Tests">
  <img src="https://img.shields.io/badge/Version-0.2.8-0f6cbd.svg" alt="Version">
  <img src="https://img.shields.io/badge/Maturity-functional-0F6CBD.svg" alt="Maturity">
</p>

---

Une application Flutter (Dart) multiplateforme qui contrôle un robot de la plateforme [HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC) via Wi-Fi, en parlant exactement le même contrat [`REMOTE_API.md`](https://github.com/JuanenRac/HYDRA-UMC-SERVER/blob/main/docs/REMOTE_API.md) qu'utilisent [HYDRA-UMC SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE) et [HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL) - découverte, connexion, commandes atomiques par robot, et synchronisation WebSocket en direct avec une instance de [HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER) en cours d'exécution (le backend headless séparé du propre processus de HYDRA-UMC STUDIO - STUDIO est désormais un simple client frontend de ce serveur, comme cette app).

> **État de la sûreté et de la cybersécurité :** cet écosystème n'est pas un système de sécurité certifié. Il n'existe pas encore de chaîne d'E-STOP matérielle, ni de limites ou de verrouillages imposés par le firmware, ni de commande de mouvement vérifiée ; les images de firmware sont contrôlées par CRC-32 et une signature Ed25519, et une compilation de version refuse les clés de développement publiées (les têtes d'outil et les cartes d'extension derrière le relais utilisent encore les chargeurs d'URTC, qui prennent un HMAC-SHA256 à clé partagée au lieu d'une signature) ; TLS et TLS mutuel sont optionnels et désactivés par défaut ; aucune carte propre n'a encore été assemblée ni testée. Lisez la [base de sécurité](https://github.com/JuanenRac/HYDRA-UMC-DOCS/blob/main/docs/SECURITY_BASELINE.md) et le [modèle de menaces](https://github.com/JuanenRac/HYDRA-UMC-DOCS/blob/main/docs/THREAT_MODEL.md) avant de vous fier à une affirmation d'ici pour la sécurité d'une personne.

---

## 📋 En un coup d'œil

| | |
|---|---|
| Version | `0.2.8` |
| Maturité | Fonctionnel |
| Tests | 254 (`flutter test`) |
| Technologie | Flutter 3.x / Dart |
| Cible | Un iPhone ou un iPad |
| Sur matériel réel | Pas encore : aucune exécution sur du matériel réel n'est consignée pour cette version |

**Aller à :** [Présentation](#-présentation) · [Architecture](#-architecture) · [Fonctionnalités](#-fonctionnalités) · [Sécurité et protection](#-sécurité-et-protection) · [Interfaces](#-interfaces) · [Configuration](#-configuration) · [Démarrage rapide](#-démarrage-rapide) · [Tests](#-tests) · [Dépannage](#-dépannage) · [Structure du dépôt](#-structure-du-dépôt) · [Projets liés](#-projets-liés)

## 🚦 État du projet

Chaque ligne est une partie de ce dépôt et le feu dit où elle en est aujourd'hui. Elle est écrite d'après ce que le dépôt peut montrer (tests, compilations, exécutions), pas d'après ce qui est prévu.

🟢 Fait et vérifié · 🟡 Fonctionne, avec des limites connues · 🟠 À moitié fait ou pas encore vérifié · 🔴 Pas fait ou ne fonctionne pas

| Domaine | État | Ce que cela veut dire ici |
|---|---|---|
| Logiciel | 🟡 | Fonctionne pour son usage principal ; la vérification d'honnêteté ci-dessus liste ce qui manque encore |
| Tests | 🟢 | 254 tests automatiques, exécutés à chaque modification |
| Matériel réel | 🔴 | Pas encore : aucune exécution sur du matériel réel n'est consignée pour cette version |
| Documentation | 🟢 | README en huit langues, vérifié par rapport au manifeste à chaque modification |

## 🎯 Présentation

Écrans de l'application : **connexion** (adresse du serveur, compte, un balayage du réseau local), **tableau de bord** (une carte par robot avec sa LED en direct et la santé du module de calcul), **contrôle** (croix de déplacement, vitesse, vannes et pompes, réservation du robot, PLAY avec une question facultative avant), **caméra** (MJPEG en direct), **vue 3D** (la vraie scène de STUDIO), **télémétrie** (un journal de type terminal) et **réglages** (langue, verrou biométrique, interrupteurs). Un bouton rouge **ARRÊT** figure dans la barre de chaque onglet.

## 🧩 Rôle dans HYDRA-UMC

**HYDRA-UMC-IOS-CONTROL** est la console d'opérateur de HYDRA-UMC pour iPhone et iPad. Elle est écrite en Flutter pour que sa logique puisse être compilée, exécutée et testée sous Windows ; la compilation iOS elle-même demande toujours Xcode sur un Mac. Elle trouve un HYDRA-UMC-SERVER sur le réseau local, se connecte, affiche et déplace les robots, surveille leurs caméras et une vue 3D, et arrête tout d'une pression, avec le même contrat distant que la SUITE et l'application Android. Ce n'est pas un dispositif de sécurité.

## 🏛️ Architecture

<p align="center">
  <img src="images/architecture.svg" alt="HYDRA-UMC-IOS-CONTROL architecture" width="100%">
</p>

### Pourquoi Flutter, et non Swift natif

Cette application cible iOS/iPadOS, mais elle est construite en **Flutter** plutôt qu'en Swift/SwiftUI : l'environnement de travail de ce dépôt est exclusivement Windows, et un projet Swift natif peut être *écrit* sous Windows mais jamais *compilé ou exécuté* là (Xcode et le SDK iOS sont exclusifs à macOS). La propre cible de bureau Windows de Flutter permet de construire, exécuter et tester réellement cette application sur cette machine - `flutter analyze` sans erreur, `flutter build windows` réussi, `flutter test` qui passe, et l'`.exe` compilé qui se lance et s'affiche sans erreur d'exécution - au lieu d'écrire des milliers de lignes de Swift à l'aveugle, sans aucun moyen d'en vérifier quoi que ce soit avant qu'un Mac ne soit disponible.

**Cela ne supprime pas la restriction propre d'Apple** - un vrai `.ipa` nécessite toujours Xcode sur un Mac (ou un runner CI macOS) pour être compilé et signé ; rien dans le choix du framework ne change cela. Ce que Flutter apporte, c'est la capacité de vérifier chaque autre ligne de la logique propre de cette application (réseau, état, UI) sur cette machine dès aujourd'hui, et de livrer plus tard une base de code identique vers iOS sans réécriture.

## ✨ Fonctionnalités

- **Connexion** (`lib/ui/login_screen.dart`, `lib/state/robot_view_model.dart`) - champs modifiables d'IP/port et d'identifiants opérateur plus `POST /api/login` ; aucun compte ni mot de passe n'est prérempli. Un serveur de production exige des identifiants d'amorçage explicitement configurés pour son premier administrateur ; des comptes "operator" supplémentaires à privilège inférieur peuvent être créés depuis Config > Users dans l'interface navigateur. Le jeton de session persiste dans le trousseau iOS (`flutter_secure_storage`) ; l'hôte et le port sont gardés avec `shared_preferences`. Un bouton "Scan local network" (`lib/network/discovery.dart`) trouve les serveurs sans que l'utilisateur ait besoin de connaître l'IP.
- **Découverte réseau** (`lib/network/discovery.dart`) - deux voies indépendantes tournent en même temps depuis la feuille "Scan local network" : mDNS/Bonjour réel (`discoverMdns()`, interroge le service `_hydra._tcp.local` que publie `server.ts` via le paquet `multicast_dns` - cette app est la première des 3 clients distants de l'écosystème à l'ajouter) plus un scan concurrent en force brute de `GET /api/hydra-info` sur le(s) sous-réseau(x) local(aux) réel(s) propre(s) de cet appareil (`scanSubnets()`, dérivé(s) du propre `NetworkInterface.list()` de `dart:io` plutôt que d'une seule supposition figée, puisque le LAN d'un téléphone a tout autant de chances d'être `192.168.0.x` ou `10.x.x.x` que `192.168.1.x`, se rabattant sur `192.168.1.x` seulement si l'énumération des interfaces elle-même revient vide). Que mDNS échoue silencieusement sur un build iOS non habilité est attendu (l'habilitation Multicast Networking d'Apple n'est pas accordée par un simple `flutter build ios`) - le scan de sous-réseau continue de fonctionner indépendamment de toute façon.
- **Verrou biométrique** (`lib/network/biometric_helper.dart`, `lib/ui/biometric_gate_screen.dart`) - Face ID/Touch ID/Windows Hello via `package:local_auth`, un interrupteur optionnel dans `Settings` qui protège la restauration d'une session valide sauvegardée au démarrage (cette app ne stocke jamais de mot de passe en clair, seulement un jeton - adapté du design de reremplissage de mot de passe propre à HYDRA-UMC-ANDROID-CONTROL pour tenir compte de cette différence).
- **Synchronisation des commandes atomiques** (le propre `_sendAtomicCommand()` de `lib/state/robot_view_model.dart`) - chaque écriture (play/pause/stop/jog/valve/pump/speed/vision) utilise le vrai point de terminaison `POST /api/robot/:id/command`, une petite charge utile ciblée plutôt que d'écraser tout l'arbre settings, avec une propagation correcte du robot combiné (`combinedWith`) pour les 5 commandes qui en ont besoin.
- **Synchronisation WebSocket en direct** (`lib/network/hydra_websocket.dart`) - envoie le jeton comme sous-protocole `hydra.bearer` et jamais dans l'URL de connexion (`server.ts` refuse `/ws?token=` par défaut), gère à la fois les types de diffusion `"settings"` et `"delta"`, se reconnecte automatiquement en cas de coupure.
- **Tableau de bord** (`lib/ui/dashboard_screen.dart`) - cartes par robot, réactives en temps réel via le propre `ChangeNotifier` de `Provider`, convention de LED (vert clignotant = actif, rouge fixe = inactif) et affichage du robot combiné (affiché uniquement du côté suiveur, résolu par id) correspondant au propre Dashboard Overview de HYDRA-UMC-STUDIO.
- **Contrôle Manuel** (`lib/ui/control_screen.dart`, `lib/ui/widgets/joystick_pad.dart`) - D-pad de jog (avec/sans cible de table XY), curseurs de vitesse/accélération, interrupteurs vanne/pompe, et le **STOP** global (`lib/ui/widgets/stop_all.dart`) : un seul appui, sans appui long ni confirmation, il arrête tous les robots (`POST /api/stop-all`) et se trouve dans la barre supérieure de chaque onglet, y compris celui de Contrôle. La réponse est affichée robot par robot (avertissement si un robot a échoué ou si l'arrêt n'a pas été enregistré ; les robots réservés par un autre compte sont signalés), une erreur réseau est retentée une fois, un serveur au-delà de sa limite de requêtes ou sans cette route reçoit l'arrêt robot par robot, et si personne ne répond un bandeau permanent « STOP non confirmé » reste affiché jusqu'à ce qu'un STOP ultérieur obtienne une réponse. Le bouton rond d'arrêt par robot garde sa protection par pression longue.
- **Réservations et limites de sécurité** (`lib/ui/widgets/access_panel.dart`, `lib/models/access.dart`, `lib/network/hydra_api_client.dart`, `lib/state/robot_view_model.dart`) - L’écran Control montre qui tient le robot sélectionné (personne, cet appareil, le même compte sur un autre appareil ou un autre compte) et propose **Réserver** et **Libérer**, ainsi que la liste de toutes les réservations du serveur (`GET /api/claims`). L’appareil garde un identifiant de contrôleur par installation et l’envoie avec chaque réservation, libération, armement du jog et commande (corps et en-tête `X-Controller-Id`) : la réservation appartient donc au compte et à cet appareil, pas à tout le compte. Les refus du serveur sont distingués : réservé par un autre compte, par votre compte sur un autre appareil ou une autre fenêtre, identifiant de contrôleur requis et jog non armé. Les limites du modèle du robot sont lues sur `GET /api/safety-limits` : un pas de jog au-dessus de la limite n’est pas envoyé et les avertissements du serveur sont affichés. Quand l’administrateur l’exige, il faut appuyer sur **Armer le jog** (avec compte à rebours) avant que le joystick déplace le robot ; l’armement se termine tout seul, avec STOP ou à la libération. Les réservations sont facultatives : un robot que personne n’a réservé se commande comme avant. Pour un **administrateur** seulement, un bouton **Prendre le contrôle** apparaît sur un robot détenu par quelqu'un d'autre ; il demande confirmation puis réserve le robot avec `force: true` (le serveur ne l'accepte que des administrateurs et revérifie le rôle). Les écritures sont conditionnelles : chacune porte la révision du robot que cette app a vue en dernier (`If-Match`, `lib/models/contract_v2.dart`) ; si quelqu'un d'autre a modifié le robot entre-temps, le serveur répond 412, rien n'est appliqué, le robot est relu et le message le dit (Standard vérifie les réservations, la table et les commandes ponctuelles ; Strict vérifie tout sauf STOP ; Désactivé ne vérifie rien ; le choix se trouve dans la liste des réservations ; STOP n'est jamais vérifié). Le jog de la table XY est une seule commande atomique `table` (un serveur plus ancien reçoit les jogs qu'il comprend), le serveur pousse les réservations par le WebSocket pour que l'écran Control cesse d'interroger tant qu'elles arrivent, et les administrateurs lisent le journal d'audit (`lib/ui/widgets/audit_dialog.dart`) avec sa chaîne SHA-256 vérifiée deux fois, par le serveur et sur l'appareil, et peuvent copier ses lignes en `.jsonl`.
- **Interrupteurs facultatifs** - deux interrupteurs, tous deux désactivés par défaut : *Bloquer les commandes sur données enregistrées* (Réglages) retient toute commande sauf le STOP tant que l'écran affiche la copie enregistrée de l'état des robots et non l'état réel, et *Ne pas analyser les réseaux de données mobiles ni VPN* (écran de connexion) exclut ces interfaces du balayage du sous-réseau. Les boutons du D-pad de jog font au moins 44 pt et VoiceOver les annonce avec leur axe et leur direction ; l'image de la caméra est fermée tant que l'app est en arrière-plan.
- **Demander avant PLAY** - activé par défaut, désactivable dans les Réglages : avant de lancer une trajectoire, l'app affiche le robot, ses points enregistrés, la vitesse et qui l'a réservé (un robot réservé par quelqu'un d'autre signale que le serveur refusera la commande). Un robot déjà en lecture n'est pas redemandé. Le choix est conservé.
- **Caméra** (`lib/ui/camera_screen.dart`, `lib/ui/widgets/mjpeg_view.dart`) - un petit analyseur de flux MJPEG écrit à la main (aucun paquet tiers), un état clair "Camera Disabled" au lieu d'un flux vide silencieux, et un interrupteur pour activer/désactiver le système de vision d'un robot directement depuis le serveur (la commande atomique `"vision"` propre de `server.ts`).
- **Vue 3D** (`lib/ui/three_d_screen.dart`) - intègre le propre viewport 3D en temps réel de HYDRA-UMC-STUDIO dans une WebView (`?hideUI=true&robotId=#token=`), la même approche que l'application Android, pour la même raison (obtient gratuitement la vraie scène 3D actuellement en production). Se rabat sur un placeholder honnête sur les plateformes que `webview_flutter` ne prend pas en charge (la cible de bureau Windows de ce dépôt, utilisée pour la vérification de build).
- **Métriques système** (`lib/state/robot_view_model.dart`) - `GET /api/system/metrics` interrogé toutes les 5s, la même cadence que les 2 autres clients, affiché dans le Dashboard.
- **Interface en 8 langues** (`lib/l10n/`, pipeline standard `flutter gen-l10n`) - anglais, espagnol, français, allemand, italien, japonais, chinois et portugais, comme le reste des clients de cet écosystème. Un réglage persistant dans `Réglages > Langue` utilise par défaut la langue du système ; `RobotViewModel.lastError` est un `HydraError` typé plutôt qu'un texte anglais déjà formaté, donc les messages d'erreur de la logique métier (échecs de connexion/commande) sont eux aussi correctement traduits, pas seulement le texte statique des écrans.
- **Cache d'état hors ligne** (`lib/network/state_cache.dart`) - le dernier arbre de réglages connu est persisté sur disque (avec un debounce de 1s) avec l'instant réel de sa sauvegarde, afin que les écrans Dashboard/Contrôle affichent des données réelles, même potentiellement obsolètes, dès le lancement plutôt qu'un état vide pendant que le vrai `connect()` est encore en cours. Une bannière réelle et visible (pas une simple supposition silencieuse) indique « données en cache de HH:mm » tant que c'est le cas. Remplacé par les données réelles dès que la connexion réussit.
- **Télémétrie** (`lib/ui/telemetry_screen.dart`) - un journal de type terminal, le plus récent en premier, des événements réels de connexion/connexion utilisateur/commande, plafonné à 50 entrées, avec une action pour l'effacer - la même convention « vert Matrix » que l'onglet Télémétrie de HYDRA-UMC-ANDROID-CONTROL.
- **Assistant Vocal Intégré** (`lib/ui/voice_assistant_dialog.dart`) - une icône de micro dans la barre d'application ouvre une boîte de dialogue pour taper une question ou un ordre, envoyée à `HYDRA-UMC-VOICE-UI` via la même route réelle `POST /api/voice/turn` qu'utilisent le bouton vocal intégré et le relais avec la montre jumelée de HYDRA-UMC-ANDROID-CONTROL. N'envoie jamais l'audio - texte uniquement pour l'instant, car la reconnaissance vocale native d'iOS nécessite le framework Speech, que cet environnement de développement Windows uniquement ne peut ni compiler ni vérifier sur un appareil réel/Xcode. Une réponse n'émet jamais de commande robot directement.

## 🔒 Sécurité et protection

| Menace | Défense | Où |
|---|---|---|
| Un jeton volé sur le téléphone | Le jeton, le nom d'utilisateur et le jeton de renouvellement sont stockés avec `flutter_secure_storage` (le trousseau iOS) ; seuls l'hôte, le port et les préférences vont dans `shared_preferences` ; l'application ne stocke jamais de mot de passe en clair | `network/auth_prefs.dart` |
| Identifiants dans la copie enregistrée de l'état | La copie du dernier état écrite sur disque perd les clés `ipUsername` et `ipPassword` à toute profondeur, et elle est effacée à la déconnexion | `network/state_cache.dart` |
| Le jeton dans un journal ou dans l'adresse du WebSocket | Le jeton passe dans le sous-protocole `hydra.bearer` du WebSocket et jamais dans son adresse ; la vue 3D intégrée le reçoit dans le fragment de l'adresse (`#token=`), qui n'est pas envoyé au serveur ; un test vérifie les deux | `network/hydra_websocket.dart`, `util/viewer_url.dart` |
| Quelqu'un avec le téléphone déverrouillé | Un verrou biométrique facultatif (Face ID, Touch ID) conditionne la restauration d'une session enregistrée au démarrage ; l'image de la caméra est fermée tant que l'application est en arrière-plan | `network/biometric_helper.dart`, `ui/biometric_gate_screen.dart` |
| Un robot déplacé par deux personnes, un PLAY pressé par erreur ou un arrêt qui n'arrive pas | Le robot est réservé avant d'être déplacé et l'écran dit qui le détient ; PLAY demande d'abord par défaut et montre le robot, ses points, la vitesse et qui l'a réservé ; l'arrêt global est réessayé une fois, se replie sur un arrêt par robot et garde une bannière persistante « ARRÊT non confirmé » si rien n'a répondu | `models/access.dart`, `util/play_confirmation.dart`, `ui/widgets/stop_all.dart` |

**Ce qu'elle ne fait jamais :** remplacer un arrêt d'urgence physique, ni chiffrer le trafic d'elle-même : l'application essaie HTTPS une fois quand une sonde HTTP en clair n'obtient pas de réponse, et elle n'a ni épinglage de certificat ni garde contre le trafic en clair hors du réseau local. L'ARRÊT est l'arrêt logiciel du serveur.

## 🔌 Interfaces

| Topic ou route | Ce qu'il porte |
|---|---|
| `POST /api/login`, `/api/logout`, `/api/refresh` | se connecter, se déconnecter et renouveler la session |
| `GET /api/hydra-info` | reconnaît un vrai serveur ; utilisé par le balayage du sous-réseau et l'adresse manuelle, avec un nouvel essai en HTTPS |
| `GET /api/settings`, `/api/system/metrics`, `/api/safety-limits`, `/api/claims` | l'état des robots, le module de calcul (toutes les 5 s), les limites de sécurité de chaque modèle et les réservations |
| `POST /api/robot/{id}/command`, `/claim`, `/release`, jog arming | une petite commande pour un robot, sa réservation et l'armement d'un déplacement manuel, avec des écritures conditionnelles par révision du robot |
| `POST /api/stop-all` | l'ARRÊT global : tous les robots, avec une réponse robot par robot |
| `GET /api/audit`, `POST /api/voice/turn`, `GET /api/camera/{id}/stream` | le journal d'audit (administrateurs, avec son propre contrôle de chaîne SHA-256), un tour de voix saisi au clavier et le flux MJPEG d'une caméra |
| WebSocket `hydra.bearer`, mDNS `_hydra._tcp.local` | changements d'état en direct (messages `settings` et `delta`, reconnexion après 3 s jusqu'à 30 s, un ping toutes les 20 s) et l'annonce Bonjour du serveur |

## ⚙️ Configuration

L'application n'a pas de fichier de configuration : tout se règle à l'écran et se stocke sur l'appareil. Les valeurs par défaut viennent du code.

| Variable | Par défaut | Ce qu'elle définit |
|---|---|---|
| Réglages > Demander avant PLAY | activé | montre le robot, ses points, la vitesse et qui l'a réservé avant le début d'une trajectoire |
| Réglages > Bloquer les commandes sur données enregistrées | désactivé | retient toute commande sauf ARRÊT tant que l'écran montre la copie enregistrée de l'état et non l'état en direct |
| Connexion > Ne pas balayer les réseaux de données mobiles ni VPN | désactivé | laisse ces interfaces hors du balayage du sous-réseau (32 hôtes à la fois, port 3000 sauf si vous en saisissez un autre) |
| Réglages > Verrou biométrique | désactivé | demande Face ID ou Touch ID avant de restaurer une session enregistrée au démarrage |
| Réglages > Langue | la langue du système | l'une des huit langues de l'application (`lib/l10n/`), conservée entre les lancements |

## 🚀 Démarrage rapide

Nécessite le SDK Flutter stable (Dart 3.13 ou plus récent). Windows exécute la logique et les tests ; une vraie compilation pour iPhone demande Xcode sur un Mac.

```bash
flutter pub get                  # downloads the packages
flutter test                     # runs the unit tests on this machine
./build-test.sh                  # non-mutating build check (build-test.bat on Windows)
flutter build ios --no-codesign  # a real iOS build; only on a Mac with Xcode
```

## 🧪 Tests

254 tests automatiques s'exécutent avec `flutter test`. Ils n'ont besoin ni de matériel ni de rien en dehors de cette machine.

La CI exécute `HYDRA_UMC_CI=1 python tools/ci_validate.py`, qui vérifie le manifeste, les documents, les huit README et les images.

## 🏗️ Compilation et publication

Nécessite le [Flutter SDK](https://docs.flutter.dev/get-started/install) (canal stable). Ce dépôt est compilé/vérifié avec Flutter 3.47.0. Seules `windows/` et `ios/` sont configurées comme plateformes dans ce dépôt (pas de dossiers `android/`, `linux/`, `web/`, ou `macos/`) - Windows existe pour que la logique propre de cette application puisse être compilée et exécutée sans un Mac ; iOS est la véritable cible.

### Scripts de build

```bash
./build.sh     # Git Bash / WSL - flutter pub get + flutter build windows
build.bat      # cmd.exe / PowerShell - flutter pub get + flutter build windows
```

Les deux produisent `build/windows/x64/runner/Release/hydra_umc_control.exe`, et aucun ne change la version de l'app - voir [Versionnage](#versionnage) ci-dessous.

### Build manuel

```bash
flutter pub get
flutter analyze          # analyse statique - aucun compilateur necessaire
flutter test             # tests de widgets
dart run tool/bump_version.dart  # incremente la version, comme le font build.sh/build.bat
flutter build windows    # produit build/windows/x64/runner/Release/hydra_umc_control.exe
flutter run -d windows   # ou -d <ios-device-id> depuis un Mac
```

**Compiler le vrai `.ipa` iOS** nécessite Xcode sous macOS - depuis cette machine : `flutter build ipa` (ou ouvrir directement `ios/Runner.xcworkspace` dans Xcode). Cela ne peut pas être fait depuis Windows ; voir "Pourquoi Flutter, et non Swift natif" ci-dessus.

### Versionnage

Ce dépôt suit une politique à l'échelle de l'écosystème : compiler ne change jamais la version. La commande `bump` explicite (`python tools/hydra_project_tool.py bump`) exécute `tool/bump_version.dart`, qui applique :

- **Patch, façon compteur kilométrique (base 10) :** +1 à chaque bump ;
  une fois 9 dépassé, il repasse à 0 et minor gagne +1 - ex. `0.0.9` ->
  `0.1.0`. Major n'est jamais modifié automatiquement.
- **Build number** (la partie après `+`) : un simple compteur
  monotone, +1 à chaque bump, sans report.

Le même script régénère `lib/app_version.dart` (généré, non modifié à
la main - un simple fichier `const`, pas une nouvelle dépendance
d'exécution comme `package_info_plus`), que l'app lit en temps réel
pour afficher sa propre version sur l'écran **Paramètres**. Voir
[CHANGELOG.md](CHANGELOG.md) pour l'historique des versions.

## 🩺 Dépannage

| Vous voyez | Parce que | Faites |
|---|---|---|
| « Session non autorisée : reconnectez-vous » | Le serveur a refusé le jeton (le WebSocket a été fermé avec le code 1008) ou il a expiré | Reconnectez-vous |
| « ARRÊT non confirmé par le serveur » | Rien n'a répondu à l'ARRÊT global dans son court délai, ou le serveur n'a pas pu enregistrer l'état d'arrêt | Appuyez à nouveau ; si la bannière reste, utilisez l'arrêt d'urgence physique |
| Le robot est réservé par un autre compte, ou par votre compte sur un autre appareil | Une réservation appartient au compte et à l'appareil (un identifiant de contrôleur par installation) | Utilisez cet appareil, ou libérez la réservation là-bas |
| « Données enregistrées de HH:mm affichées » | Le serveur est hors de portée et l'écran montre la copie enregistrée du dernier état ; avec Bloquer les commandes sur données enregistrées activé, toute commande sauf ARRÊT est retenue | Vérifiez le serveur et le Wi-Fi ; l'écran repasse seul en direct quand la connexion revient |
| « Déplacement refusé : le pas dépasse la limite » | Le pas dépasse la limite que le serveur fixe pour ce modèle de robot (`GET /api/safety-limits`) | Utilisez un pas plus petit ; rien n'a été envoyé |
| « Balayer le réseau local » ne trouve aucun serveur | Sur un vrai iPhone, Bonjour demande une autorisation qu'une compilation simple ne porte pas, et le balayage peut laisser de côté les réseaux de données mobiles et VPN | Rejoignez le même Wi-Fi que le serveur, ou saisissez à la main son adresse et son port |

## 📂 Structure du dépôt

<p align="center">
  <img src="images/repository-structure.svg" alt="Repository structure of HYDRA-UMC-IOS-CONTROL" width="100%">
</p>

<details>
<summary>Version texte de l'arborescence</summary>

```text
HYDRA-UMC-IOS-CONTROL/
├── lib/                                                              code source
│   ├── main.dart                                                     Point d'entree de l'application, ChangeNotifierProvider + porte de connexion
│   ├── app_version.dart                                              GENERE - regenere par bump_manifest_version.py, ne pas modifier a la main
│   ├── models/                                                       modèles de données et règles pures
│   ├── network/                                                      client REST, WebSocket et découverte
│   ├── state/                                                        l'état que chaque écran écoute
│   ├── l10n/                                                         Vraies localisations générées (8 langues) - voir l10n.yaml à la racine du dépôt
│   ├── util/                                                         Utilitaires sans écran propre
│   └── ui/                                                           écrans et widgets
├── ios/                                                              Projet Xcode (compiler uniquement depuis macOS)
├── windows/                                                          Cible de bureau Windows - verification de build sans un Mac
├── tools/                                                            outils du projet et vérifications de la CI
├── test/                                                             les tests unitaires de la logique
├── images/                                                           bannière et images du README
├── .github/                                                          workflow de CI et modèles de tickets
├── build.bat / build.sh                                              flutter pub get puis flutter build windows ; ne change jamais la version
├── docs/ARCHITECTURE.md                                              architecture du projet
├── pubspec.yaml / pubspec.lock / l10n.yaml / analysis_options.yaml   La définition du paquet Flutter et ses versions figées, les réglages du générateur l10n et les règles de lint
├── CHANGELOG.md                                                      ce qui a changé à chaque version
├── build-test.sh                                                     vérification de build sans modification
├── bump_manifest_version.py                                          synchronise la version du manifeste
├── hydra-umc.project.json                                            manifeste : version, maturité, famille
└── test.sh                                                           vérification de build sans modification (flutter test lance les tests unitaires)
```

</details>

## 🗺️ Feuille de route et limites connues

Il n'y a pas de compilation pour iPhone ou iPad dans la CI : `flutter build ios` demande Xcode sur un Mac, l'application n'a donc été exécutée et testée que sous Windows. La découverte Bonjour demande une autorisation qu'une compilation simple ne porte pas ; sur un vrai iPhone, c'est donc le balayage du sous-réseau qui trouve le serveur. Il n'y a pas encore de reconnaissance vocale sur l'appareil (l'assistant vocal prend du texte saisi), ni de réglages TLS, ni de Bluetooth.

## 🌍 Langues

Ce README et les documents du dépôt existent en huit langues : anglais, espagnol, allemand, français, italien, japonais, chinois et portugais (Portugal). Ils sont écrits ensemble et la CI vérifie que les huit fichiers ont les mêmes sections et les mêmes liens.

## 🔗 Projets liés

Ce projet fait partie de l'écosystème robotique HYDRA-UMC du même auteur (JuanenRac / Electro Hobby 3D). Bon à savoir, car une demande pourrait en réalité concerner l'un de ceux-ci plutôt que ce dépôt.

**Projet Parent**
- **[HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER)** — le vrai backend headless (REST/WebSocket) auquel parle réellement chaque client de contrôle ; le backend contre lequel s'exécutent la connexion, les commandes atomiques et la synchronisation WebSocket propres à cette application.

**Projets Frères** — parlent également à la propre API de HYDRA-UMC-SERVER, chacun en tant que son propre client
- **[HYDRA-UMC-STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO)** — tableau de bord de contrôle web avec visualisation 3D multi-robot en temps réel ; son propre visualiseur 3D est intégré directement dans l'écran Vue 3D de cette application via WebView.
- **[HYDRA-UMC-SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE)** — centre de commande d'essaim de bureau (PySide6) pour plusieurs serveurs à la fois, empaqueté en exécutable autonome ; parle exactement le même contrat `REMOTE_API.md` que cette application.
- **[HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL)** — application de contrôle Android native avec connexion biométrique et un compagnon Wear OS jumelé ; parle exactement le même contrat `REMOTE_API.md` que cette application.
- **[HYDRA-UMC-DSI](https://github.com/JuanenRac/HYDRA-UMC-DSI)** — interface tactile native pour l'écran tactile DSI 7" embarqué, intégrée directement sur le CM5.
- **[HYDRA-UMC-BRIDGE-AMR](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-AMR)** — frontière de coordination pour les flottes AGV/AMR via un éditeur MQTT VDA 5050 (testé uniquement contre une flotte émulée).
- **[HYDRA-UMC-BRIDGE-CNC](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-CNC)** — coordinateur haut niveau pour cellules CNC avec accès au statut/octets de contrôle GRBL (testé uniquement contre un émulateur).
- **[HYDRA-UMC-BRIDGE-DROIDS](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-DROIDS)** — frontière de coordination pour droïdes à pattes/humanoïdes, avec un émetteur de commandes Boston Dynamics Spot (testé uniquement contre un émulateur).
- **[HYDRA-UMC-BRIDGE-LASER](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-LASER)** — coordinateur de cellules laser lisant 3 signaux GPIO de clé/enceinte/verrouillage (testé uniquement contre une puce simulée ; il ne peut ni armer ni tirer un laser).
- **[HYDRA-UMC-BRIDGE-OPENPNP](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-OPENPNP)** — coordinateur haut niveau sûr pour le flux de cartes du pick-and-place OpenPnP.
- **[HYDRA-UMC-BRIDGE-PRINTER3D](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-PRINTER3D)** — frontière de coordination sûre pour imprimantes 3D Moonraker/Klipper, avec de vraies commandes de tâche contrôlées.
- **[HYDRA-UMC-BRIDGE-ROS2](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-ROS2)** — coordinateur avec un transport ROS 2 rclpy à importation paresseuse (pas encore exécuté contre une installation ROS 2).
- **[HYDRA-UMC-BRIDGE-UAV](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-UAV)** — frontière de coordination pour UAV équipés de caméra, avec un émetteur de commandes MAVLink (testé uniquement contre un émulateur).

**Directement Liés**
- **[HYDRA-UMC-WATCH](https://github.com/JuanenRac/HYDRA-UMC-WATCH)** — application compagnon WearOS avec des motifs d'alerte haptique et un relais vocal vers le téléphone jumelé (pas encore exécutée sur une montre physique) ; la compagne de poignet de HYDRA-UMC-ANDROID-CONTROL (WearOS uniquement : cette application iOS n'a pas encore d'équivalent Apple Watch).
- **[HYDRA-UMC-HIL-BRIDGE](https://github.com/JuanenRac/HYDRA-UMC-HIL-BRIDGE)** — routeur hardware-in-the-loop avec un verrouillage logiciel de collision entre simulation et matériel réel (testé sans matériel réel) ; le pont qui permet à cette application de contrôler à distance le jumeau numérique, hardware-in-the-loop.

**Fait Également Partie de l'Écosystème**

*Matériel & Plateforme de Base*
- **[HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC)** — la conception de la carte mère du bras robotique : hôte CM5 + coprocesseur STM32H745 double cœur, destinée à coordonner jusqu'à 8 bras-outils via CAN-OTA/SPI-OTA (firmware à un stade précoce ; aucune carte assemblée pour l'instant).
- **[HYDRA-UMC-OS](https://github.com/JuanenRac/HYDRA-UMC-OS)** — couche produit reproductible sur Raspberry Pi OS pour le CM5 : agent en lecture seule, config/profils validés, provisionnement WiFi de premier contact.
- **[HYDRA-UMC-SDK](https://github.com/JuanenRac/HYDRA-UMC-SDK)** — le contrat JSON-Schema partagé et la barrière logicielle de contrôle des jobs contre laquelle chaque bridge valide ses commandes (pas une fonction de sécurité certifiée).
- **[HYDRA-UMC-CONNECTOR-HUB](https://github.com/JuanenRac/HYDRA-UMC-CONNECTOR-HUB)** — registre déclaratif et validateur de manifestes d'adaptateur pour les connecteurs de machines externes ; étend la propre idée de contrat du SDK aux machines externes sans remplacer les projets de passerelle industrielle.

*Backend Central & Clients*
- **[HYDRA-UMC-EDITOR-URDF](https://github.com/JuanenRac/HYDRA-UMC-EDITOR-URDF)** — créateur/éditeur graphique de bureau pour URDF qui envoie les modèles terminés vers le propre catalogue de STUDIO.
- **[HYDRA-UMC-EDITOR-STL](https://github.com/JuanenRac/HYDRA-UMC-EDITOR-STL)** — éditeur de bureau de modèles STL, transformant/remplaçant/retirant/ajoutant de vraies pièces dans le même catalogue de modèles qu'édite aussi HYDRA-UMC-EDITOR-URDF.

*Plateforme d'Outils URTC*
- **[URTC](https://github.com/JuanenRac/URTC)** — firmware pour la carte physique Universal Robot Tool Controller, plus de 25 profils d'outil sur bus CAN.
- **[URTC-FLASHER](https://github.com/JuanenRac/URTC-FLASHER)** — outil de bureau à interface graphique pour flasher les cartes URTC, CAN-OTA plus SWD/JTAG puce complète.
- **[URTC-TESTER](https://github.com/JuanenRac/URTC-TESTER)** — outil de bureau de diagnostic CAN-bus en direct pour cartes URTC, un panneau par profil d'outil.
- **[URTC-WEB-STUDIO](https://github.com/JuanenRac/URTC-WEB-STUDIO)** — alternative basée navigateur à URTC-TESTER via la Web Serial API, sans installation locale.
- **[URTC-GATEWAY](https://github.com/JuanenRac/URTC-GATEWAY)** — passerelle devant le bus CAN d'URTC : liste d'identifiants autorisés, limite de débit et clé de session ; logiciel testé sur ordinateur, pas encore sur un bus réel.

*Nœud IA de Vision (Hailo-8)*
- **[HYDRA-UMC-VISION-NODE](https://github.com/JuanenRac/HYDRA-UMC-VISION-NODE)** — hub d'intégration pour le pipeline de vision Hailo-8, avec une vraie vérification de disponibilité matérielle par étape.
- **[HYDRA-UMC-DETECTION-HEF](https://github.com/JuanenRac/HYDRA-UMC-DETECTION-HEF)** — registre réel de modèles compilés avec vérification de chargement sécurisé par architecture Hailo/checksum.
- **[HYDRA-UMC-VISION-STREAMER](https://github.com/JuanenRac/HYDRA-UMC-VISION-STREAMER)** — générateur réel de pipeline GStreamer + config MediaMTX, avec une vraie frontière d'intégration HailoRT.
- **[HYDRA-UMC-VISUAL-SERVOING-API](https://github.com/JuanenRac/HYDRA-UMC-VISUAL-SERVOING-API)** — loi de correction Position-Based Visual Servoing avec autorisation conditionnée à l'état de zone ; pas encore d'estimation de pose par caméra.
- **[HYDRA-UMC-SAFETY-ZONES](https://github.com/JuanenRac/HYDRA-UMC-SAFETY-ZONES)** — logique v0 de violation de zone, de fraîcheur de calibration et de demande d'E-STOP qui lit les positions d'objets dans un fichier ; aucun détecteur ne l'alimente et aucun E-STOP physique n'y est encore relié.

*Nœud IA Cognitif (Hailo-10)*
- **[HYDRA-UMC-COGNITIVE-NODE](https://github.com/JuanenRac/HYDRA-UMC-COGNITIVE-NODE)** — hub d'intégration pour le pipeline cognitif Hailo-10 (orchestration LLM/VLA/voix).
- **[HYDRA-UMC-VLA-ENGINE](https://github.com/JuanenRac/HYDRA-UMC-VLA-ENGINE)** — vrai encodage/décodage de jetons d'action et génération de trajectoire pour un modèle Vision-Language-Action.
- **[HYDRA-UMC-VOICE-UI](https://github.com/JuanenRac/HYDRA-UMC-VOICE-UI)** — vrai front-end vocal (VAD + analyseur d'intention) avec un relais Watch borné et soumis à confirmation.
- **[HYDRA-UMC-SEMANTIC-PLANNER](https://github.com/JuanenRac/HYDRA-UMC-SEMANTIC-PLANNER)** — vraie décomposition de tâches basée sur des règles et récupération sémantique d'erreurs sur les codes d'erreur MCU.
- **[HYDRA-UMC-DOCS-QA](https://github.com/JuanenRac/HYDRA-UMC-DOCS-QA)** — vraie recherche documentaire TF-IDF (bibliothèque standard uniquement) sur les propres documents Markdown de cet écosystème.
- **[HYDRA-UMC-LOCAL-TECHNICIAN](https://github.com/JuanenRac/HYDRA-UMC-LOCAL-TECHNICIAN)** — technicien de maintenance IA local et à portes de politique pour l'écosystème lui-même - observe, diagnostique et propose des corrections ; les deux niveaux de risque les plus élevés ne sont délibérément pas encore implémentés.

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
- **[HYDRA-UMC-OS-REBUILDER](https://github.com/JuanenRac/HYDRA-UMC-OS-REBUILDER)** — outil de bureau Windows/Linux qui construit une image de la CM5 prête à graver, préchargée avec les versions les plus actuelles de l'écosystème, avec une configuration de premier démarrage Wi-Fi/utilisateur/SSH façon Raspberry Pi Imager.
- **[HYDRA-UMC-OPS-AGENT](https://github.com/JuanenRac/HYDRA-UMC-OPS-AGENT)** — coordinateur d'incidents de maintenance : un rôle edge à faible privilège collecte un instantané d'inventaire/santé assaini, un rôle control-plane le rend en lecture seule et demande à un fournisseur d'IA de suggérer un diagnostic - n'applique jamais de correctif ni ne déploie rien.
- **[HYDRA-UMC-DEV-SERVER](https://github.com/JuanenRac/HYDRA-UMC-DEV-SERVER)** — hôte de développement reproductible (Raspberry Pi 5 / CM5) qui héberge le code source de l'écosystème et exécute des tâches de compilation/test délimitées via une file d'attente durable ; un rôle de développement dédié, explicitement distinct d'un CM5 opérationnel.

## 📚 Documentation

Où lire la suite :

* [docs/SOURCE_MAP.md](docs/SOURCE_MAP.md) - chaque fichier source de l'application avec une ligne sur son rôle
* **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — le contrat de transport Wi-Fi que cette app parle avec `server.ts` (endpoint par endpoint), pourquoi il n'y a toujours aucune voie Bluetooth, le vrai mécanisme de découverte à deux voies, et la relation de cette app avec le reste de l'écosystème.
* [Base de sécurité de l'écosystème](https://github.com/JuanenRac/HYDRA-UMC-DOCS/blob/main/docs/SECURITY_BASELINE.md)
* [Modèle de menaces de l'écosystème](https://github.com/JuanenRac/HYDRA-UMC-DOCS/blob/main/docs/THREAT_MODEL.md)
* [Journal des modifications de ce dépôt](CHANGELOG.md)
* [Licence de ce dépôt](LICENSE.md)

## 🤝 Contribuer et communauté

* Avant une pull request, exécutez `HYDRA_UMC_CI=1 py -3 tools/ci_validate.py` (ou `HYDRA_UMC_CI=1 python3 tools/ci_validate.py`) : il doit afficher `CI_VALIDATION=PASS`. N'exécutez pas `build.sh` ni `build.bat` pour cette vérification ; compiler n'est pas vérifier.
* Les huit README sont écrits à partir d'une source unique dans HYDRA-UMC-DOCS ; ne les modifiez pas à la main. Changez la source et réécrivez-les avec `tools/make_readmes.py`.
* N'affirmez pas dans un README ce qui n'a pas tourné : écrivez « simulé » ou « non essayé sur matériel » quand c'est la vérité.
* Voir [CONTRIBUTING.md](CONTRIBUTING.md), le [code de conduite](CODE_OF_CONDUCT.md), [SECURITY.md](SECURITY.md) et [SUPPORT.md](SUPPORT.md).

## 👤 AUTEUR

**JuanenRac (Electro Hobby 3D)** · electrohobby3d@gmail.com

## 📜 LICENCE

GPL-3.0-or-later - [LICENSE](LICENSE).
