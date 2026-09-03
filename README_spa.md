<p align="center">
  <img src="images/HYDRA_UMC_BANNER.svg" alt="HYDRA-UMC-IOS-CONTROL banner" width="100%">
</p>

# 📱 HYDRA-UMC CONTROL (iOS)

<p align="center">
  <a href="README.md">🇺🇸 English</a> |
  🇪🇸 <b>Español</b> |
  <a href="README_fra.md">🇫🇷 Français</a> |
  <a href="README_ita.md">🇮🇹 Italiano</a> |
  <a href="README_deu.md">🇩🇪 Deutsch</a> |
  <a href="README_zho.md">🇨🇳 简体中文</a> |
  <a href="README_jpn.md">🇯🇵 日本語</a>
</p>


<p align="left">
  <img src="https://img.shields.io/badge/Licencia-GPL%203.0-blue.svg" alt="GPL 3.0">
  <img src="https://img.shields.io/badge/Framework-Flutter-02569B.svg" alt="Flutter">
  <img src="https://img.shields.io/badge/Lenguaje-Dart-0175C2.svg" alt="Dart">
  <img src="https://img.shields.io/badge/Plataforma-iOS-000000.svg" alt="iOS">
</p>


Una app Flutter (Dart) multiplataforma que controla un robot de la plataforma [HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC) por Wi-Fi, hablando exactamente el mismo contrato [`REMOTE_API.md`](https://github.com/JuanenRac/HYDRA-UMC-SERVER/blob/main/docs/REMOTE_API.md) que usan [HYDRA-UMC SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE) y [HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL) - descubrimiento, login, comandos atómicos por robot, y sincronización WebSocket en vivo contra una instancia de [HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER) en ejecución (el backend headless separado del propio proceso de HYDRA-UMC STUDIO - STUDIO es ahora un cliente puro de frontend de ese servidor, igual que esta app).

## 🔀 Por qué Flutter, no Swift nativo

Esta app tiene como objetivo iOS/iPadOS, pero está construida en **Flutter** en vez de Swift/SwiftUI: el entorno de trabajo de este repositorio es exclusivamente Windows, y un proyecto Swift nativo se puede *escribir* en Windows pero nunca *compilar o ejecutar* ahí (Xcode y el SDK de iOS son exclusivos de macOS). El propio target de escritorio Windows de Flutter permite que esta app se construya, ejecute y pruebe de verdad en esta máquina - `flutter analyze` limpio, `flutter build windows` con éxito, `flutter test` pasando, y el `.exe` compilado arrancando y renderizando sin errores en tiempo de ejecución - en vez de escribir miles de líneas de Swift a ciegas, sin forma alguna de verificar nada de ello hasta que haya un Mac disponible.

**Esto no elimina la propia restricción de Apple** - un `.ipa` real sigue requiriendo Xcode en un Mac (o un runner de CI macOS) para compilarlo y firmarlo; nada de la elección de framework cambia eso. Lo que Flutter aporta es la capacidad de verificar cada otra línea de la lógica propia de esta app (redes, estado, UI) en esta máquina hoy, y de enviar un código base idéntico a iOS más adelante sin reescribirlo.

## 🏗️ Qué está implementado

- **Login** (`lib/ui/login_screen.dart`, `lib/state/robot_view_model.dart`) - campos editables de IP/puerto y credenciales del operador más `POST /api/login`; no hay cuenta ni contraseña predefinidas. Un servidor de producción requiere credenciales de arranque configuradas explícitamente para su primer administrador; las cuentas "operator" adicionales de menor privilegio se crean desde Config > Users en la interfaz del navegador. El token de sesión persiste entre arranques mediante `shared_preferences`. Un botón "Scan local network" (`lib/network/discovery.dart`) encuentra servidores sin que el usuario necesite saber ya la IP.
- **Descubrimiento de red** (`lib/network/discovery.dart`) - escaneo concurrente de `GET /api/hydra-info` a través de la(s) subred(es) local(es) real(es) propia(s) de este dispositivo, derivadas del `NetworkInterface.list()` propio de `dart:io` en vez de una única suposición fija, ya que la LAN de un teléfono tiene tantas probabilidades de ser `192.168.0.x` o `10.x.x.x` como `192.168.1.x`. Recae en `192.168.1.x` solo si la enumeración de interfaces en sí vuelve vacía.
- **Sincronización de comandos atómicos** (el propio `_sendAtomicCommand()` de `lib/state/robot_view_model.dart`) - cada escritura (enable/disable/play/pause/stop/jog/valve/pump/speed/vision) usa el endpoint real `POST /api/robot/:id/command`, una carga útil pequeña y dirigida en vez de sobrescribir todo el árbol de settings, con propagación correcta de robot combinado (`combinedWith`) para los 5 comandos que la necesitan.
- **Sincronización WebSocket en vivo** (`lib/network/hydra_websocket.dart`) - siempre adjunta `?token=` a la URL de conexión (el propio upgrade `/ws` de `server.ts` lo exige incondicionalmente), maneja tanto tipos de difusión `"settings"` como `"delta"`, se reconecta automáticamente al caerse.
- **Dashboard** (`lib/ui/dashboard_screen.dart`) - tarjetas por robot, reactivas en tiempo real vía el propio `ChangeNotifier` de `Provider`, convención de LED (verde parpadeando = activo, rojo fijo = inactivo) y visualización de robot combinado (mostrada solo en el lado seguidor, resuelta por id) igualando el propio Dashboard Overview de HYDRA-UMC-STUDIO.
- **Control Manual** (`lib/ui/control_screen.dart`, `lib/ui/widgets/joystick_pad.dart`) - D-pad de jog (con/sin objetivo de mesa XY), sliders de velocidad/aceleración, interruptores de válvula/bomba, y protección real de pulsación larga en E-STOP/STOP (un toque rápido no hace nada salvo un aviso háptico + visual, solo una pulsación sostenida genuina envía el comando).
- **Cámara** (`lib/ui/camera_screen.dart`, `lib/ui/widgets/mjpeg_view.dart`) - un pequeño analizador de stream MJPEG hecho a mano (sin paquete de terceros), un estado claro de "Camera Disabled" en vez de una imagen en blanco silenciosa, y un interruptor para activar/desactivar el sistema de visión de un robot directamente desde el servidor (el comando atómico `"vision"` propio de `server.ts`).
- **Vista 3D** (`lib/ui/three_d_screen.dart`) - embebe el propio viewport 3D en tiempo real de HYDRA-UMC-STUDIO en un WebView (`?hideUI=true&robotId=&token=`), el mismo enfoque que la app de Android, por la misma razón (obtiene gratis la escena 3D real, actualmente en producción). Recae en un placeholder honesto en plataformas que `webview_flutter` no soporta (el target de escritorio Windows de este repositorio, usado para verificación de build).
- **Métricas del sistema** (`lib/state/robot_view_model.dart`) - `GET /api/system/metrics` consultado cada 5s, la misma cadencia que los otros 2 clientes, mostrado en el Dashboard.
- **UI en 7 idiomas** (`lib/l10n/`, pipeline estándar `flutter gen-l10n`) - inglés, español, francés, alemán, italiano, japonés y chino, igualando al resto de clientes de este ecosistema. Un ajuste persistido en `Ajustes > Idioma` usa por defecto el idioma del sistema; `RobotViewModel.lastError` es un `HydraError` tipado en lugar de texto en inglés ya formateado, así que los mensajes de error de la lógica de negocio (fallos de inicio de sesión/conexión/comando) también se traducen correctamente, no solo el texto estático de las pantallas.
- **Caché de estado sin conexión** (`lib/network/state_cache.dart`) - el último árbol de ajustes conocido se guarda en disco (con debounce de 1s), así que las pantallas de Dashboard/Control muestran datos reales, aunque potencialmente desactualizados, inmediatamente al arrancar en vez de un estado vacío mientras el `connect()` real todavía está en curso. Se sustituye por los datos reales en cuanto la conexión tiene éxito.
- **Telemetría** (`lib/ui/telemetry_screen.dart`) - un registro estilo terminal, más reciente primero, de eventos reales de conexión/inicio de sesión/comandos, limitado a 50 entradas, con una acción para borrarlo - la misma convención "verde Matrix" que la propia pestaña de Telemetría de HYDRA-UMC-ANDROID-CONTROL.

## 🚀 Compilación

Requiere el [Flutter SDK](https://docs.flutter.dev/get-started/install) (canal stable). Este repositorio se compila/verifica contra Flutter 3.47.0. Solo `windows/` e `ios/` están configuradas como plataformas en este repositorio (sin carpetas `android/`, `linux/`, `web/`, o `macos/`) - Windows existe para que la lógica propia de esta app se pueda compilar y ejecutar sin un Mac; iOS es el objetivo real.

### Scripts de build

```bash
./build.sh     # Git Bash / WSL - flutter pub get + bump de versión + flutter build windows
build.bat      # cmd.exe / PowerShell - flutter pub get + bump de versión + flutter build windows
```

Ambos producen `build/windows/x64/runner/Release/hydra_umc_control.exe`, y ambos suben la versión de la app primero - ver [Versionado](#-versionado) más abajo.

### Build manual

```bash
flutter pub get
flutter analyze          # analisis estatico - sin necesidad de compilador
flutter test             # pruebas de widgets
dart run tool/bump_version.dart  # sube la versión, igual que hacen build.sh/build.bat
flutter build windows    # produce build/windows/x64/runner/Release/hydra_umc_control.exe
flutter run -d windows   # o -d <ios-device-id> desde un Mac, o -d chrome para una vista previa web rapida
```

**Compilar el `.ipa` real de iOS** requiere Xcode en macOS - desde esa máquina: `flutter build ipa` (o abrir `ios/Runner.xcworkspace` directamente en Xcode). Esto no se puede hacer desde Windows; ver "Por qué Flutter, no Swift nativo" arriba.

## 🔢 Versionado

Este repositorio sigue una política ecosistema-wide: la versión sube
automáticamente en **cada build real**, sin editar a mano la línea
`version:` de `pubspec.yaml`. `build.sh`/`build.bat` ejecutan
`tool/bump_version.dart` antes de invocar `flutter build`, aplicando:

- **Patch, estilo cuentakilómetros (base 10):** +1 en cada build; al
  superar 9 se resetea a 0 y minor sube +1 - p. ej. `0.0.9` ->
  `0.1.0`. Major nunca se toca automáticamente.
- **Build number** (la parte tras `+`): un contador monotónico simple,
  +1 en cada build, sin acarreo.

El mismo script regenera `lib/app_version.dart` (generado, no editado a
mano - un simple archivo `const`, no una dependencia nueva en tiempo de
ejecución como `package_info_plus`), que la app lee en tiempo real para
mostrar su propia versión en la pantalla de **Ajustes**. Ver
[CHANGELOG.md](CHANGELOG.md) para el historial de versiones.

## 📂 Estructura del Repositorio

```text
HYDRA-UMC-IOS-CONTROL/
├── build.bat, build.sh              # flutter pub get + bump de versión + flutter build windows
├── tool/
│   └── bump_version.dart            # Script de bump de versión, ejecutado por build.bat/build.sh antes de cada build (ver Versionado arriba)
├── lib/
│   ├── main.dart                    # Punto de entrada de la app, ChangeNotifierProvider + puerta de login
│   ├── app_version.dart             # GENERADO - regenerado por tool/bump_version.dart, no editar a mano
│   ├── models/
│   │   ├── server_info.dart         # Entrada de descubrimiento/conexion - refleja ServerInfo de los otros 2 clientes
│   │   └── hydra_state.dart         # RobotView/ControllerView/HydraState - vistas mutables finas sobre el arbol crudo de settings.json
│   ├── network/
│   │   ├── hydra_api_client.dart    # REST: login, settings, comando atomico de robot, metricas del sistema
│   │   ├── hydra_websocket.dart     # Cliente de sincronizacion en vivo por /ws
│   │   ├── discovery.dart           # Escaneo concurrente de la(s) subred(es) local(es) real(es) de este dispositivo contra GET /api/hydra-info
│   │   ├── auth_prefs.dart          # Conexion y token persistidos (shared_preferences)
│   │   ├── biometric_helper.dart    # Envoltorio fino sobre package:local_auth (puerta Face ID/Touch ID)
│   │   └── state_cache.dart         # Portado de StateCache.kt de Android - último estado bueno conocido, persistido entre arranques
│   ├── state/
│   │   ├── robot_view_model.dart    # Unico ChangeNotifier que escucha cada pantalla
│   │   └── hydra_error.dart         # Superficie de error tipada para RobotViewModel (sin BuildContext propio)
│   ├── l10n/                        # Localizaciones reales generadas (7 idiomas) - ver l10n.yaml en la raíz del repo
│   │   ├── app_localizations.dart   # Clase base generada
│   │   ├── app_localizations_en.dart, _es.dart, _it.dart, _fr.dart, _de.dart, _ja.dart, _zh.dart
│   │   └── language_prefs.dart      # Override de idioma persistido (shared_preferences)
│   └── ui/
│       ├── login_screen.dart        # Campos de host/puerto/usuario/pass + "Scan local network"
│       ├── biometric_gate_screen.dart # Mostrada por _RootGate de main.dart mientras Face ID/Touch ID está pendiente
│       ├── main_screen.dart         # Contenedor de navegacion inferior (Dashboard/Control/Camara/3D/Ajustes)
│       ├── dashboard_screen.dart    # Tarjetas por robot + barra de metricas del sistema
│       ├── control_screen.dart      # Controles de jog/velocidad/valvula/bomba/reproduccion
│       ├── camera_screen.dart       # Visor MJPEG + interruptor de vision on/off
│       ├── three_d_screen.dart      # Embebe el propio viewport 3D de STUDIO via WebView
│       ├── telemetry_screen.dart    # Portado de TelemetryScreen.kt de Android
│       ├── settings_screen.dart     # Informacion de conexion + cerrar sesion
│       └── widgets/
│           ├── joystick_pad.dart     # D-pad de jog (deliberadamente no un stick analogico, ver cabecera del archivo)
│           ├── digital_readout.dart, status_led.dart
│           └── mjpeg_view.dart       # Analizador de stream MJPEG hecho a mano
├── ios/                              # Proyecto Xcode (compilar solo desde macOS)
├── windows/                          # Target de escritorio Windows - verificacion de build sin un Mac
├── docs/ARCHITECTURE.md
├── test/                             # widget_test, websocket_uri_test, format_uptime_test, localization_test, state_cache_test, telemetry_log_test
├── images/
├── README.md                         # este archivo (ingles)
└── README_spa.md / README_ita.md / README_fra.md / README_deu.md / README_zho.md / README_jpn.md  # traducciones
```

## 🔗 Proyectos Relacionados

Este proyecto es parte del ecosistema de robótica HYDRA-UMC del mismo autor (JuanenRac / Electro Hobby 3D). Vale la pena conocerlo, ya que una petición podría en realidad ser sobre alguno de estos en vez de sobre este repositorio.

**Proyecto Padre**
- **[HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER)** — el backend headless real (REST/WebSocket) con el que habla de verdad cada cliente de control; el backend contra el que se ejecutan el inicio de sesión, los comandos atómicos y la sincronización WebSocket propios de esta app.

**Proyectos Hermanos** — también hablan con la propia API de HYDRA-UMC-SERVER, cada uno como su propio cliente
- **[HYDRA-UMC-STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO)** — panel de control web con visualización 3D multi-robot en tiempo real; su propio visor 3D se integra directamente en la pantalla de Vista 3D de esta app mediante WebView.
- **[HYDRA-UMC-SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE)** — centro de mando de enjambre de escritorio (PySide6) para varios servidores a la vez, empaquetado como ejecutable independiente; habla exactamente el mismo contrato `REMOTE_API.md` que esta app.
- **[HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL)** — app nativa de control para Android con inicio de sesión biométrico y un compañero Wear OS emparejado; habla exactamente el mismo contrato `REMOTE_API.md` que esta app.
- **[HYDRA-UMC-DSI](https://github.com/JuanenRac/HYDRA-UMC-DSI)** — interfaz táctil nativa para la pantalla táctil DSI de 7" a bordo, embebida en el propio CM5.
- **[HYDRA-UMC-BRIDGE-AMR](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-AMR)** — barrera de coordinación para flotas AGV/AMR mediante un publicador MQTT VDA 5050 real.
- **[HYDRA-UMC-BRIDGE-CNC](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-CNC)** — coordinador de alto nivel para celdas CNC con acceso real a estado/bytes de control GRBL.
- **[HYDRA-UMC-BRIDGE-DROIDS](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-DROIDS)** — barrera de coordinación para droides con patas/humanoides, con un emisor de comandos real para Boston Dynamics Spot.
- **[HYDRA-UMC-BRIDGE-LASER](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-LASER)** — coordinador de seguridad para celdas láser que lee 3 salvaguardas GPIO reales de llave/carcasa/enclavamiento.
- **[HYDRA-UMC-BRIDGE-OPENPNP](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-OPENPNP)** — coordinador de alto nivel seguro para el flujo de placas de pick-and-place OpenPnP.
- **[HYDRA-UMC-BRIDGE-PRINTER3D](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-PRINTER3D)** — barrera de coordinación segura para impresoras 3D Moonraker/Klipper, con comandos de trabajo reales y controlados.
- **[HYDRA-UMC-BRIDGE-ROS2](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-ROS2)** — coordinador de seguridad con un transporte ROS 2 rclpy real, importado de forma perezosa.
- **[HYDRA-UMC-BRIDGE-UAV](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-UAV)** — barrera de coordinación para UAV equipados con cámara, con un emisor de comandos MAVLink real.

**Directamente Relacionados**
- **[HYDRA-UMC-WATCH](https://github.com/JuanenRac/HYDRA-UMC-WATCH)** — app compañera de WearOS con alertas hápticas reales y un relé de voz al teléfono emparejado; la compañera Apple Watch de esta app, para control y estado de un vistazo desde la muñeca.
- **[HYDRA-UMC-HIL-BRIDGE](https://github.com/JuanenRac/HYDRA-UMC-HIL-BRIDGE)** — enclavamiento de seguridad real hardware-in-the-loop que enruta comandos entre simulación y hardware real; el puente que permite a esta app controlar de forma remota el gemelo digital, hardware-in-the-loop.

**También Forma Parte del Ecosistema**

*Hardware y Plataforma Base*
- **[HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC)** — la placa madre física del brazo robótico: host CM5 + coprocesador STM32H745 de doble núcleo, coordinando hasta 8 brazos herramienta por CAN-OTA/SPI-OTA.
- **[HYDRA-UMC-OS](https://github.com/JuanenRac/HYDRA-UMC-OS)** — capa de producto reproducible sobre Raspberry Pi OS para el CM5: agente de solo lectura, config/perfiles validados, aprovisionamiento WiFi de primer contacto.
- **[HYDRA-UMC-SDK](https://github.com/JuanenRac/HYDRA-UMC-SDK)** — el contrato JSON-Schema compartido y la barrera de seguridad contra la que cada bridge valida sus comandos.

*Backend Central y Clientes*
- **[HYDRA-UMC-EDITOR-URDF](https://github.com/JuanenRac/HYDRA-UMC-EDITOR-URDF)** — creador/editor gráfico de URDF de escritorio que envía los modelos terminados al propio catálogo de STUDIO.

*Plataforma de Herramientas URTC*
- **[URTC](https://github.com/JuanenRac/URTC)** — firmware para la placa física del Universal Robot Tool Controller, más de 25 perfiles de herramienta por bus CAN.
- **[URTC-FLASHER](https://github.com/JuanenRac/URTC-FLASHER)** — herramienta de escritorio con GUI para flashear placas URTC, CAN-OTA más SWD/JTAG de chip completo.
- **[URTC-TESTER](https://github.com/JuanenRac/URTC-TESTER)** — herramienta de escritorio de diagnóstico CAN-bus en vivo para placas URTC, un panel por perfil de herramienta.
- **[URTC-WEB-STUDIO](https://github.com/JuanenRac/URTC-WEB-STUDIO)** — alternativa basada en navegador a URTC-TESTER mediante la Web Serial API, sin instalación local.

*Nodo IA de Visión (Hailo-8)*
- **[HYDRA-UMC-VISION-NODE](https://github.com/JuanenRac/HYDRA-UMC-VISION-NODE)** — nodo de integración para el pipeline de visión Hailo-8, con una comprobación real de disponibilidad de hardware por etapa.
- **[HYDRA-UMC-DETECTION-HEF](https://github.com/JuanenRac/HYDRA-UMC-DETECTION-HEF)** — registro real de modelos compilados con verificación de carga segura por arquitectura Hailo/checksum.
- **[HYDRA-UMC-VISION-STREAMER](https://github.com/JuanenRac/HYDRA-UMC-VISION-STREAMER)** — generador real de pipeline GStreamer + config MediaMTX, con una frontera de integración HailoRT real.
- **[HYDRA-UMC-VISUAL-SERVOING-API](https://github.com/JuanenRac/HYDRA-UMC-VISUAL-SERVOING-API)** — ley de corrección real de Position-Based Visual Servoing, con puerta de seguridad según el estado de zona previo.
- **[HYDRA-UMC-SAFETY-ZONES](https://github.com/JuanenRac/HYDRA-UMC-SAFETY-ZONES)** — comprobación real de invasión de zona y solicitud de E-STOP, con exigencia de vigencia de calibración.

*Nodo IA Cognitivo (Hailo-10)*
- **[HYDRA-UMC-COGNITIVE-NODE](https://github.com/JuanenRac/HYDRA-UMC-COGNITIVE-NODE)** — nodo de integración para el pipeline cognitivo Hailo-10 (orquestación de LLM/VLA/voz).
- **[HYDRA-UMC-VLA-ENGINE](https://github.com/JuanenRac/HYDRA-UMC-VLA-ENGINE)** — codificación/decodificación real de tokens de acción y generación de trayectoria para un modelo Vision-Language-Action.
- **[HYDRA-UMC-VOICE-UI](https://github.com/JuanenRac/HYDRA-UMC-VOICE-UI)** — front-end de voz real (VAD + analizador de intención) con un relé a Watch acotado y con confirmación.
- **[HYDRA-UMC-SEMANTIC-PLANNER](https://github.com/JuanenRac/HYDRA-UMC-SEMANTIC-PLANNER)** — descomposición real de tareas basada en reglas y recuperación semántica de errores sobre códigos de error del MCU.
- **[HYDRA-UMC-DOCS-QA](https://github.com/JuanenRac/HYDRA-UMC-DOCS-QA)** — búsqueda real de documentos TF-IDF (solo librería estándar) sobre los propios documentos Markdown de este ecosistema.

*Orquestación y Enjambre*
- **[HYDRA-UMC-ORCHESTRATOR](https://github.com/JuanenRac/HYDRA-UMC-ORCHESTRATOR)** — nodo de integración con un contrato real de informe de salud gRPC/Protobuf y una máquina de estados de misión.
- **[HYDRA-UMC-JOB-DISPATCHER](https://github.com/JuanenRac/HYDRA-UMC-JOB-DISPATCHER)** — cola de trabajos real basada en prioridad con deduplicación, sobre una API HTTP real.
- **[HYDRA-UMC-NODE-HEALING](https://github.com/JuanenRac/HYDRA-UMC-NODE-HEALING)** — watchdog de salud de flota real basado en gRPC, con reintento/backoff y detección de discrepancia de identidad.
- **[HYDRA-UMC-PATH-PLANNER-3D](https://github.com/JuanenRac/HYDRA-UMC-PATH-PLANNER-3D)** — planificador de rutas 3D real basado en RRT, con validación real de colisión de obstáculos/espacio de trabajo.
- **[HYDRA-UMC-SWARM-SYNC](https://github.com/JuanenRac/HYDRA-UMC-SWARM-SYNC)** — sincronización de estado real mediante CRDT LWW-Element-Map, con pruebas de propiedades para convergencia multi-celda.

*Gemelo Digital y Simulación*
- **[HYDRA-UMC-TWIN](https://github.com/JuanenRac/HYDRA-UMC-TWIN)** — nodo de integración para el motor de gemelo digital, con un contrato real de sincronización por compatibilidad de versión.
- **[HYDRA-UMC-PHYSICS-REPLICA](https://github.com/JuanenRac/HYDRA-UMC-PHYSICS-REPLICA)** — cinemática directa real y validación de límites articulares sobre un subconjunto real de URDF.
- **[HYDRA-UMC-SYNTHETIC-DATA-GEN](https://github.com/JuanenRac/HYDRA-UMC-SYNTHETIC-DATA-GEN)** — generador real de escenas 2D procedurales con exportación de anotaciones YOLO/COCO.

*Datos y Analítica*
- **[HYDRA-UMC-DATALAKE](https://github.com/JuanenRac/HYDRA-UMC-DATALAKE)** — almacén de series temporales real respaldado por sqlite3, con una API HTTP real de ingesta/consulta.
- **[HYDRA-UMC-ANOMALY-DETECTOR](https://github.com/JuanenRac/HYDRA-UMC-ANOMALY-DETECTOR)** — detector de anomalías real basado en FFT + línea base estadística, con monitorización de deriva.
- **[HYDRA-UMC-PRODUCTION-REPORTS](https://github.com/JuanenRac/HYDRA-UMC-PRODUCTION-REPORTS)** — cálculo real de OEE/disponibilidad sobre el histórico de DATALAKE, con exportación CSV reproducible.
- **[HYDRA-UMC-TELEMETRY-COLLECTOR](https://github.com/JuanenRac/HYDRA-UMC-TELEMETRY-COLLECTOR)** — pipeline real de ingesta CAN/WebSocket hacia DATALAKE, con deduplicación por secuencia.

*Pasarela Industrial*
- **[HYDRA-UMC-GATEWAY-INDUSTRIAL](https://github.com/JuanenRac/HYDRA-UMC-GATEWAY-INDUSTRIAL)** — nodo de integración que retransmite a protocolos industriales, con una capa real de lista blanca de comandos/contrapresión.
- **[HYDRA-UMC-OPCUA-SERVER](https://github.com/JuanenRac/HYDRA-UMC-OPCUA-SERVER)** — espacio de direcciones OPC-UA real, verificado con una sesión de cliente real del protocolo binario.
- **[HYDRA-UMC-MQTT-BROKER](https://github.com/JuanenRac/HYDRA-UMC-MQTT-BROKER)** — broker MQTT real con autenticación por cliente opcional y ACL de tópicos.
- **[HYDRA-UMC-MTCONNECT-ADAPTER](https://github.com/JuanenRac/HYDRA-UMC-MTCONNECT-ADAPTER)** — endpoints XML reales `/probe` y `/current` de MTConnect, con salida en modo degradado.

*Herramientas Complementarias y Operaciones del Ecosistema*
- **[HYDRA-UMC-DASHBOARD-AI](https://github.com/JuanenRac/HYDRA-UMC-DASHBOARD-AI)** — paneles de Resúmenes Inteligentes y Resaltado de Anomalías sobre DATALAKE/ANOMALY-DETECTOR, con un respaldo estadístico honesto.
- **[HYDRA-UMC-TOOL-CLI](https://github.com/JuanenRac/HYDRA-UMC-TOOL-CLI)** — CLI de flota con un contrato real y estable de códigos de salida, cliente real y en vivo de la propia API de HYDRA-UMC-SERVER.
- **[URTC-SMART-RACK](https://github.com/JuanenRac/URTC-SMART-RACK)** — firmware para un rack de montaje de placas con decodificación real de ID de herramienta y lógica de precalentamiento Smart Idle.
- **[URTC-VISION-TOOL](https://github.com/JuanenRac/URTC-VISION-TOOL)** — firmware más un compañero de visión real en Python para un cabezal de inspección térmica/RGB.
- **[HYDRA-UMC-UPDATER](https://github.com/JuanenRac/HYDRA-UMC-UPDATER)** — herramienta administrativa de escritorio que descubre, clona y actualiza cada repositorio de este ecosistema.

---

## 👤 AUTOR
**JuanenRac** (Electro Hobby 3D)
📧 electrohobby3d@gmail.com
📺 [youtube.com/@electrohobby3d](https://youtube.com/@electrohobby3d)

## 📜 LICENCIA

GNU General Public License v3.0 (GPL-3.0) para el código fuente - ver [`LICENSE`](LICENSE).

La documentación (este README y sus propias traducciones - `README_spa.md`, `README_ita.md`, `README_fra.md`, `README_deu.md`, `README_zho.md`, `README_jpn.md`) está disponible bajo **Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)**. Texto completo en https://creativecommons.org/licenses/by-sa/4.0/.
