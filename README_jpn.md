<p align="center">
  <img src="images/HYDRA_UMC_BANNER.svg" alt="HYDRA-UMC-IOS-CONTROL banner" width="100%">
</p>

# 📱 HYDRA-UMC CONTROL（iOS）

<p align="center">
  <a href="README.md">🇺🇸 English</a> |
  <a href="README_spa.md">🇪🇸 Español</a> |
  <a href="README_fra.md">🇫🇷 Français</a> |
  <a href="README_ita.md">🇮🇹 Italiano</a> |
  <a href="README_deu.md">🇩🇪 Deutsch</a> |
  <a href="README_zho.md">🇨🇳 简体中文</a> |
  🇯🇵 <b>日本語</b>
</p>


<p align="left">
  <img src="https://img.shields.io/badge/License-GPL%203.0-blue.svg" alt="GPL 3.0">
  <img src="https://img.shields.io/badge/Framework-Flutter-02569B.svg" alt="Flutter">
  <img src="https://img.shields.io/badge/Language-Dart-0175C2.svg" alt="Dart">
  <img src="https://img.shields.io/badge/Platform-iOS-000000.svg" alt="iOS">
</p>


Wi-Fi 経由で [HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC) プラットフォーム上のロボットを制御する、クロスプラットフォームな Flutter アプリ（Dart）です。[HYDRA-UMC SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE) と [HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL) が使用しているのとまったく同じ [`REMOTE_API.md`](https://github.com/JuanenRac/HYDRA-UMC-SERVER/blob/main/docs/REMOTE_API.md) 契約を話します——稼働中の [HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER) インスタンス（HYDRA-UMC STUDIO 自身のプロセスから切り離されたヘッドレスバックエンド——STUDIO は現在、本アプリと同様にその純粋なフロントエンドクライアントです）に対するディスカバリー、ログイン、原子的なロボットごとの指令、リアルタイム WebSocket 同期。

## 🔀 ネイティブ Swift ではなく Flutter を選んだ理由

本アプリは iOS/iPadOS をターゲットとしていますが、Swift/SwiftUI ではなく **Flutter** で構築されています：本リポジトリの作業環境は Windows のみであり、ネイティブ Swift プロジェクトは Windows 上で*記述*はできても、そこで*コンパイルまたは実行*することは決してできません（Xcode と iOS SDK は macOS 専用です）。Flutter 自身の Windows デスクトップターゲットにより、本アプリはこのマシン上で実際にビルド、実行、テストできます——`flutter analyze` はクリーン、`flutter build windows` は成功し、`flutter test` はパスし、ビルドされた `.exe` はランタイムエラーなく起動してレンダリングされます——Mac が手に入るまで何も検証できないまま、何千行もの Swift コードを盲目的に書くのではなく。

**これはアップル自身の制約を取り除くものではありません**——実際の `.ipa` は、依然として Mac 上の（あるいは macOS CI ランナー上の）Xcode でビルド・署名する必要があります。フレームワークの選択はそれを変えません。Flutter がもたらすのは、本アプリ自身のロジック（ネットワーキング、状態、UI）のあらゆる他の行を今日このマシン上で検証できる能力であり、後で書き直すことなく同一のコードベースを iOS に出荷できる能力です。

## 🏗️ 実装済みの内容

- **ログイン**（`lib/ui/login_screen.dart`、`lib/state/robot_view_model.dart`）—— 編集可能なサーバー IP/ポートとオペレーター認証情報フィールド、および `POST /api/login` を使用します。アカウントやパスワードは事前入力されません。本番サーバーでは最初の管理者用に明示的に設定したブートストラップ認証情報が必要です。追加の低権限「オペレーター」アカウントはブラウザー UI の Config > Users から作成できます。セッショントークンは `shared_preferences` により起動をまたいで保持されます。「ローカルネットワークをスキャン」ボタン（`lib/network/discovery.dart`）は、ユーザーが IP を事前に知らなくてもサーバーを見つけられます。
- **ネットワークディスカバリー**（`lib/network/discovery.dart`）—— 「ローカルネットワークをスキャン」シートから 2 つの独立した経路が同時に実行されます: 実際の mDNS/Bonjour（`discoverMdns()`、`multicast_dns` パッケージ経由で `server.ts` が公開する `_hydra._tcp.local` サービスを問い合わせます——本アプリはエコシステムの 3 つのリモートクライアントの中で最初にこれを追加したものです）に加えて、このデバイス自身の実際のローカルサブネットに対する `GET /api/hydra-info` の並行総当たりスキャン（`scanSubnets()`、単一のハードコードされた推測ではなく `dart:io` の `NetworkInterface.list()` から導出されます。スマートフォンの LAN は `192.168.1.x` と同じくらい `192.168.0.x` や `10.x.x.x` である可能性があるため、インターフェースの列挙自体が空を返した場合にのみ `192.168.1.x` にフォールバックします）。権限が付与されていない iOS ビルドで mDNS が静かに失敗するのは想定内です（Apple の Multicast Networking 権限は通常の `flutter build ios` では付与されません）——いずれにせよサブネットスキャンは独立して動作し続けます。
- **生体認証ゲート**（`lib/network/biometric_helper.dart`、`lib/ui/biometric_gate_screen.dart`）—— `package:local_auth` による Face ID/Touch ID/Windows Hello。`Settings` のオプションのトグルで、起動時にすでに有効な保存済みセッションを復元する処理を保護します（本アプリは平文パスワードを一切保存せず、トークンのみを保存します——HYDRA-UMC-ANDROID-CONTROL 自身のパスワード再入力デザインをこの違いに合わせて適応させたものです）。
- **原子的な指令同期**（`lib/state/robot_view_model.dart` 自身の `_sendAtomicCommand()`）—— すべての書き込み（有効化/無効化/再生/一時停止/停止/ジョグ/バルブ/ポンプ/速度/ビジョン）は、実際の `POST /api/robot/:id/command` エンドポイントを使用し、設定ツリー全体を上書きするのではなく、小さな標的を絞ったペイロードを送信し、それが必要な 5 つの指令に対しては正しい統合ロボット（`combinedWith`）の伝播を行います。
- **リアルタイム WebSocket 同期**（`lib/network/hydra_websocket.dart`）—— 接続 URL には常に `?token=` を付加します（`server.ts` 自身の `/ws` アップグレードは無条件にこれを要求します）。`"settings"` と `"delta"` の両方のブロードキャストタイプを処理し、切断時には自動的に再接続します。
- **ダッシュボード**（`lib/ui/dashboard_screen.dart`）—— ロボットごとのカード、`Provider` 自身の `ChangeNotifier` によるリアルタイムの反応、LED の慣例（緑の点滅=アクティブ、赤の点灯=非アクティブ）、そして統合ロボット表示（フォロワー側でのみ表示され、id で解決されます）——HYDRA-UMC-STUDIO 自身のダッシュボード概要と一致しています。
- **手動制御**（`lib/ui/control_screen.dart`、`lib/ui/widgets/joystick_pad.dart`）—— ジョグ方向パッド（XY テーブルターゲットあり/なし）、速度/加速度スライダー、バルブ/ポンプのトグル、そして緊急停止/停止に対する実際の長押し保護（すばやいタップでは何も起こらず、触感フィードバック+視覚的なヒントのみで、本当に長押しした場合にのみ指令が送信されます）。
- **カメラ**（`lib/ui/camera_screen.dart`、`lib/ui/widgets/mjpeg_view.dart`）—— 小さな手作りの MJPEG ストリームパーサー（サードパーティパッケージなし）、（サイレントに空白のフィードを表示するのではなく）明確な「カメラ無効」状態、そしてサーバーから直接ロボットのビジョンシステムをオン/オフする切り替えスイッチ（`server.ts` の `"vision"` 原子指令）。
- **3D ビュー**（`lib/ui/three_d_screen.dart`）—— HYDRA-UMC-STUDIO 自身のリアルタイム 3D ビューポートを WebView に埋め込みます（`?hideUI=true&robotId=&token=`）。Android アプリと同じアプローチで、同じ理由からです（実際の、現在提供されている 3D シーンを無料で得られます）。`webview_flutter` がサポートしていないプラットフォーム（本リポジトリのビルド検証に使用される Windows デスクトップターゲット）では、正直なプレースホルダーにフォールバックします。
- **システム指標**（`lib/state/robot_view_model.dart`）—— `GET /api/system/metrics` を 5 秒ごとにポーリングします。他の 2 つのクライアントと同じ頻度で、ダッシュボードに表示されます。
- **7言語対応UI**（`lib/l10n/`、標準の `flutter gen-l10n` パイプライン）—— 英語・スペイン語・フランス語・ドイツ語・イタリア語・日本語・中国語に対応し、このエコシステムの他のクライアントと同じです。`設定 > 言語` に保存される上書き設定はデフォルトでOSのロケールに従います。`RobotViewModel.lastError` は整形済みの英語テキストではなく型付きの `HydraError` になっているため、ビジネスロジック側のエラーメッセージ（サインイン・接続・コマンド失敗)も画面の静的なテキストと同様に正しくローカライズされます。
- **オフライン状態キャッシュ**（`lib/network/state_cache.dart`）—— 最後に把握した設定ツリーをディスクに保存します（1秒のデバウンス付き）。これにより、実際の `connect()` の往復通信がまだ進行中でも、ダッシュボード/操作画面が空の状態ではなく、多少古い可能性はあっても実際のロボットデータをすぐに表示します。実際の取得が成功した瞬間に置き換えられます。
- **テレメトリ**（`lib/ui/telemetry_screen.dart`）—— 接続・サインイン・コマンドの実際のライフサイクルイベントを新しい順に表示するターミナル風のログで、最大50件まで保持し、ログを消去する操作も備えています。HYDRA-UMC-ANDROID-CONTROL 自身のテレメトリタブと同じ「マトリックスグリーン」の配色です。

