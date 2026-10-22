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
  <a href="README_jpn.md">🇯🇵 日本語</a> |
  <a href="README_por.md">🇵🇹 Português</a>
</p>


<p align="center">
  <img src="https://img.shields.io/badge/License-GPL%203.0--or--later-blue.svg" alt="GPL 3.0 or later">
  <img src="https://img.shields.io/badge/Framework-Flutter-02569B.svg" alt="Flutter">
  <img src="https://img.shields.io/badge/Language-Dart-0175C2.svg" alt="Dart">
  <img src="https://img.shields.io/badge/Platform-iOS-000000.svg" alt="iOS">
</p>


一款跨平台的 Flutter 应用（Dart），通过 Wi-Fi 控制 [HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC) 平台上的机器人，使用与 [HYDRA-UMC SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE) 和 [HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL) 完全相同的 [`REMOTE_API.md`](https://github.com/JuanenRac/HYDRA-UMC-SERVER/blob/main/docs/REMOTE_API.md) 契约——针对运行中的 [HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER) 实例（从 HYDRA-UMC STUDIO 自身进程中拆分出来的无头式后端——STUDIO 现在是它的一个纯前端客户端，与本应用一样）进行发现、登录、原子化的逐机器人指令,以及实时 WebSocket 同步。

> **安全与安防现状:**本生态系统不是经认证的安全系统。目前尚无硬件 E-STOP 通路,没有由固件强制执行的限位或联锁,也没有经过验证的运动指令;固件映像使用 CRC32 和共享密钥的 HMAC-SHA256 校验,而非非对称签名;TLS 与双向 TLS 均为可选项,默认关闭;自制电路板尚未组装或测试。在依赖此处任何说法来保障人身安全之前,请先阅读[安全基线](https://github.com/JuanenRac/HYDRA-UMC-DOCS/blob/main/docs/SECURITY_BASELINE.md)和[威胁模型](https://github.com/JuanenRac/HYDRA-UMC-DOCS/blob/main/docs/THREAT_MODEL.md)。

## 📋 速览

| | |
|---|---|
| 版本 | `0.2.6` |
| 成熟度 | 可用 |
| 技术栈 | Flutter 3.x / Dart |
| 目标 | iPhone 或 iPad |
| 真实硬件 | 尚未：此版本没有在真实硬件上运行的记录 |

## 🔀 为何选择 Flutter，而非原生 Swift

本应用面向 iOS/iPadOS,但它是用 **Flutter** 而非 Swift/SwiftUI 构建的:本仓库的工作环境仅限 Windows,而一个原生 Swift 项目虽然可以在 Windows 上*编写*,但永远无法在其上*编译或运行*（Xcode 和 iOS SDK 仅限 macOS）。Flutter 自身的 Windows 桌面目标让本应用可以在这台机器上真正地构建、运行和测试——`flutter analyze` 干净通过,`flutter build windows` 成功,`flutter test` 通过,构建出的 `.exe` 能够启动并渲染,没有任何运行时错误——而不是盲目地编写数千行 Swift 代码,在拿到 Mac 之前完全无法验证任何一行。

**这并不能消除苹果自身的限制**——一个真正的 `.ipa` 仍然需要在 Mac 上（或 macOS CI 运行器上）使用 Xcode 来构建和签名;框架的选择并不会改变这一点。Flutter 带来的好处是,能够在这台机器上今天就验证本应用自身逻辑（网络、状态、界面）的每一行代码,并在日后无需重写就能将完全相同的代码库发布到 iOS。

## 🏗️ 已实现的功能

- **登录**（`lib/ui/login_screen.dart`、`lib/state/robot_view_model.dart`）—— 可编辑的服务器 IP/端口和操作员凭据字段，加上 `POST /api/login`；不会预填账户或密码。生产服务器必须为首个管理员显式配置引导凭据；可在浏览器界面的 Config > Users 中创建额外的低权限“操作员”账户。会话令牌保存在 iOS 钥匙串（`flutter_secure_storage`）中并在多次启动之间保持；主机和端口则保存在 `shared_preferences`。“扫描本地网络”按钮（`lib/network/discovery.dart`）无需用户预先知道 IP 即可找到服务器。
- **网络发现**（`lib/network/discovery.dart`）—— 从同一个“扫描本地网络”面板同时运行两条独立路径：真实的 mDNS/Bonjour（`discoverMdns()`，通过 `multicast_dns` 包查询 `server.ts` 发布的 `_hydra._tcp.local` 服务——本应用是本生态系统 3 个远程客户端中第一个加入该能力的）,以及针对本设备自身真实本地子网的并发暴力扫描 `GET /api/hydra-info`（`scanSubnets()`，该子网通过 `dart:io` 的 `NetworkInterface.list()` 推导,而非单一的硬编码猜测,因为手机的局域网同样可能是 `192.168.0.x` 或 `10.x.x.x`,而不一定是 `192.168.1.x`,仅当接口枚举本身返回为空时才回退到 `192.168.1.x`）。在未获得相应权限的 iOS 构建上，mDNS 静默失败是预期行为（Apple 的 Multicast Networking 权限并非普通 `flutter build ios` 就能获得）——无论如何，子网扫描都会独立继续工作。
- **生物识别登录锁**（`lib/network/biometric_helper.dart`、`lib/ui/biometric_gate_screen.dart`）—— 通过 `package:local_auth` 实现的 Face ID/Touch ID/Windows Hello，`Settings` 中的一个可选开关，用于在启动时保护已保存有效会话的恢复过程（本应用从不保存明文密码，只保存令牌——相较 HYDRA-UMC-ANDROID-CONTROL 自身的密码重填设计，针对这一差异做了适配）。
- **原子化指令同步**（`lib/state/robot_view_model.dart` 自身的 `_sendAtomicCommand()`）—— 每一次写入（播放/暂停/停止/点动/阀门/泵/速度/视觉）都使用真实的 `POST /api/robot/:id/command` 端点,发送一个小型的定向负载,而非覆盖整棵设置树,并对需要它的 5 种指令进行正确的合并机器人（`combinedWith`）传播。
- **实时 WebSocket 同步**（`lib/network/hydra_websocket.dart`）—— 以 `hydra.bearer` 子协议发送令牌，从不放入连接 URL（`server.ts` 默认拒绝 `/ws?token=`），同时处理 `"settings"` 和 `"delta"` 两种广播类型,断线后自动重连。
- **仪表盘**（`lib/ui/dashboard_screen.dart`）—— 每机器人卡片,通过 `Provider` 自身的 `ChangeNotifier` 实时响应,LED 惯例（绿色脉冲=活动,红色常亮=非活动）,以及合并机器人显示（仅在从属方一侧显示,按 id 解析）,与 HYDRA-UMC-STUDIO 自身的仪表盘概览一致。
- **手动控制**（`lib/ui/control_screen.dart`、`lib/ui/widgets/joystick_pad.dart`）—— 点动方向键（带/不带 XY 工作台目标）、速度/加速度滑块、阀门/泵开关,以及全局 **STOP**（`lib/ui/widgets/stop_all.dart`）：只需轻触一次，无需长按也无需确认，即可停止所有机器人（`POST /api/stop-all`），并固定显示在每个标签页（包括控制标签页）的顶部栏中。结果按机器人逐个显示（有机器人失败或停止未保存时给出警告，被其他账户预约的机器人会被标出），网络错误会重试一次，超出请求限制或没有该路由的服务器则改用逐个机器人停止，若无人应答，则会一直显示“STOP 未确认”横幅，直到之后的某次 STOP 得到应答。圆形的单机器人停止按钮保留长按保护。
- **可选开关** - 两个开关，默认均为关闭：*显示已保存数据时禁止发送指令*（设置）会在屏幕显示的是机器人状态的已保存副本而非实时状态时，拦截除停止以外的所有指令；*不扫描移动数据网络和VPN*（登录界面）会在子网扫描中排除这些网络接口。点动方向键按钮至少 44 pt，VoiceOver 会读出其轴和方向；应用处于后台时，摄像头画面会被关闭。
- **摄像头**（`lib/ui/camera_screen.dart`、`lib/ui/widgets/mjpeg_view.dart`）—— 一个小型的手写 MJPEG 流解析器（无第三方包）,一个明确的“摄像头已禁用”状态（而非静默显示空白画面）,以及一个可直接从服务器打开/关闭机器人视觉系统的开关（`server.ts` 的 `"vision"` 原子指令）。
- **3D 视图**（`lib/ui/three_d_screen.dart`）—— 通过 WebView 嵌入 HYDRA-UMC-STUDIO 自身的实时 3D 视口（`?hideUI=true&robotId=&token=`）,与 Android 应用的方式相同,原因也相同（免费获得真实的、当前正在使用的 3D 场景）。在 `webview_flutter` 不支持的平台（本仓库用于构建验证的 Windows 桌面目标）上,会回退到一个诚实的占位符。
- **系统指标**（`lib/state/robot_view_model.dart`）—— 每 5 秒轮询一次 `GET /api/system/metrics`,与其他 2 个客户端的节奏相同,显示在仪表盘中。
- **8 语言界面**（`lib/l10n/`，标准的 `flutter gen-l10n` 流程）—— 英语、西班牙语、法语、德语、意大利语、日语和中文，与本生态系统的其他客户端保持一致。`设置 > 语言` 中的持久化设置默认跟随系统语言；`RobotViewModel.lastError` 现在是带类型的 `HydraError`，而不是预先格式化好的英文文本，因此业务逻辑层的错误提示（登录/连接/指令失败）也能正确本地化，而不只是界面上的静态文本。
- **离线状态缓存**（`lib/network/state_cache.dart`）—— 最后一次已知的设置树会连同真实的保存时刻一起持久化到磁盘（1 秒防抖），这样在真正的 `connect()` 往返请求仍在进行时，仪表盘/控制界面会立即显示真实（即使可能已过时）的机器人数据，而不是空白状态。只要这种情况还成立，一个真实可见的提示条(而不是默默猜测)就会显示"正在显示 HH:mm 的缓存数据"。一旦真正的数据获取成功，就会被替换。
- **遥测**（`lib/ui/telemetry_screen.dart`）—— 一个终端风格、最新在前的日志，记录真实的连接/登录/指令生命周期事件，最多保留 50 条，并提供清除日志的操作——与 HYDRA-UMC-ANDROID-CONTROL 自身的遥测标签页相同的"Matrix 绿"配色约定。
- **应用内语音助手**（`lib/ui/voice_assistant_dialog.dart`）—— 应用栏中的麦克风图标会打开一个对话框，可输入问题或指令,通过与 HYDRA-UMC-ANDROID-CONTROL 自身应用内语音按钮及其手表中继相同的真实 `POST /api/voice/turn` 路由发送给 `HYDRA-UMC-VOICE-UI`。绝不上传音频——目前仅支持文本输入,因为 iOS 原生语音识别需要 Speech 框架,而这个仅限 Windows 的开发环境无法针对真实设备/Xcode 进行编译或验证。回复绝不会直接发出机器人指令。

## 🚀 构建

需要 [Flutter SDK](https://docs.flutter.dev/get-started/install)（stable 渠道）。本仓库基于 Flutter 3.47.0 构建/验证。本仓库中只配置了 `windows/` 和 `ios/` 两个平台（没有 `android/`、`linux/`、`web/` 或 `macos/` 文件夹）——Windows 的存在是为了让本应用自身的逻辑能够在没有 Mac 的情况下构建和运行;iOS 才是真正的目标平台。

### 构建脚本

```bash
./build.sh     # Git Bash / WSL —— flutter pub get + flutter build windows
build.bat      # cmd.exe / PowerShell —— flutter pub get + flutter build windows
```

两者都会生成 `build/windows/x64/runner/Release/hydra_umc_control.exe`,并且都不会更改应用的版本号——见下文[版本管理](#-版本管理)。

### 手动构建

```bash
flutter pub get
flutter analyze          # 静态分析——无需编译器
flutter test             # 组件测试
dart run tool/bump_version.dart  # 递增版本号，与 build.sh/build.bat 所做的相同
flutter build windows    # 生成 build/windows/x64/runner/Release/hydra_umc_control.exe
flutter run -d windows   # 或在 Mac 上使用 -d <ios-device-id>
```

**构建真正的 iOS `.ipa`** 需要在 macOS 上使用 Xcode——在该机器上运行：`flutter build ipa`（或直接在 Xcode 中打开 `ios/Runner.xcworkspace`）。这无法在 Windows 上完成；见上文“为何选择 Flutter，而非原生 Swift”。

## 🔢 版本管理

本仓库遵循生态系统统一的策略：构建绝不会更改版本号。显式的 `bump` 命令（`python tools/hydra_project_tool.py bump`）会运行 `tool/bump_version.dart`，并应用：

- **Patch,里程表方式（十进制）：** 每次 bump +1;一旦超过 9 就重置为 0,并将 minor 加 1——例如 `0.0.9` -> `0.1.0`。Major 从不被自动修改。
- **构建号**（`+` 之后的部分）：一个纯粹的单调计数器,每次 bump +1,不进位。

同一个脚本会重新生成 `lib/app_version.dart`（这是生成的文件,不是手工编辑的——一个普通的 `const` 文件,而非像 `package_info_plus` 那样引入新的运行时依赖）,应用在运行时读取它,以在 **Settings** 界面显示自身版本。完整版本历史见 [CHANGELOG.md](CHANGELOG.md)。

## 📂 仓库结构

```text
HYDRA-UMC-IOS-CONTROL/
├── build.bat, build.sh              # flutter pub get + 版本递增 + flutter build windows
├── tool/
│   └── bump_version.dart            # 里程表式版本递增（仅由显式 `bump` 命令运行）
├── lib/
│   ├── main.dart                    # 应用入口点，ChangeNotifierProvider + 登录门禁
│   ├── app_version.dart             # 生成文件——由 tool/bump_version.dart 重新生成，请勿手动编辑
│   ├── models/
│   │   ├── server_info.dart         # 发现/连接条目——与其他 2 个客户端中的 ServerInfo 镜像一致
│   │   ├── hydra_state.dart         # RobotView/ControllerView/HydraState——原始 settings.json 树的薄型可变视图
│   │   ├── assistant_reply.dart    # 应用内语音助手的回复模型
│   │   └── stop_all_result.dart    # 全局 STOP 的应答（按机器人）
│   ├── network/
│   │   ├── hydra_api_client.dart    # REST：登录、设置、原子化机器人指令、系统指标
│   │   ├── hydra_websocket.dart     # /ws 实时同步客户端
│   │   ├── discovery.dart           # 针对本设备自身真实本地子网的并发扫描 GET /api/hydra-info
│   │   ├── auth_prefs.dart          # 持久化的连接信息（shared_preferences）+ 令牌（钥匙串）
│   │   ├── biometric_helper.dart    # package:local_auth 的轻量封装（Face ID/Touch ID 门禁）
│   │   └── state_cache.dart         # 移植自 Android 自身的 StateCache.kt——跨启动持久化的最后已知良好状态
│   ├── state/
│   │   ├── robot_view_model.dart    # 每个界面都监听的单一 ChangeNotifier
│   │   └── hydra_error.dart         # 面向 RobotViewModel 的类型化错误接口（自身无 BuildContext）
│   ├── l10n/                        # 真实生成的本地化文件（8 种语言）——见仓库根目录的 l10n.yaml
│   │   ├── app_localizations.dart   # 生成的基类
│   │   ├── app_localizations_en.dart, _es.dart, _it.dart, _fr.dart, _de.dart, _ja.dart, _zh.dart, _pt.dart
│   │   └── language_prefs.dart      # 持久化的语言覆盖设置（shared_preferences）
│   └── ui/
│       ├── login_screen.dart        # 主机/端口/用户/密码字段 + “扫描本地网络”
│       ├── biometric_gate_screen.dart # Face ID/Touch ID 待处理时由 main.dart 的 _RootGate 显示
│       ├── main_screen.dart         # 底部导航外壳（仪表盘/控制/摄像头/3D/遥测/设置）
│       ├── dashboard_screen.dart    # 每机器人卡片 + 系统指标栏
│       ├── control_screen.dart      # 点动/速度/阀门/泵/回放控制
│       ├── camera_screen.dart       # MJPEG 查看器 + 视觉开关
│       ├── three_d_screen.dart      # 通过 WebView 嵌入 STUDIO 自身的 3D 视口
│       ├── telemetry_screen.dart    # 移植自 Android 自身的 TelemetryScreen.kt
│       ├── voice_assistant_dialog.dart # 应用内麦克风/文本按钮,连接 HYDRA-UMC-VOICE-UI
│       ├── settings_screen.dart     # 连接信息 + 退出登录
│       └── widgets/
│           ├── joystick_pad.dart     # 点动方向键（刻意不采用模拟摇杆，见文件头部说明）
│           ├── stop_all.dart            # 全局 STOP 按钮及其结果/“未确认”横幅
│           ├── digital_readout.dart, status_led.dart
│           └── mjpeg_view.dart       # 手写的 MJPEG 流解析器
├── ios/                              # Xcode 项目（仅可在 macOS 上构建）
├── windows/                          # Windows 桌面目标——无需 Mac 即可进行构建验证
├── docs/ARCHITECTURE.md
├── test/                             # widget_test, auth_prefs_test, discovery_interfaces_test, format_uptime_test, hostile_answers_test, hydra_error_test, hydra_websocket_reconnect_test, hydra_websocket_token_test, joystick_pad_test, localization_test, main_screen_cached_state_banner_test, mjpeg_lifecycle_test, robot_view_model_background_pause_test, robot_view_model_cached_state_test, robot_view_model_server_errors_test, robot_view_model_silent_refresh_test, robot_view_model_stop_all_test, saved_data_block_test, session_storage_test, state_cache_test, telemetry_log_test, voice_turn_test, websocket_uri_test
├── images/
├── README.md                         # 本文件
└── README_spa.md / README_ita.md / README_fra.md / README_deu.md / README_zho.md / README_jpn.md / README_por.md  # 翻译
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
- **[HYDRA-UMC-BRIDGE-AMR](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-AMR)** —— 通过 VDA 5050 MQTT 发布者为 AGV/AMR 车队提供的协调边界(仅针对仿真车队测试)。
- **[HYDRA-UMC-BRIDGE-CNC](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-CNC)** —— 具备 GRBL 状态/控制字节访问能力的高层 CNC 单元协调器(仅针对模拟器测试)。
- **[HYDRA-UMC-BRIDGE-DROIDS](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-DROIDS)** —— 面向足式/人形机器人的协调边界,带有 Boston Dynamics Spot 指令发送器(仅针对模拟器测试)。
- **[HYDRA-UMC-BRIDGE-LASER](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-LASER)** —— 读取 3 路钥匙/外壳/联锁 GPIO 信号的激光单元协调器(仅针对模拟芯片测试;无法使激光器上膛或发射)。
- **[HYDRA-UMC-BRIDGE-OPENPNP](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-OPENPNP)** —— 面向 OpenPnP 贴片机板级流程的安全高层协调器。
- **[HYDRA-UMC-BRIDGE-PRINTER3D](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-PRINTER3D)** —— 面向 Moonraker/Klipper 3D 打印机的安全协调边界,具备真实的受控作业指令。
- **[HYDRA-UMC-BRIDGE-ROS2](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-ROS2)** —— 带有惰性导入 rclpy ROS 2 传输层的协调器(尚未在 ROS 2 环境中运行)。
- **[HYDRA-UMC-BRIDGE-UAV](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-UAV)** —— 面向搭载摄像头的无人机的协调边界,带有 MAVLink 指令发送器(仅针对模拟器测试)。

**直接相关**
- **[HYDRA-UMC-WATCH](https://github.com/JuanenRac/HYDRA-UMC-WATCH)** —— 带有触觉提醒模式与配对手机语音中继的 WearOS 伴侣应用(尚未在实体手表上运行);HYDRA-UMC-ANDROID-CONTROL 的腕上伴侣(仅限 WearOS;本 iOS 应用目前还没有对应的 Apple Watch 版本)。
- **[HYDRA-UMC-HIL-BRIDGE](https://github.com/JuanenRac/HYDRA-UMC-HIL-BRIDGE)** —— 在仿真与真实硬件之间带有软件碰撞联锁的硬件在环路由器(未在真实硬件上测试);让本应用能够以硬件在环方式远程控制数字孪生的桥接。

**生态系统中的其他项目**

*核心硬件与平台*
- **[HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC)** —— 机器人手臂主板设计——CM5 主机 + 双核 STM32H745,目标是通过 CAN-OTA/SPI-OTA 协调最多 8 条工具臂(固件处于早期阶段,尚无已组装的电路板)。
- **[HYDRA-UMC-OS](https://github.com/JuanenRac/HYDRA-UMC-OS)** —— 面向 CM5 的可复现 Raspberry Pi OS 产品层——只读代理、经过验证的配置/配置文件、WiFi 首次配网。
- **[HYDRA-UMC-SDK](https://github.com/JuanenRac/HYDRA-UMC-SDK)** —— 每个桥接都据此校验自身指令的共享 JSON-Schema 契约与软件作业门限边界(并非经认证的安全功能)。
- **[HYDRA-UMC-CONNECTOR-HUB](https://github.com/JuanenRac/HYDRA-UMC-CONNECTOR-HUB)** — 面向外部机器连接器的声明式适配器清单注册与校验工具；把 SDK 自身的契约理念扩展到外部机器，而不取代工业网关类项目。

*核心后端与客户端*
- **[HYDRA-UMC-EDITOR-URDF](https://github.com/JuanenRac/HYDRA-UMC-EDITOR-URDF)** —— 将完成的模型推送到 STUDIO 自身目录的桌面版图形化 URDF 创建/编辑工具。
- **[HYDRA-UMC-EDITOR-STL](https://github.com/JuanenRac/HYDRA-UMC-EDITOR-STL)** — 桌面 STL 模型编辑器，在 HYDRA-UMC-EDITOR-URDF 编辑的同一模型目录中变换/替换/移除/添加真实部件。

*URTC 工具平台*
- **[URTC](https://github.com/JuanenRac/URTC)** —— 面向实体 Universal Robot Tool Controller 板卡的固件,通过 CAN 总线支持 25 种以上工具配置。
- **[URTC-FLASHER](https://github.com/JuanenRac/URTC-FLASHER)** —— 面向 URTC 板卡的桌面图形烧录工具,支持 CAN-OTA 以及全芯片 SWD/JTAG。
- **[URTC-TESTER](https://github.com/JuanenRac/URTC-TESTER)** —— 面向 URTC 板卡的桌面实时 CAN 总线诊断工具,每种工具配置对应一个面板。
- **[URTC-WEB-STUDIO](https://github.com/JuanenRac/URTC-WEB-STUDIO)** —— 通过 Web Serial API 实现的浏览器版 URTC-TESTER 替代方案,无需本地安装。

*视觉 AI 节点(Hailo-8)*
- **[HYDRA-UMC-VISION-NODE](https://github.com/JuanenRac/HYDRA-UMC-VISION-NODE)** —— 面向 Hailo-8 视觉流水线的集成中枢,具备逐阶段的真实硬件就绪检测。
- **[HYDRA-UMC-DETECTION-HEF](https://github.com/JuanenRac/HYDRA-UMC-DETECTION-HEF)** —— 具备 Hailo 架构/校验和安全加载验证的真实编译模型注册表。
- **[HYDRA-UMC-VISION-STREAMER](https://github.com/JuanenRac/HYDRA-UMC-VISION-STREAMER)** —— 具备真实 HailoRT 集成边界的真实 GStreamer 流水线 + MediaMTX 配置生成器。
- **[HYDRA-UMC-VISUAL-SERVOING-API](https://github.com/JuanenRac/HYDRA-UMC-VISUAL-SERVOING-API)** —— 以区域状态为授权条件的 Position-Based Visual Servoing 修正律;尚无摄像头位姿估计。
- **[HYDRA-UMC-SAFETY-ZONES](https://github.com/JuanenRac/HYDRA-UMC-SAFETY-ZONES)** —— 从文件读取物体位置的 v0 区域入侵、校准新鲜度与 E-STOP 请求逻辑;没有检测器为其供数,也尚未连接任何物理 E-STOP。

*认知 AI 节点(Hailo-10)*
- **[HYDRA-UMC-COGNITIVE-NODE](https://github.com/JuanenRac/HYDRA-UMC-COGNITIVE-NODE)** —— 面向 Hailo-10 认知流水线(LLM/VLA/语音编排)的集成中枢。
- **[HYDRA-UMC-VLA-ENGINE](https://github.com/JuanenRac/HYDRA-UMC-VLA-ENGINE)** —— 面向 Vision-Language-Action 模型的真实动作 token 编解码与轨迹生成。
- **[HYDRA-UMC-VOICE-UI](https://github.com/JuanenRac/HYDRA-UMC-VOICE-UI)** —— 具备受限、需确认的 Watch 中继的真实语音前端(VAD + 意图解析)。
- **[HYDRA-UMC-SEMANTIC-PLANNER](https://github.com/JuanenRac/HYDRA-UMC-SEMANTIC-PLANNER)** —— 基于真实规则的任务分解,以及针对 MCU 错误码的语义化错误恢复。
- **[HYDRA-UMC-DOCS-QA](https://github.com/JuanenRac/HYDRA-UMC-DOCS-QA)** —— 面向本生态系统自身 Markdown 文档的真实纯标准库 TF-IDF 文档检索。
- **[HYDRA-UMC-LOCAL-TECHNICIAN](https://github.com/JuanenRac/HYDRA-UMC-LOCAL-TECHNICIAN)** — 面向生态系统自身的本地、按策略门控的 AI 维护技师——观察、诊断并提出修复建议;两个最高风险等级目前特意尚未实现。

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
- **[HYDRA-UMC-OS-REBUILDER](https://github.com/JuanenRac/HYDRA-UMC-OS-REBUILDER)** —— 构建即刻可烧录、预装生态系统最新版本的 CM5 镜像的 Windows/Linux 桌面工具,具备类似 Raspberry Pi Imager 风格的首次启动 Wi-Fi/用户/SSH 配置。
- **[HYDRA-UMC-OPS-AGENT](https://github.com/JuanenRac/HYDRA-UMC-OPS-AGENT)** — 维护事件协调器：一个低权限的边缘角色采集经过脱敏的库存/健康快照，一个控制面角色以只读方式渲染它，并请求某个 AI 提供方给出诊断建议——从不应用补丁，也从不部署任何内容。
- **[HYDRA-UMC-DEV-SERVER](https://github.com/JuanenRac/HYDRA-UMC-DEV-SERVER)** — 可复现的开发主机（Raspberry Pi 5 / CM5），保存整个生态系统的源代码，并在持久队列下运行有界的构建/测试任务；这是专用的开发角色，明确区别于运行中的 CM5。

---

## 📚 文档与社区

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** —— 本应用与 `server.ts` 之间的 Wi-Fi 传输契约（逐个端点说明）、为何目前仍没有蓝牙路径、真实的双路径发现机制，以及本应用与生态系统其余部分的关系。
- **[CONTRIBUTING.md](CONTRIBUTING.md)** —— 提交 Pull Request 所需的技术栈和编码规范。
- **[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)** —— 本社区所期望的行为准则。
- **[SECURITY.md](SECURITY.md)** —— 如何报告漏洞，以及本项目真实的安全关注重点。
- **[SUPPORT.md](SUPPORT.md)** —— 在哪里提问和报告缺陷。
- **[LICENSE.md](LICENSE.md)** —— 本项目自身的许可证。

## 👤 作者
**JuanenRac** (Electro Hobby 3D)
📧 electrohobby3d@gmail.com
📺 [youtube.com/@electrohobby3d](https://youtube.com/@electrohobby3d)

## 📜 许可证

源代码采用 **GNU 通用公共许可证 v3.0（GPL-3.0-or-later）**——见 [`LICENSE`](LICENSE)。

文档（本 README 及其自身的翻译版本——`README_spa.md`、`README_ita.md`、`README_fra.md`、`README_deu.md`、`README_zho.md`、`README_jpn.md`、`README_por.md`）依据 **知识共享 署名-相同方式共享 4.0 国际许可协议（CC BY-SA 4.0）** 提供。完整文本见 https://creativecommons.org/licenses/by-sa/4.0/。
