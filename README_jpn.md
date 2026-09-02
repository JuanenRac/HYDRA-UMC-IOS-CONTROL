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
- **ネットワークディスカバリー**（`lib/network/discovery.dart`）—— このデバイス自身の実際のローカルサブネットに対する `GET /api/hydra-info` の並行スキャン。単一のハードコードされた推測ではなく `dart:io` の `NetworkInterface.list()` から導出されます。スマートフォンの LAN は `192.168.1.x` と同じくらい `192.168.0.x` や `10.x.x.x` である可能性があるためです。インターフェースの列挙自体が空を返した場合にのみ、`192.168.1.x` にフォールバックします。
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
│   │   └── auth_prefs.dart          # 永続化された接続情報 + トークン（shared_preferences）
│   ├── state/
│   │   └── robot_view_model.dart    # すべての画面がリッスンする単一の ChangeNotifier
│   └── ui/
│       ├── login_screen.dart        # ホスト/ポート/ユーザー/パスワードフィールド + 「ローカルネットワークをスキャン」
│       ├── main_screen.dart         # ボトムナビゲーションシェル（ダッシュボード/制御/カメラ/3D/設定）
│       ├── dashboard_screen.dart    # ロボットごとのカード + システム指標バー
│       ├── control_screen.dart      # ジョグ/速度/バルブ/ポンプ/再生制御
│       ├── camera_screen.dart       # MJPEG ビューアー + ビジョンオン/オフスイッチ
│       ├── three_d_screen.dart      # WebView 経由で STUDIO 自身の 3D ビューポートを埋め込み
│       ├── settings_screen.dart     # 接続情報 + サインアウト
│       └── widgets/
│           ├── joystick_pad.dart     # ジョグ方向パッド（意図的にアナログスティックではない、ファイルヘッダー参照）
│           ├── digital_readout.dart, status_led.dart
│           └── mjpeg_view.dart       # 手作りの MJPEG ストリームパーサー
├── ios/                              # Xcode プロジェクト（macOS からのみビルド可能）
├── windows/                          # Windows デスクトップターゲット——Mac なしでのビルド検証
├── docs/ARCHITECTURE.md
├── test/widget_test.dart, websocket_uri_test.dart  # 起動と不透明トークンの URL エンコード
├── images/
├── README.md                         # 本ファイル
└── README_spa.md / README_ita.md / README_fra.md / README_deu.md / README_zho.md / README_jpn.md  # 翻訳
```

## 🔗 関連プロジェクト

本プロジェクトは、同一著者（JuanenRac / Electro Hobby 3D）による、多数のプロジェクトからなる、より大きなロボティクスエコシステムの一部です。ご要望が実際にはこれらのプロジェクトのいずれかに関するものであり、本リポジトリのものではない可能性もあるため、知っておく価値があります。

**本アプリと直接関連**
- **[HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER)** —— 本アプリのログイン、アトミックコマンド、WebSocket同期のすべてが対して動作するバックエンド。
- **[HYDRA-UMC-STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO)** —— その実際のリアルタイム3Dビューポートは、WebView経由で本アプリ自身の3Dビュー画面に直接埋め込まれています。
- **[HYDRA-UMC-SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE)** / **[HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL)** —— 本アプリと全く同じ `REMOTE_API.md` 契約を話す兄弟クライアント。
- **[HYDRA-UMC-WATCH](https://github.com/JuanenRac/HYDRA-UMC-WATCH)** — 本アプリの Apple Watch 版連携デバイスで、手首から一目で制御と状態確認ができます。
- **[HYDRA-UMC-HIL-BRIDGE](https://github.com/JuanenRac/HYDRA-UMC-HIL-BRIDGE)** — 本アプリがハードウェアインザループでデジタルツインをリモート制御できるようにするブリッジです。

**エコシステムのその他のプロジェクト**

💠 *コアエコシステム*：[HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC) · [HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER) · [HYDRA-UMC-STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO) · [HYDRA-UMC-SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE) · [HYDRA-UMC-DSI](https://github.com/JuanenRac/HYDRA-UMC-DSI) · [HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL) · [HYDRA-UMC-EDITOR-URDF](https://github.com/JuanenRac/HYDRA-UMC-EDITOR-URDF) · [URTC](https://github.com/JuanenRac/URTC) · [URTC-FLASHER](https://github.com/JuanenRac/URTC-FLASHER) · [URTC-TESTER](https://github.com/JuanenRac/URTC-TESTER) · [URTC-WEB-STUDIO](https://github.com/JuanenRac/URTC-WEB-STUDIO)

👁️ *ビジョン AI ノード（Hailo-8）*：[HYDRA-UMC-VISION-NODE](https://github.com/JuanenRac/HYDRA-UMC-VISION-NODE) · [HYDRA-UMC-VISION-STREAMER](https://github.com/JuanenRac/HYDRA-UMC-VISION-STREAMER) · [HYDRA-UMC-DETECTION-HEF](https://github.com/JuanenRac/HYDRA-UMC-DETECTION-HEF) · [HYDRA-UMC-SAFETY-ZONES](https://github.com/JuanenRac/HYDRA-UMC-SAFETY-ZONES) · [HYDRA-UMC-VISUAL-SERVOING-API](https://github.com/JuanenRac/HYDRA-UMC-VISUAL-SERVOING-API)

🧠 *認知 AI ノード（Hailo-10）*：[HYDRA-UMC-COGNITIVE-NODE](https://github.com/JuanenRac/HYDRA-UMC-COGNITIVE-NODE) · [HYDRA-UMC-VLA-ENGINE](https://github.com/JuanenRac/HYDRA-UMC-VLA-ENGINE) · [HYDRA-UMC-VOICE-UI](https://github.com/JuanenRac/HYDRA-UMC-VOICE-UI) · [HYDRA-UMC-SEMANTIC-PLANNER](https://github.com/JuanenRac/HYDRA-UMC-SEMANTIC-PLANNER) · [HYDRA-UMC-DOCS-QA](https://github.com/JuanenRac/HYDRA-UMC-DOCS-QA)

🐝 *オーケストレーションと群制御*：[HYDRA-UMC-ORCHESTRATOR](https://github.com/JuanenRac/HYDRA-UMC-ORCHESTRATOR) · [HYDRA-UMC-SWARM-SYNC](https://github.com/JuanenRac/HYDRA-UMC-SWARM-SYNC) · [HYDRA-UMC-PATH-PLANNER-3D](https://github.com/JuanenRac/HYDRA-UMC-PATH-PLANNER-3D) · [HYDRA-UMC-JOB-DISPATCHER](https://github.com/JuanenRac/HYDRA-UMC-JOB-DISPATCHER) · [HYDRA-UMC-NODE-HEALING](https://github.com/JuanenRac/HYDRA-UMC-NODE-HEALING)

🎮 *デジタルツインとシミュレーション*：[HYDRA-UMC-TWIN](https://github.com/JuanenRac/HYDRA-UMC-TWIN) · [HYDRA-UMC-PHYSICS-REPLICA](https://github.com/JuanenRac/HYDRA-UMC-PHYSICS-REPLICA) · [HYDRA-UMC-SYNTHETIC-DATA-GEN](https://github.com/JuanenRac/HYDRA-UMC-SYNTHETIC-DATA-GEN)

📊 *データと分析*：[HYDRA-UMC-DATALAKE](https://github.com/JuanenRac/HYDRA-UMC-DATALAKE) · [HYDRA-UMC-TELEMETRY-COLLECTOR](https://github.com/JuanenRac/HYDRA-UMC-TELEMETRY-COLLECTOR) · [HYDRA-UMC-ANOMALY-DETECTOR](https://github.com/JuanenRac/HYDRA-UMC-ANOMALY-DETECTOR) · [HYDRA-UMC-PRODUCTION-REPORTS](https://github.com/JuanenRac/HYDRA-UMC-PRODUCTION-REPORTS)

🏭 *産業用ゲートウェイ*：[HYDRA-UMC-GATEWAY-INDUSTRIAL](https://github.com/JuanenRac/HYDRA-UMC-GATEWAY-INDUSTRIAL) · [HYDRA-UMC-OPCUA-SERVER](https://github.com/JuanenRac/HYDRA-UMC-OPCUA-SERVER) · [HYDRA-UMC-MQTT-BROKER](https://github.com/JuanenRac/HYDRA-UMC-MQTT-BROKER) · [HYDRA-UMC-MTCONNECT-ADAPTER](https://github.com/JuanenRac/HYDRA-UMC-MTCONNECT-ADAPTER)

🛠️ *補完ツール*：[URTC-SMART-RACK](https://github.com/JuanenRac/URTC-SMART-RACK) · [URTC-VISION-TOOL](https://github.com/JuanenRac/URTC-VISION-TOOL) · [HYDRA-UMC-TOOL-CLI](https://github.com/JuanenRac/HYDRA-UMC-TOOL-CLI) · [HYDRA-UMC-DASHBOARD-AI](https://github.com/JuanenRac/HYDRA-UMC-DASHBOARD-AI)

---

## 👤 作者
**JuanenRac** (Electro Hobby 3D)
📧 electrohobby3d@gmail.com
📺 [youtube.com/@electrohobby3d](https://youtube.com/@electrohobby3d)

## 📜 ライセンス

ソースコードは **GNU General Public License v3.0（GPL-3.0）**——[`LICENSE`](LICENSE) を参照してください。

ドキュメント（本 README およびその自身の翻訳版——`README_spa.md`、`README_ita.md`、`README_fra.md`、`README_deu.md`、`README_zho.md`、`README_jpn.md`）は、**クリエイティブ・コモンズ 表示-継承 4.0 国際（CC BY-SA 4.0）** の下で提供されます。全文は https://creativecommons.org/licenses/by-sa/4.0/ を参照してください。