## 🚀 ビルド

[Flutter SDK](https://docs.flutter.dev/get-started/install)（stable チャンネル）が必要です。本リポジトリは Flutter 3.47.0 に対してビルド/検証されています。本リポジトリでは `windows/` と `ios/` のみがプラットフォームとして設定されています（`android/`、`linux/`、`web/`、`macos/` フォルダはありません）——Windows は、Mac なしで本アプリ自身のロジックをビルド・実行できるようにするために存在します。iOS が真のターゲットです。

### ビルドスクリプト

```bash
./build.sh     # Git Bash / WSL —— flutter pub get + バージョン加算 + flutter build windows
build.bat      # cmd.exe / PowerShell —— flutter pub get + バージョン加算 + flutter build windows
```

どちらも `build/windows/x64/runner/Release/hydra_umc_control.exe` を生成し、どちらも最初にアプリのバージョンを加算します——下記の[バージョン管理](#-バージョン管理)参照。

### 手動ビルド

```bash
flutter pub get
flutter analyze          # 静的解析——コンパイラ不要
flutter test             # ウィジェットテスト
dart run tool/bump_version.dart  # バージョンを加算、build.sh/build.bat が行うのと同じ
flutter build windows    # build/windows/x64/runner/Release/hydra_umc_control.exe を生成
flutter run -d windows   # または Mac 上で -d <ios-device-id>、あるいは -d chrome でクイックな Web プレビュー
```

**実際の iOS `.ipa` をビルドする**には、macOS 上の Xcode が必要です——そのマシンから：`flutter build ipa`（または Xcode で `ios/Runner.xcworkspace` を直接開く）。これは Windows からは行えません。上記「ネイティブ Swift ではなく Flutter を選んだ理由」を参照してください。

## 🔢 バージョン管理

本リポジトリは、エコシステム全体で統一されたポリシーに従います：バージョンは**実際のビルドのたび**に自動的に加算され、`pubspec.yaml` の `version:` 行を手動で編集する必要はありません。`build.sh`/`build.bat` は、`flutter build` を呼び出す前に `tool/bump_version.dart` を実行し、以下を適用します：

- **Patch、オドメーター方式（10 進法）：** 毎回のビルドで +1；9 を超えるとリセットされて 0 になり、代わりに minor が +1 されます——例：`0.0.9` -> `0.1.0`。Major は自動的には決して変更されません。
- **ビルド番号**（`+` の後の部分）：単純な単調カウンター、毎回のビルドで +1、繰り上がりなし。

同じスクリプトが `lib/app_version.dart`（生成物であり、手作業で編集されるものではありません——単純な `const` ファイルであり、`package_info_plus` のような新しいランタイム依存関係ではありません）を再生成し、アプリは実行時にこれを読み取って **Settings** 画面に自身のバージョンを表示します。バージョン履歴は [CHANGELOG.md](CHANGELOG.md) を参照してください。

## 📂 リポジトリ構成

```text
HYDRA-UMC-IOS-CONTROL/
├── build.bat, build.sh              # flutter pub get + バージョン加算 + flutter build windows
├── tool/
│   └── bump_version.dart            # build.bat/build.sh が毎回のビルド前に実行するバージョン加算スクリプト（上記バージョン管理を参照）
├── lib/
│   ├── main.dart                    # アプリのエントリポイント、ChangeNotifierProvider + ログインゲート
│   ├── app_version.dart             # 生成物——tool/bump_version.dart によって再生成される、手動編集禁止
│   ├── models/
│   │   ├── server_info.dart         # 発見/接続エントリ——他の 2 つのクライアントの ServerInfo をミラーリング
│   │   └── hydra_state.dart         # RobotView/ControllerView/HydraState——生の settings.json ツリーに対する薄い可変ビュー
│   ├── network/
│   │   ├── hydra_api_client.dart    # REST：ログイン、設定、原子的ロボット指令、システム指標
│   │   ├── hydra_websocket.dart     # /ws リアルタイム同期クライアント
│   │   ├── discovery.dart           # このデバイス自身の実際のローカルサブネットに対する GET /api/hydra-info の並行スキャン
│   │   ├── auth_prefs.dart          # 永続化された接続情報 + トークン（shared_preferences）
│   │   ├── biometric_helper.dart    # package:local_auth の薄いラッパー（Face ID/Touch ID ゲート）
│   │   └── state_cache.dart         # AndroidのStateCache.ktから移植——起動をまたいで永続化される最後の正常状態
│   ├── state/
│   │   ├── robot_view_model.dart    # すべての画面がリッスンする単一の ChangeNotifier
│   │   └── hydra_error.dart         # RobotViewModel向けの型付きエラーサーフェス(独自のBuildContextを持たない)
│   ├── l10n/                        # 実際に生成されたローカライゼーション(7言語) - リポジトリルートのl10n.yamlを参照
│   │   ├── app_localizations.dart   # 生成されたベースクラス
│   │   ├── app_localizations_en.dart, _es.dart, _it.dart, _fr.dart, _de.dart, _ja.dart, _zh.dart
│   │   └── language_prefs.dart      # 永続化された言語上書き設定(shared_preferences)
│   └── ui/
│       ├── login_screen.dart        # ホスト/ポート/ユーザー/パスワードフィールド + 「ローカルネットワークをスキャン」
│       ├── biometric_gate_screen.dart # Face ID/Touch ID保留中にmain.dartの_RootGateが表示
│       ├── main_screen.dart         # ボトムナビゲーションシェル（ダッシュボード/制御/カメラ/3D/設定）
│       ├── dashboard_screen.dart    # ロボットごとのカード + システム指標バー
│       ├── control_screen.dart      # ジョグ/速度/バルブ/ポンプ/再生制御
│       ├── camera_screen.dart       # MJPEG ビューアー + ビジョンオン/オフスイッチ
│       ├── three_d_screen.dart      # WebView 経由で STUDIO 自身の 3D ビューポートを埋め込み
│       ├── telemetry_screen.dart    # AndroidのTelemetryScreen.ktから移植
│       ├── settings_screen.dart     # 接続情報 + サインアウト
│       └── widgets/
│           ├── joystick_pad.dart     # ジョグ方向パッド（意図的にアナログスティックではない、ファイルヘッダー参照）
│           ├── digital_readout.dart, status_led.dart
│           └── mjpeg_view.dart       # 手作りの MJPEG ストリームパーサー
├── ios/                              # Xcode プロジェクト（macOS からのみビルド可能）
├── windows/                          # Windows デスクトップターゲット——Mac なしでのビルド検証
├── docs/ARCHITECTURE.md
├── test/                             # widget_test、websocket_uri_test、format_uptime_test、localization_test、state_cache_test、telemetry_log_test
├── images/
├── README.md                         # 本ファイル
└── README_spa.md / README_ita.md / README_fra.md / README_deu.md / README_zho.md / README_jpn.md  # 翻訳
```

## 🔗 関連プロジェクト

本プロジェクトは、同じ作者(JuanenRac / Electro Hobby 3D)による HYDRA-UMC ロボティクスエコシステムの一部です。リクエストが実はこの中のどれかについてのものである可能性があるため、知っておく価値があります。

**親プロジェクト**
- **[HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER)** — すべての制御クライアントが実際に通信する、本物のヘッドレスバックエンド(REST/WebSocket)。本アプリ自身のログイン、アトミックコマンド、WebSocket 同期がすべてこれに対して動作するバックエンド。

**兄弟プロジェクト** —— それぞれ独自のクライアントとして、同じく HYDRA-UMC-SERVER 自身の API と通信する
- **[HYDRA-UMC-STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO)** — リアルタイムのマルチロボット 3D 可視化を備えたウェブ制御ダッシュボード。その 3D ビューポートは、WebView 経由で本アプリ自身の 3D ビュー画面に直接組み込まれている。
- **[HYDRA-UMC-SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE)** — 複数のサーバーを同時に扱えるデスクトップ(PySide6)スウォームコマンドセンター、スタンドアロン実行ファイルとしてパッケージ化。本アプリとまったく同じ `REMOTE_API.md` 契約を話す。
- **[HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL)** — 生体認証ログインとペアリングされた Wear OS コンパニオンを備えたネイティブ Android 制御アプリ。本アプリとまったく同じ `REMOTE_API.md` 契約を話す。
- **[HYDRA-UMC-DSI](https://github.com/JuanenRac/HYDRA-UMC-DSI)** — 本体搭載の 7 インチ DSI タッチスクリーン向けネイティブタッチ UI、CM5 自体に組み込み。
- **[HYDRA-UMC-BRIDGE-AMR](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-AMR)** — 実際の VDA 5050 MQTT パブリッシャーによる AGV/AMR フリートの調整境界。
- **[HYDRA-UMC-BRIDGE-CNC](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-CNC)** — 実際の GRBL ステータス/制御バイトへのアクセスを持つ、CNC セルの高レベルコーディネーター。
- **[HYDRA-UMC-BRIDGE-DROIDS](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-DROIDS)** — 実際の Boston Dynamics Spot コマンド送信機能を持つ、脚型/ヒューマノイドドロイドの調整境界。
- **[HYDRA-UMC-BRIDGE-LASER](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-LASER)** — 実際のキー/筐体/インターロック GPIO セーフガード 3 系統を読み取る、レーザーセルの安全コーディネーター。
- **[HYDRA-UMC-BRIDGE-OPENPNP](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-OPENPNP)** — OpenPnP ピックアンドプレースの基板フローを安全に統括する高レベルコーディネーター。
- **[HYDRA-UMC-BRIDGE-PRINTER3D](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-PRINTER3D)** — 実際にゲート制御されたジョブコマンドを持つ、Moonraker/Klipper 3D プリンター向けの安全な調整境界。
- **[HYDRA-UMC-BRIDGE-ROS2](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-ROS2)** — 実際の遅延インポート rclpy ROS 2 トランスポートを持つ安全コーディネーター。
- **[HYDRA-UMC-BRIDGE-UAV](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-UAV)** — 実際の MAVLink コマンド送信機能を持つ、カメラ搭載 UAV の調整境界。

**直接関連**
- **[HYDRA-UMC-WATCH](https://github.com/JuanenRac/HYDRA-UMC-WATCH)** — 実際の触覚アラートとペアリングされたスマートフォンへの音声リレーを備えた WearOS コンパニオンアプリ。本アプリの Apple Watch コンパニオンであり、手首から一目で制御・状態確認ができる。
- **[HYDRA-UMC-HIL-BRIDGE](https://github.com/JuanenRac/HYDRA-UMC-HIL-BRIDGE)** — シミュレーションと実際のハードウェアの間でコマンドをルーティングする、実際のハードウェア・イン・ザ・ループ安全インターロック。本アプリからデジタルツインをハードウェア・イン・ザ・ループでリモート制御できるブリッジ。

**エコシステムの他のプロジェクト**

*コアハードウェア&プラットフォーム*
- **[HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC)** — 実際のロボットアームのマザーボード——CM5 ホスト + デュアルコア STM32H745、CAN-OTA/SPI-OTA 経由で最大 8 本のツールアームを統括。
- **[HYDRA-UMC-OS](https://github.com/JuanenRac/HYDRA-UMC-OS)** — CM5 向けの再現可能な Raspberry Pi OS プロダクト層——読み取り専用エージェント、検証済み設定/プロファイル、WiFi 初回接続プロビジョニング。
- **[HYDRA-UMC-SDK](https://github.com/JuanenRac/HYDRA-UMC-SDK)** — すべてのブリッジが自身のコマンドを検証する共有 JSON-Schema 契約と安全ゲートの境界。

*コアバックエンド&クライアント*
- **[HYDRA-UMC-EDITOR-URDF](https://github.com/JuanenRac/HYDRA-UMC-EDITOR-URDF)** — 完成したモデルを STUDIO 自身のカタログへ送信するデスクトップ用グラフィカル URDF 作成/編集ツール。

*URTC ツールプラットフォーム*
- **[URTC](https://github.com/JuanenRac/URTC)** — 物理的な Universal Robot Tool Controller 基板向けファームウェア、CAN バス経由の 25 以上のツールプロファイル。
- **[URTC-FLASHER](https://github.com/JuanenRac/URTC-FLASHER)** — URTC 基板用のデスクトップ GUI 書き込みツール、CAN-OTA およびフルチップ SWD/JTAG。
- **[URTC-TESTER](https://github.com/JuanenRac/URTC-TESTER)** — URTC 基板向けのデスクトップ CAN バスライブ診断ツール、ツールプロファイルごとに 1 パネル。
- **[URTC-WEB-STUDIO](https://github.com/JuanenRac/URTC-WEB-STUDIO)** — Web Serial API を使ったブラウザベースの URTC-TESTER の代替、ローカルインストール不要。

*ビジョン AI ノード(Hailo-8)*
- **[HYDRA-UMC-VISION-NODE](https://github.com/JuanenRac/HYDRA-UMC-VISION-NODE)** — Hailo-8 ビジョンパイプラインの統合ハブ、段階ごとの実際のハードウェア準備状況チェック付き。
- **[HYDRA-UMC-DETECTION-HEF](https://github.com/JuanenRac/HYDRA-UMC-DETECTION-HEF)** — Hailo アーキテクチャ/チェックサムによる安全読み込み検証を備えた、実際のコンパイル済みモデルレジストリ。
- **[HYDRA-UMC-VISION-STREAMER](https://github.com/JuanenRac/HYDRA-UMC-VISION-STREAMER)** — 実際の HailoRT 統合境界を持つ、実際の GStreamer パイプライン + MediaMTX 設定生成器。
- **[HYDRA-UMC-VISUAL-SERVOING-API](https://github.com/JuanenRac/HYDRA-UMC-VISUAL-SERVOING-API)** — 上流のゾーン状態に応じて安全ゲート制御される、実際の Position-Based Visual Servoing 補正則。
- **[HYDRA-UMC-SAFETY-ZONES](https://github.com/JuanenRac/HYDRA-UMC-SAFETY-ZONES)** — キャリブレーションの鮮度を強制する、実際のゾーン侵入チェックと E-STOP 要求。

*コグニティブ AI ノード(Hailo-10)*
- **[HYDRA-UMC-COGNITIVE-NODE](https://github.com/JuanenRac/HYDRA-UMC-COGNITIVE-NODE)** — Hailo-10 コグニティブパイプライン(LLM/VLA/音声オーケストレーション)の統合ハブ。
- **[HYDRA-UMC-VLA-ENGINE](https://github.com/JuanenRac/HYDRA-UMC-VLA-ENGINE)** — Vision-Language-Action モデル向けの、実際のアクショントークンのエンコード/デコードと軌道生成。
- **[HYDRA-UMC-VOICE-UI](https://github.com/JuanenRac/HYDRA-UMC-VOICE-UI)** — 確認ゲート付きの限定的な Watch リレーを備えた、実際の音声フロントエンド(VAD + 意図解析)。
- **[HYDRA-UMC-SEMANTIC-PLANNER](https://github.com/JuanenRac/HYDRA-UMC-SEMANTIC-PLANNER)** — MCU エラーコードに対する、実際のルールベースのタスク分解と意味的エラー復旧。
- **[HYDRA-UMC-DOCS-QA](https://github.com/JuanenRac/HYDRA-UMC-DOCS-QA)** — このエコシステム自身の Markdown ドキュメントに対する、標準ライブラリのみの実際の TF-IDF 文書検索。

*オーケストレーション&スウォーム*
- **[HYDRA-UMC-ORCHESTRATOR](https://github.com/JuanenRac/HYDRA-UMC-ORCHESTRATOR)** — 実際の gRPC/Protobuf ヘルスレポート契約とミッションステートマシンを持つ統合ハブ。
- **[HYDRA-UMC-JOB-DISPATCHER](https://github.com/JuanenRac/HYDRA-UMC-JOB-DISPATCHER)** — 実際の HTTP API 上に構築された、優先度ベースの実際のジョブキュー(重複排除付き)。
- **[HYDRA-UMC-NODE-HEALING](https://github.com/JuanenRac/HYDRA-UMC-NODE-HEALING)** — リトライ/バックオフとアイデンティティ不一致検出を備えた、実際の gRPC ベースのフリートヘルスウォッチドッグ。
- **[HYDRA-UMC-PATH-PLANNER-3D](https://github.com/JuanenRac/HYDRA-UMC-PATH-PLANNER-3D)** — 実際の障害物/ワークスペース衝突検証を備えた、実際の RRT ベースの 3D 経路プランナー。
- **[HYDRA-UMC-SWARM-SYNC](https://github.com/JuanenRac/HYDRA-UMC-SWARM-SYNC)** — 複数セルの収束についてプロパティテストされた、実際の CRDT LWW-Element-Map 状態同期。

*デジタルツイン&シミュレーション*
- **[HYDRA-UMC-TWIN](https://github.com/JuanenRac/HYDRA-UMC-TWIN)** — 実際のバージョン互換性同期契約を持つ、デジタルツインエンジンの統合ハブ。
- **[HYDRA-UMC-PHYSICS-REPLICA](https://github.com/JuanenRac/HYDRA-UMC-PHYSICS-REPLICA)** — 実際の URDF サブセットに対する、実際の順運動学と関節限界検証。
- **[HYDRA-UMC-SYNTHETIC-DATA-GEN](https://github.com/JuanenRac/HYDRA-UMC-SYNTHETIC-DATA-GEN)** — YOLO/COCO アノテーションのエクスポート機能を持つ、実際のプロシージャル 2D シーンジェネレーター。

*データ&分析*
- **[HYDRA-UMC-DATALAKE](https://github.com/JuanenRac/HYDRA-UMC-DATALAKE)** — 実際の取り込み/クエリ HTTP API を備えた、実際の sqlite3 ベースの時系列ストア。
- **[HYDRA-UMC-ANOMALY-DETECTOR](https://github.com/JuanenRac/HYDRA-UMC-ANOMALY-DETECTOR)** — ドリフト監視を備えた、実際の FFT + 統計ベースラインによる異常検知器。
- **[HYDRA-UMC-PRODUCTION-REPORTS](https://github.com/JuanenRac/HYDRA-UMC-PRODUCTION-REPORTS)** — DATALAKE の履歴に対する実際の OEE/稼働率計算、再現可能な CSV エクスポート付き。
- **[HYDRA-UMC-TELEMETRY-COLLECTOR](https://github.com/JuanenRac/HYDRA-UMC-TELEMETRY-COLLECTOR)** — シーケンス重複排除機能を備えた、DATALAKE への実際の CAN/WebSocket 取り込みパイプライン。

*産業用ゲートウェイ*
- **[HYDRA-UMC-GATEWAY-INDUSTRIAL](https://github.com/JuanenRac/HYDRA-UMC-GATEWAY-INDUSTRIAL)** — 実際のコマンド許可リスト/バックプレッシャー層を持つ、産業用プロトコルへ中継する統合ハブ。
- **[HYDRA-UMC-OPCUA-SERVER](https://github.com/JuanenRac/HYDRA-UMC-OPCUA-SERVER)** — 実際のバイナリプロトコルクライアントセッションで検証された、実際の OPC-UA アドレス空間。
- **[HYDRA-UMC-MQTT-BROKER](https://github.com/JuanenRac/HYDRA-UMC-MQTT-BROKER)** — クライアント単位のオプション認証とトピック ACL を備えた、実際の MQTT ブローカー。
- **[HYDRA-UMC-MTCONNECT-ADAPTER](https://github.com/JuanenRac/HYDRA-UMC-MTCONNECT-ADAPTER)** — 縮退モード出力を備えた、実際の MTConnect `/probe` および `/current` XML エンドポイント。

*補完ツール&エコシステム運用*
- **[HYDRA-UMC-DASHBOARD-AI](https://github.com/JuanenRac/HYDRA-UMC-DASHBOARD-AI)** — 誠実な統計フォールバックを備えた、DATALAKE/ANOMALY-DETECTOR 上のスマートサマリーと異常ハイライトパネル。
- **[HYDRA-UMC-TOOL-CLI](https://github.com/JuanenRac/HYDRA-UMC-TOOL-CLI)** — 実際の安定した終了コード契約を持つフリート CLI、HYDRA-UMC-SERVER 自身の API の本物のライブクライアント。
- **[URTC-SMART-RACK](https://github.com/JuanenRac/URTC-SMART-RACK)** — 実際の工具 ID デコードと Smart Idle 予熱ロジックを備えた、基板搭載ラック用ファームウェア。
- **[URTC-VISION-TOOL](https://github.com/JuanenRac/URTC-VISION-TOOL)** — サーマル/RGB 検査ツールヘッド向けの、ファームウェアと実際の Python ビジョンコンパニオン。
- **[HYDRA-UMC-UPDATER](https://github.com/JuanenRac/HYDRA-UMC-UPDATER)** — このエコシステム内のすべてのリポジトリを検出・クローン・更新する、管理用デスクトップツール。
- **[HYDRA-UMC-OS-REBUILDER](https://github.com/JuanenRac/HYDRA-UMC-OS-REBUILDER)** — エコシステムの最新バージョンをプリロードした、書き込み可能なCM5イメージを構築するWindows/Linuxデスクトップツール。Raspberry Pi Imager方式の初回起動Wi-Fi/ユーザー/SSH設定を備える。

---

## 📚 ドキュメント & コミュニティ

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** —— 本アプリが `server.ts` と交わす Wi-Fi トランスポート契約（エンドポイントごと）、Bluetooth パスがまだ存在しない理由、実際の二経路ディスカバリー機構、そして本アプリとエコシステムの他の部分との関係。
- **[CONTRIBUTING.md](CONTRIBUTING.md)** —— プルリクエストのための技術スタックとコーディング指針。
- **[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)** —— このコミュニティで期待される行動規範。
- **[SECURITY.md](SECURITY.md)** —— 脆弱性の報告方法と、このプロジェクトの実際のセキュリティ重点領域。
- **[SUPPORT.md](SUPPORT.md)** —— 質問の投稿先とバグの報告先。
- **[LICENSE.md](LICENSE.md)** —— このプロジェクト自身のライセンス。

## 👤 作者
**JuanenRac** (Electro Hobby 3D)
📧 electrohobby3d@gmail.com
📺 [youtube.com/@electrohobby3d](https://youtube.com/@electrohobby3d)

## 📜 ライセンス

ソースコードは **GNU General Public License v3.0（GPL-3.0）**——[`LICENSE`](LICENSE) を参照してください。

ドキュメント（本 README およびその自身の翻訳版——`README_spa.md`、`README_ita.md`、`README_fra.md`、`README_deu.md`、`README_zho.md`、`README_jpn.md`）は、**クリエイティブ・コモンズ 表示-継承 4.0 国際（CC BY-SA 4.0）** の下で提供されます。全文は https://creativecommons.org/licenses/by-sa/4.0/ を参照してください。
