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
- **7 语言界面**（`lib/l10n/`，标准的 `flutter gen-l10n` 流程）—— 英语、西班牙语、法语、德语、意大利语、日语和中文，与本生态系统的其他客户端保持一致。`设置 > 语言` 中的持久化设置默认跟随系统语言；`RobotViewModel.lastError` 现在是带类型的 `HydraError`，而不是预先格式化好的英文文本，因此业务逻辑层的错误提示（登录/连接/指令失败）也能正确本地化，而不只是界面上的静态文本。
- **离线状态缓存**（`lib/network/state_cache.dart`）—— 最后一次已知的设置树会持久化到磁盘（1 秒防抖），这样在真正的 `connect()` 往返请求仍在进行时，仪表盘/控制界面会立即显示真实（即使可能已过时）的机器人数据，而不是空白状态。一旦真正的数据获取成功，就会被替换。
- **遥测**（`lib/ui/telemetry_screen.dart`）—— 一个终端风格、最新在前的日志，记录真实的连接/登录/指令生命周期事件，最多保留 50 条，并提供清除日志的操作——与 HYDRA-UMC-ANDROID-CONTROL 自身的遥测标签页相同的"Matrix 绿"配色约定。

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
│   │   ├── auth_prefs.dart          # 持久化的连接信息 + 令牌（shared_preferences）
│   │   ├── biometric_helper.dart    # package:local_auth 的轻量封装（Face ID/Touch ID 门禁）
│   │   └── state_cache.dart         # 移植自 Android 自身的 StateCache.kt——跨启动持久化的最后已知良好状态
│   ├── state/
│   │   ├── robot_view_model.dart    # 每个界面都监听的单一 ChangeNotifier
│   │   └── hydra_error.dart         # 面向 RobotViewModel 的类型化错误接口（自身无 BuildContext）
│   ├── l10n/                        # 真实生成的本地化文件（7 种语言）——见仓库根目录的 l10n.yaml
│   │   ├── app_localizations.dart   # 生成的基类
│   │   ├── app_localizations_en.dart, _es.dart, _it.dart, _fr.dart, _de.dart, _ja.dart, _zh.dart
│   │   └── language_prefs.dart      # 持久化的语言覆盖设置（shared_preferences）
│   └── ui/
│       ├── login_screen.dart        # 主机/端口/用户/密码字段 + “扫描本地网络”
│       ├── biometric_gate_screen.dart # Face ID/Touch ID 待处理时由 main.dart 的 _RootGate 显示
│       ├── main_screen.dart         # 底部导航外壳（仪表盘/控制/摄像头/3D/设置）
│       ├── dashboard_screen.dart    # 每机器人卡片 + 系统指标栏
│       ├── control_screen.dart      # 点动/速度/阀门/泵/回放控制
│       ├── camera_screen.dart       # MJPEG 查看器 + 视觉开关
│       ├── three_d_screen.dart      # 通过 WebView 嵌入 STUDIO 自身的 3D 视口
│       ├── telemetry_screen.dart    # 移植自 Android 自身的 TelemetryScreen.kt
│       ├── settings_screen.dart     # 连接信息 + 退出登录
│       └── widgets/
│           ├── joystick_pad.dart     # 点动方向键（刻意不采用模拟摇杆，见文件头部说明）
│           ├── digital_readout.dart, status_led.dart
│           └── mjpeg_view.dart       # 手写的 MJPEG 流解析器
├── ios/                              # Xcode 项目（仅可在 macOS 上构建）
├── windows/                          # Windows 桌面目标——无需 Mac 即可进行构建验证
├── docs/ARCHITECTURE.md
├── test/                             # widget_test、websocket_uri_test、format_uptime_test、localization_test、state_cache_test、telemetry_log_test
├── images/
├── README.md                         # 本文件
└── README_spa.md / README_ita.md / README_fra.md / README_deu.md / README_zho.md / README_jpn.md  # 翻译
```

## 🔗 相关项目

本项目是同一作者(JuanenRac / Electro Hobby 3D)打造的 HYDRA-UMC 机器人生态系统的一部分。值得了解,因为某个请求实际上可能是关于这些项目之一,而非本仓库本身。

**父项目**
- **[HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER)** —— 每个控制客户端真正通信的真实无头后端(REST/WebSocket);本应用自身的登录、原子指令与 WebSocket 同步都基于此后端运行。

**兄弟项目** —— 同样与 HYDRA-UMC-SERVER 自身 API 通信,各自作为独立客户端
- **[HYDRA-UMC-STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO)** —— 具有实时多机器人 3D 可视化的网页控制面板;其自身的 3D 视图通过 WebView 直接嵌入本应用的 3D 视图界面。
- **[HYDRA-UMC-SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE)** —— 面向多台服务器的桌面(PySide6)集群指挥中心,打包为独立可执行文件;与本应用使用完全相同的 `REMOTE_API.md` 契约。
- **[HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL)** —— 具有生物识别登录和配对 Wear OS 伴侣应用的原生 Android 控制应用;与本应用使用完全相同的 `REMOTE_API.md` 契约。
- **[HYDRA-UMC-DSI](https://github.com/JuanenRac/HYDRA-UMC-DSI)** —— 面向机载 7 英寸 DSI 触摸屏的原生触控界面,直接嵌入 CM5 本体。
- **[HYDRA-UMC-BRIDGE-AMR](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-AMR)** —— 通过真实的 VDA 5050 MQTT 发布者为 AGV/AMR 车队提供的协调边界。
- **[HYDRA-UMC-BRIDGE-CNC](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-CNC)** —— 具备真实 GRBL 状态/控制字节访问能力的高层 CNC 单元协调器。
- **[HYDRA-UMC-BRIDGE-DROIDS](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-DROIDS)** —— 面向足式/人形机器人的协调边界,具备真实的 Boston Dynamics Spot 指令发送器。
- **[HYDRA-UMC-BRIDGE-LASER](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-LASER)** —— 读取 3 项真实钥匙/外壳/联锁 GPIO 安全信号的激光单元安全协调器。
- **[HYDRA-UMC-BRIDGE-OPENPNP](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-OPENPNP)** —— 面向 OpenPnP 贴片机板级流程的安全高层协调器。
- **[HYDRA-UMC-BRIDGE-PRINTER3D](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-PRINTER3D)** —— 面向 Moonraker/Klipper 3D 打印机的安全协调边界,具备真实的受控作业指令。
- **[HYDRA-UMC-BRIDGE-ROS2](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-ROS2)** —— 具备真实的惰性导入 rclpy ROS 2 传输层的安全协调器。
- **[HYDRA-UMC-BRIDGE-UAV](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-UAV)** —— 面向搭载摄像头的无人机的协调边界,具备真实的 MAVLink 指令发送器。

**直接相关**
- **[HYDRA-UMC-WATCH](https://github.com/JuanenRac/HYDRA-UMC-WATCH)** —— 具备真实触觉提醒与配对手机语音中继功能的 WearOS 伴侣应用;本应用的 Apple Watch 伴侣,可从手腕一目了然地控制并查看状态。
- **[HYDRA-UMC-HIL-BRIDGE](https://github.com/JuanenRac/HYDRA-UMC-HIL-BRIDGE)** —— 在仿真与真实硬件之间路由指令的真实硬件在环安全联锁;让本应用能够以硬件在环方式远程控制数字孪生的桥接。

**生态系统中的其他项目**

*核心硬件与平台*
- **[HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC)** —— 机器人手臂的真实主板——CM5 主机 + 双核 STM32H745,通过 CAN-OTA/SPI-OTA 协调最多 8 条工具臂。
- **[HYDRA-UMC-OS](https://github.com/JuanenRac/HYDRA-UMC-OS)** —— 面向 CM5 的可复现 Raspberry Pi OS 产品层——只读代理、经过验证的配置/配置文件、WiFi 首次配网。
- **[HYDRA-UMC-SDK](https://github.com/JuanenRac/HYDRA-UMC-SDK)** —— 每个桥接都据此校验自身指令的共享 JSON-Schema 契约与安全门限边界。

*核心后端与客户端*
- **[HYDRA-UMC-EDITOR-URDF](https://github.com/JuanenRac/HYDRA-UMC-EDITOR-URDF)** —— 将完成的模型推送到 STUDIO 自身目录的桌面版图形化 URDF 创建/编辑工具。

*URTC 工具平台*
- **[URTC](https://github.com/JuanenRac/URTC)** —— 面向实体 Universal Robot Tool Controller 板卡的固件,通过 CAN 总线支持 25 种以上工具配置。
- **[URTC-FLASHER](https://github.com/JuanenRac/URTC-FLASHER)** —— 面向 URTC 板卡的桌面图形烧录工具,支持 CAN-OTA 以及全芯片 SWD/JTAG。
- **[URTC-TESTER](https://github.com/JuanenRac/URTC-TESTER)** —— 面向 URTC 板卡的桌面实时 CAN 总线诊断工具,每种工具配置对应一个面板。
- **[URTC-WEB-STUDIO](https://github.com/JuanenRac/URTC-WEB-STUDIO)** —— 通过 Web Serial API 实现的浏览器版 URTC-TESTER 替代方案,无需本地安装。

*视觉 AI 节点(Hailo-8)*
- **[HYDRA-UMC-VISION-NODE](https://github.com/JuanenRac/HYDRA-UMC-VISION-NODE)** —— 面向 Hailo-8 视觉流水线的集成中枢,具备逐阶段的真实硬件就绪检测。
- **[HYDRA-UMC-DETECTION-HEF](https://github.com/JuanenRac/HYDRA-UMC-DETECTION-HEF)** —— 具备 Hailo 架构/校验和安全加载验证的真实编译模型注册表。
- **[HYDRA-UMC-VISION-STREAMER](https://github.com/JuanenRac/HYDRA-UMC-VISION-STREAMER)** —— 具备真实 HailoRT 集成边界的真实 GStreamer 流水线 + MediaMTX 配置生成器。
- **[HYDRA-UMC-VISUAL-SERVOING-API](https://github.com/JuanenRac/HYDRA-UMC-VISUAL-SERVOING-API)** —— 具备真实 Position-Based Visual Servoing 修正律,并依据上游区域状态进行安全门控。
- **[HYDRA-UMC-SAFETY-ZONES](https://github.com/JuanenRac/HYDRA-UMC-SAFETY-ZONES)** —— 具备校准新鲜度强制检查的真实区域入侵检测与 E-STOP 请求。

*认知 AI 节点(Hailo-10)*
- **[HYDRA-UMC-COGNITIVE-NODE](https://github.com/JuanenRac/HYDRA-UMC-COGNITIVE-NODE)** —— 面向 Hailo-10 认知流水线(LLM/VLA/语音编排)的集成中枢。
- **[HYDRA-UMC-VLA-ENGINE](https://github.com/JuanenRac/HYDRA-UMC-VLA-ENGINE)** —— 面向 Vision-Language-Action 模型的真实动作 token 编解码与轨迹生成。
- **[HYDRA-UMC-VOICE-UI](https://github.com/JuanenRac/HYDRA-UMC-VOICE-UI)** —— 具备受限、需确认的 Watch 中继的真实语音前端(VAD + 意图解析)。
- **[HYDRA-UMC-SEMANTIC-PLANNER](https://github.com/JuanenRac/HYDRA-UMC-SEMANTIC-PLANNER)** —— 基于真实规则的任务分解,以及针对 MCU 错误码的语义化错误恢复。
- **[HYDRA-UMC-DOCS-QA](https://github.com/JuanenRac/HYDRA-UMC-DOCS-QA)** —— 面向本生态系统自身 Markdown 文档的真实纯标准库 TF-IDF 文档检索。

*编排与集群*
- **[HYDRA-UMC-ORCHESTRATOR](https://github.com/JuanenRac/HYDRA-UMC-ORCHESTRATOR)** —— 具备真实 gRPC/Protobuf 健康报告契约与任务状态机的集成中枢。
- **[HYDRA-UMC-JOB-DISPATCHER](https://github.com/JuanenRac/HYDRA-UMC-JOB-DISPATCHER)** —— 基于真实 HTTP API 的真实优先级任务队列,支持去重。
- **[HYDRA-UMC-NODE-HEALING](https://github.com/JuanenRac/HYDRA-UMC-NODE-HEALING)** —— 具备重试/退避与身份不匹配检测的真实基于 gRPC 的车队健康看门狗。
- **[HYDRA-UMC-PATH-PLANNER-3D](https://github.com/JuanenRac/HYDRA-UMC-PATH-PLANNER-3D)** —— 具备真实障碍物/工作空间碰撞校验的真实基于 RRT 的三维路径规划器。
- **[HYDRA-UMC-SWARM-SYNC](https://github.com/JuanenRac/HYDRA-UMC-SWARM-SYNC)** —— 经过多单元收敛属性测试的真实 CRDT LWW-Element-Map 状态同步。

*数字孪生与仿真*
- **[HYDRA-UMC-TWIN](https://github.com/JuanenRac/HYDRA-UMC-TWIN)** —— 面向数字孪生引擎的集成中枢,具备真实的版本兼容性同步契约。
- **[HYDRA-UMC-PHYSICS-REPLICA](https://github.com/JuanenRac/HYDRA-UMC-PHYSICS-REPLICA)** —— 面向真实 URDF 子集的真实正向运动学与关节限位校验。
- **[HYDRA-UMC-SYNTHETIC-DATA-GEN](https://github.com/JuanenRac/HYDRA-UMC-SYNTHETIC-DATA-GEN)** —— 具备 YOLO/COCO 标注导出功能的真实程序化 2D 场景生成器。

*数据与分析*
- **[HYDRA-UMC-DATALAKE](https://github.com/JuanenRac/HYDRA-UMC-DATALAKE)** —— 具备真实数据摄入/查询 HTTP API 的真实 sqlite3 时序数据存储。
- **[HYDRA-UMC-ANOMALY-DETECTOR](https://github.com/JuanenRac/HYDRA-UMC-ANOMALY-DETECTOR)** —— 具备漂移监测能力的真实 FFT + 统计基线异常检测器。
- **[HYDRA-UMC-PRODUCTION-REPORTS](https://github.com/JuanenRac/HYDRA-UMC-PRODUCTION-REPORTS)** —— 基于 DATALAKE 历史数据的真实 OEE/可用率计算,支持可复现的 CSV 导出。
- **[HYDRA-UMC-TELEMETRY-COLLECTOR](https://github.com/JuanenRac/HYDRA-UMC-TELEMETRY-COLLECTOR)** —— 面向 DATALAKE 的真实 CAN/WebSocket 数据摄入管道,支持序列去重。

*工业网关*
- **[HYDRA-UMC-GATEWAY-INDUSTRIAL](https://github.com/JuanenRac/HYDRA-UMC-GATEWAY-INDUSTRIAL)** —— 中继至工业协议的集成中枢,具备真实的指令白名单/背压控制层。
- **[HYDRA-UMC-OPCUA-SERVER](https://github.com/JuanenRac/HYDRA-UMC-OPCUA-SERVER)** —— 经真实二进制协议客户端会话验证的真实 OPC-UA 地址空间。
- **[HYDRA-UMC-MQTT-BROKER](https://github.com/JuanenRac/HYDRA-UMC-MQTT-BROKER)** —— 具备可选按客户端认证与主题 ACL 的真实 MQTT 代理。
- **[HYDRA-UMC-MTCONNECT-ADAPTER](https://github.com/JuanenRac/HYDRA-UMC-MTCONNECT-ADAPTER)** —— 具备降级模式输出的真实 MTConnect `/probe` 与 `/current` XML 端点。

*辅助工具与生态系统运维*
- **[HYDRA-UMC-DASHBOARD-AI](https://github.com/JuanenRac/HYDRA-UMC-DASHBOARD-AI)** —— 基于 DATALAKE/ANOMALY-DETECTOR 的智能摘要与异常高亮面板,具备诚实的统计回退机制。
- **[HYDRA-UMC-TOOL-CLI](https://github.com/JuanenRac/HYDRA-UMC-TOOL-CLI)** —— 具备真实、稳定退出码契约的车队 CLI,是 HYDRA-UMC-SERVER 自身 API 的真实在线客户端。
- **[URTC-SMART-RACK](https://github.com/JuanenRac/URTC-SMART-RACK)** —— 面向板卡安装机架的固件,具备真实的工具 ID 解码与 Smart Idle 预热逻辑。
- **[URTC-VISION-TOOL](https://github.com/JuanenRac/URTC-VISION-TOOL)** —— 面向热成像/RGB 检测工具头的固件及真实 Python 视觉伴侣程序。
- **[HYDRA-UMC-UPDATER](https://github.com/JuanenRac/HYDRA-UMC-UPDATER)** —— 发现、克隆并更新本生态系统中每个仓库的管理类桌面工具。

---

## 👤 作者
**JuanenRac** (Electro Hobby 3D)
📧 electrohobby3d@gmail.com
📺 [youtube.com/@electrohobby3d](https://youtube.com/@electrohobby3d)

## 📜 许可证

源代码采用 **GNU 通用公共许可证 v3.0（GPL-3.0）**——见 [`LICENSE`](LICENSE)。

文档（本 README 及其自身的翻译版本——`README_spa.md`、`README_ita.md`、`README_fra.md`、`README_deu.md`、`README_zho.md`、`README_jpn.md`）依据 **知识共享 署名-相同方式共享 4.0 国际许可协议（CC BY-SA 4.0）** 提供。完整文本见 https://creativecommons.org/licenses/by-sa/4.0/。
