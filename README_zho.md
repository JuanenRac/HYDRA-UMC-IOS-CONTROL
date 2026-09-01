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
  🇨🇳 <b>简体中文</b> |
  <a href="README_jpn.md">🇯🇵 日本語</a>
</p>


<p align="left">
  <img src="https://img.shields.io/badge/License-GPL%203.0-blue.svg" alt="GPL 3.0">
  <img src="https://img.shields.io/badge/Framework-Flutter-02569B.svg" alt="Flutter">
  <img src="https://img.shields.io/badge/Language-Dart-0175C2.svg" alt="Dart">
  <img src="https://img.shields.io/badge/Platform-iOS-000000.svg" alt="iOS">
</p>


一款跨平台的 Flutter 应用（Dart），通过 Wi-Fi 控制 [HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC) 平台上的机器人，使用与 [HYDRA-UMC SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE) 和 [HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL) 完全相同的 [`REMOTE_API.md`](https://github.com/JuanenRac/HYDRA-UMC-SERVER/blob/main/docs/REMOTE_API.md) 契约——针对运行中的 [HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER) 实例（从 HYDRA-UMC STUDIO 自身进程中拆分出来的无头式后端——STUDIO 现在是它的一个纯前端客户端，与本应用一样）进行发现、登录、原子化的逐机器人指令,以及实时 WebSocket 同步。

## 🔀 为何选择 Flutter，而非原生 Swift

本应用面向 iOS/iPadOS,但它是用 **Flutter** 而非 Swift/SwiftUI 构建的:本仓库的工作环境仅限 Windows,而一个原生 Swift 项目虽然可以在 Windows 上*编写*,但永远无法在其上*编译或运行*（Xcode 和 iOS SDK 仅限 macOS）。Flutter 自身的 Windows 桌面目标让本应用可以在这台机器上真正地构建、运行和测试——`flutter analyze` 干净通过,`flutter build windows` 成功,`flutter test` 通过,构建出的 `.exe` 能够启动并渲染,没有任何运行时错误——而不是盲目地编写数千行 Swift 代码,在拿到 Mac 之前完全无法验证任何一行。

**这并不能消除苹果自身的限制**——一个真正的 `.ipa` 仍然需要在 Mac 上（或 macOS CI 运行器上）使用 Xcode 来构建和签名;框架的选择并不会改变这一点。Flutter 带来的好处是,能够在这台机器上今天就验证本应用自身逻辑（网络、状态、界面）的每一行代码,并在日后无需重写就能将完全相同的代码库发布到 iOS。

## 🏗️ 已实现的功能

- **登录**（`lib/ui/login_screen.dart`、`lib/state/robot_view_model.dart`）—— 可编辑的服务器 IP/端口和操作员凭据字段，加上 `POST /api/login`；不会预填账户或密码。生产服务器必须为首个管理员显式配置引导凭据；可在浏览器界面的 Config > Users 中创建额外的低权限“操作员”账户。会话令牌通过 `shared_preferences` 在多次启动之间持久化。“扫描本地网络”按钮（`lib/network/discovery.dart`）无需用户预先知道 IP 即可找到服务器。
- **网络发现**（`lib/network/discovery.dart`）—— 针对本设备自身真实本地子网的并发扫描 `GET /api/hydra-info`,该子网通过 `dart:io` 的 `NetworkInterface.list()` 推导,而非单一的硬编码猜测,因为手机的局域网同样可能是 `192.168.0.x` 或 `10.x.x.x`,而不一定是 `192.168.1.x`。仅当接口枚举本身返回为空时,才回退到 `192.168.1.x`。
- **原子化指令同步**（`lib/state/robot_view_model.dart` 自身的 `_sendAtomicCommand()`）—— 每一次写入（启用/禁用/播放/暂停/停止/点动/阀门/泵/速度/视觉）都使用真实的 `POST /api/robot/:id/command` 端点,发送一个小型的定向负载,而非覆盖整棵设置树,并对需要它的 5 种指令进行正确的合并机器人（`combinedWith`）传播。
- **实时 WebSocket 同步**（`lib/network/hydra_websocket.dart`）—— 始终在连接 URL 中附加 `?token=`（`server.ts` 自身的 `/ws` 升级请求无条件地要求它）,同时处理 `"settings"` 和 `"delta"` 两种广播类型,断线后自动重连。
- **仪表盘**（`lib/ui/dashboard_screen.dart`）—— 每机器人卡片,通过 `Provider` 自身的 `ChangeNotifier` 实时响应,LED 惯例（绿色脉冲=活动,红色常亮=非活动）,以及合并机器人显示（仅在从属方一侧显示,按 id 解析）,与 HYDRA-UMC-STUDIO 自身的仪表盘概览一致。
- **手动控制**（`lib/ui/control_screen.dart`、`lib/ui/widgets/joystick_pad.dart`）—— 点动方向键（带/不带 XY 工作台目标）、速度/加速度滑块、阀门/泵开关,以及紧急停止/停止按钮上真实的长按保护（快速轻触不会产生任何效果,只有触感反馈+视觉提示,只有真正的长按才会发送指令）。
- **摄像头**（`lib/ui/camera_screen.dart`、`lib/ui/widgets/mjpeg_view.dart`）—— 一个小型的手写 MJPEG 流解析器（无第三方包）,一个明确的“摄像头已禁用”状态（而非静默显示空白画面）,以及一个可直接从服务器打开/关闭机器人视觉系统的开关（`server.ts` 的 `"vision"` 原子指令）。
- **3D 视图**（`lib/ui/three_d_screen.dart`）—— 通过 WebView 嵌入 HYDRA-UMC-STUDIO 自身的实时 3D 视口（`?hideUI=true&robotId=&token=`）,与 Android 应用的方式相同,原因也相同（免费获得真实的、当前正在使用的 3D 场景）。在 `webview_flutter` 不支持的平台（本仓库用于构建验证的 Windows 桌面目标）上,会回退到一个诚实的占位符。
- **系统指标**（`lib/state/robot_view_model.dart`）—— 每 5 秒轮询一次 `GET /api/system/metrics`,与其他 2 个客户端的节奏相同,显示在仪表盘中。

## 🚀 构建

需要 [Flutter SDK](https://docs.flutter.dev/get-started/install)（stable 渠道）。本仓库基于 Flutter 3.47.0 构建/验证。本仓库中只配置了 `windows/` 和 `ios/` 两个平台（没有 `android/`、`linux/`、`web/` 或 `macos/` 文件夹）——Windows 的存在是为了让本应用自身的逻辑能够在没有 Mac 的情况下构建和运行;iOS 才是真正的目标平台。

### 构建脚本

```bash
./build.sh     # Git Bash / WSL —— flutter pub get + 版本递增 + flutter build windows
build.bat      # cmd.exe / PowerShell —— flutter pub get + 版本递增 + flutter build windows
```

两者都会生成 `build/windows/x64/runner/Release/hydra_umc_control.exe`,并且都会先递增应用的版本号——见下文[版本管理](#-版本管理)。

### 手动构建

```bash
flutter pub get
flutter analyze          # 静态分析——无需编译器
flutter test             # 组件测试
dart run tool/bump_version.dart  # 递增版本号，与 build.sh/build.bat 所做的相同
flutter build windows    # 生成 build/windows/x64/runner/Release/hydra_umc_control.exe
flutter run -d windows   # 或在 Mac 上使用 -d <ios-device-id>，或使用 -d chrome 进行快速网页预览
```

**构建真正的 iOS `.ipa`** 需要在 macOS 上使用 Xcode——在该机器上运行：`flutter build ipa`（或直接在 Xcode 中打开 `ios/Runner.xcworkspace`）。这无法在 Windows 上完成；见上文“为何选择 Flutter，而非原生 Swift”。

## 🔢 版本管理

本仓库遵循一项全生态系统统一的策略：版本号在**每次真正的构建**时自动递增,无需手动编辑 `pubspec.yaml` 的 `version:` 行。`build.sh`/`build.bat` 会在调用 `flutter build` 之前运行 `tool/bump_version.dart`,应用以下规则：

- **Patch,里程表方式（十进制）：** 每次构建 +1;一旦超过 9 就重置为 0,并将 minor 加 1——例如 `0.0.9` -> `0.1.0`。Major 从不被自动修改。
- **构建号**（`+` 之后的部分）：一个纯粹的单调计数器,每次构建 +1,不进位。

同一个脚本会重新生成 `lib/app_version.dart`（这是生成的文件,不是手工编辑的——一个普通的 `const` 文件,而非像 `package_info_plus` 那样引入新的运行时依赖）,应用在运行时读取它,以在 **Settings** 界面显示自身版本。完整版本历史见 [CHANGELOG.md](CHANGELOG.md)。

## 📂 仓库结构

```text
HYDRA-UMC-IOS-CONTROL/
├── build.bat, build.sh              # flutter pub get + 版本递增 + flutter build windows
├── tool/
│   └── bump_version.dart            # build.bat/build.sh 在每次构建前运行的版本递增脚本（见上文版本管理）
├── lib/
│   ├── main.dart                    # 应用入口点，ChangeNotifierProvider + 登录门禁
│   ├── app_version.dart             # 生成文件——由 tool/bump_version.dart 重新生成，请勿手动编辑
│   ├── models/
│   │   ├── server_info.dart         # 发现/连接条目——与其他 2 个客户端中的 ServerInfo 镜像一致
│   │   └── hydra_state.dart         # RobotView/ControllerView/HydraState——原始 settings.json 树的薄型可变视图
│   ├── network/
│   │   ├── hydra_api_client.dart    # REST：登录、设置、原子化机器人指令、系统指标
│   │   ├── hydra_websocket.dart     # /ws 实时同步客户端
│   │   ├── discovery.dart           # 针对本设备自身真实本地子网的并发扫描 GET /api/hydra-info
│   │   └── auth_prefs.dart          # 持久化的连接信息 + 令牌（shared_preferences）
│   ├── state/
│   │   └── robot_view_model.dart    # 每个界面都监听的单一 ChangeNotifier
│   └── ui/
│       ├── login_screen.dart        # 主机/端口/用户/密码字段 + “扫描本地网络”
│       ├── main_screen.dart         # 底部导航外壳（仪表盘/控制/摄像头/3D/设置）
│       ├── dashboard_screen.dart    # 每机器人卡片 + 系统指标栏
│       ├── control_screen.dart      # 点动/速度/阀门/泵/回放控制
│       ├── camera_screen.dart       # MJPEG 查看器 + 视觉开关
│       ├── three_d_screen.dart      # 通过 WebView 嵌入 STUDIO 自身的 3D 视口
│       ├── settings_screen.dart     # 连接信息 + 退出登录
│       └── widgets/
│           ├── joystick_pad.dart     # 点动方向键（刻意不采用模拟摇杆，见文件头部说明）
│           ├── digital_readout.dart, status_led.dart
│           └── mjpeg_view.dart       # 手写的 MJPEG 流解析器
├── ios/                              # Xcode 项目（仅可在 macOS 上构建）
├── windows/                          # Windows 桌面目标——无需 Mac 即可进行构建验证
├── docs/ARCHITECTURE.md
├── test/widget_test.dart, websocket_uri_test.dart  # 启动与不透明令牌 URL 编码
├── images/
├── README.md                         # 本文件
└── README_spa.md / README_ita.md / README_fra.md / README_deu.md / README_zho.md / README_jpn.md  # 翻译
```

## 🔗 相关项目

本项目是同一作者（JuanenRac / Electro Hobby 3D）打造的更大规模机器人生态系统的一部分，由众多项目组成。值得了解，因为某个请求实际所指的可能正是这些项目之一，而非本仓库。

**与本应用直接相关**
- **[HYDRA-UMC-WATCH](https://github.com/JuanenRac/HYDRA-UMC-WATCH)** — 本应用的 Apple Watch 配套设备，用于从手腕一目了然地进行控制和查看状态。
- **[HYDRA-UMC-HIL-BRIDGE](https://github.com/JuanenRac/HYDRA-UMC-HIL-BRIDGE)** — 让本应用能够以硬件在环方式远程控制数字孪生的桥接组件。

**生态系统的其余部分**

💠 *核心生态系统*：[HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC) · [HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER) · [HYDRA-UMC-STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO) · [HYDRA-UMC-SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE) · [HYDRA-UMC-DSI](https://github.com/JuanenRac/HYDRA-UMC-DSI) · [HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL) · [HYDRA-UMC-EDITOR-URDF](https://github.com/JuanenRac/HYDRA-UMC-EDITOR-URDF) · [URTC](https://github.com/JuanenRac/URTC) · [URTC-FLASHER](https://github.com/JuanenRac/URTC-FLASHER) · [URTC-TESTER](https://github.com/JuanenRac/URTC-TESTER) · [URTC-WEB-STUDIO](https://github.com/JuanenRac/URTC-WEB-STUDIO)

👁️ *Vision AI Node (Hailo-8)*：[HYDRA-UMC-VISION-NODE](https://github.com/JuanenRac/HYDRA-UMC-VISION-NODE) · [HYDRA-UMC-VISION-STREAMER](https://github.com/JuanenRac/HYDRA-UMC-VISION-STREAMER) · [HYDRA-UMC-DETECTION-HEF](https://github.com/JuanenRac/HYDRA-UMC-DETECTION-HEF) · [HYDRA-UMC-SAFETY-ZONES](https://github.com/JuanenRac/HYDRA-UMC-SAFETY-ZONES) · [HYDRA-UMC-VISUAL-SERVOING-API](https://github.com/JuanenRac/HYDRA-UMC-VISUAL-SERVOING-API)

🧠 *Cognitive AI Node (Hailo-10)*：[HYDRA-UMC-COGNITIVE-NODE](https://github.com/JuanenRac/HYDRA-UMC-COGNITIVE-NODE) · [HYDRA-UMC-VLA-ENGINE](https://github.com/JuanenRac/HYDRA-UMC-VLA-ENGINE) · [HYDRA-UMC-VOICE-UI](https://github.com/JuanenRac/HYDRA-UMC-VOICE-UI) · [HYDRA-UMC-SEMANTIC-PLANNER](https://github.com/JuanenRac/HYDRA-UMC-SEMANTIC-PLANNER) · [HYDRA-UMC-DOCS-QA](https://github.com/JuanenRac/HYDRA-UMC-DOCS-QA)

🐝 *Orchestration & Swarm*：[HYDRA-UMC-ORCHESTRATOR](https://github.com/JuanenRac/HYDRA-UMC-ORCHESTRATOR) · [HYDRA-UMC-SWARM-SYNC](https://github.com/JuanenRac/HYDRA-UMC-SWARM-SYNC) · [HYDRA-UMC-PATH-PLANNER-3D](https://github.com/JuanenRac/HYDRA-UMC-PATH-PLANNER-3D) · [HYDRA-UMC-JOB-DISPATCHER](https://github.com/JuanenRac/HYDRA-UMC-JOB-DISPATCHER) · [HYDRA-UMC-NODE-HEALING](https://github.com/JuanenRac/HYDRA-UMC-NODE-HEALING)

🎮 *Digital Twin & Simulation*：[HYDRA-UMC-TWIN](https://github.com/JuanenRac/HYDRA-UMC-TWIN) · [HYDRA-UMC-PHYSICS-REPLICA](https://github.com/JuanenRac/HYDRA-UMC-PHYSICS-REPLICA) · [HYDRA-UMC-SYNTHETIC-DATA-GEN](https://github.com/JuanenRac/HYDRA-UMC-SYNTHETIC-DATA-GEN)

📊 *Data & Analytics*：[HYDRA-UMC-DATALAKE](https://github.com/JuanenRac/HYDRA-UMC-DATALAKE) · [HYDRA-UMC-TELEMETRY-COLLECTOR](https://github.com/JuanenRac/HYDRA-UMC-TELEMETRY-COLLECTOR) · [HYDRA-UMC-ANOMALY-DETECTOR](https://github.com/JuanenRac/HYDRA-UMC-ANOMALY-DETECTOR) · [HYDRA-UMC-PRODUCTION-REPORTS](https://github.com/JuanenRac/HYDRA-UMC-PRODUCTION-REPORTS)

🏭 *Industrial Gateway*：[HYDRA-UMC-GATEWAY-INDUSTRIAL](https://github.com/JuanenRac/HYDRA-UMC-GATEWAY-INDUSTRIAL) · [HYDRA-UMC-OPCUA-SERVER](https://github.com/JuanenRac/HYDRA-UMC-OPCUA-SERVER) · [HYDRA-UMC-MQTT-BROKER](https://github.com/JuanenRac/HYDRA-UMC-MQTT-BROKER) · [HYDRA-UMC-MTCONNECT-ADAPTER](https://github.com/JuanenRac/HYDRA-UMC-MTCONNECT-ADAPTER)

🛠️ *Complementary Tools*：[URTC-SMART-RACK](https://github.com/JuanenRac/URTC-SMART-RACK) · [URTC-VISION-TOOL](https://github.com/JuanenRac/URTC-VISION-TOOL) · [HYDRA-UMC-TOOL-CLI](https://github.com/JuanenRac/HYDRA-UMC-TOOL-CLI) · [HYDRA-UMC-DASHBOARD-AI](https://github.com/JuanenRac/HYDRA-UMC-DASHBOARD-AI)

---

## 👤 作者

**JuanenRac**（Electro Hobby 3D）
📧 electrohobby3d@gmail.com
📺 youtube.com/@electrohobby3d

---

## 📜 许可证

源代码采用 **GNU 通用公共许可证 v3.0（GPL-3.0）**——见 [`LICENSE`](LICENSE)。

文档（本 README 及其自身的翻译版本——`README_spa.md`、`README_ita.md`、`README_fra.md`、`README_deu.md`、`README_zho.md`、`README_jpn.md`）依据 **知识共享 署名-相同方式共享 4.0 国际许可协议（CC BY-SA 4.0）** 提供。完整文本见 https://creativecommons.org/licenses/by-sa/4.0/。
