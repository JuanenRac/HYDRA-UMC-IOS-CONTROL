<p align="center">
  <img src="images/HYDRA_UMC_IOS_CONTROL_BANNER.jpg" alt="HYDRA-UMC iOS Control Banner" width="100%">
</p>

# 📱 HYDRA-UMC CONTROL (iOS)

Una app Flutter (Dart) multiplataforma que controla un robot de la plataforma [HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC) por Wi-Fi, hablando exactamente el mismo contrato [`REMOTE_API.md`](https://github.com/JuanenRac/HYDRA-UMC-STUDIO/blob/main/docs/REMOTE_API.md) que usan [HYDRA-UMC SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE) y [HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL) - descubrimiento, login, comandos atómicos por robot, y sincronización WebSocket en vivo contra un servidor [HYDRA-UMC STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO) en ejecución.

## 🔀 Por qué Flutter, no Swift nativo

Esta app tiene como objetivo iOS/iPadOS, pero está construida en **Flutter** en vez de Swift/SwiftUI: el entorno de trabajo de este repositorio es exclusivamente Windows, y un proyecto Swift nativo se puede *escribir* en Windows pero nunca *compilar o ejecutar* ahí (Xcode y el SDK de iOS son exclusivos de macOS). El propio target de escritorio Windows de Flutter permite que esta app se construya, ejecute y pruebe de verdad en esta máquina - `flutter analyze` limpio, `flutter build windows` con éxito, `flutter test` pasando, y el `.exe` compilado arrancando y renderizando sin errores en tiempo de ejecución - en vez de escribir miles de líneas de Swift a ciegas, sin forma alguna de verificar nada de ello hasta que haya un Mac disponible.

**Esto no elimina la propia restricción de Apple** - un `.ipa` real sigue requiriendo Xcode en un Mac (o un runner de CI macOS) para compilarlo y firmarlo; nada de la elección de framework cambia eso. Lo que Flutter aporta es la capacidad de verificar cada otra línea de la lógica propia de esta app (redes, estado, UI) en esta máquina hoy, y de enviar un código base idéntico a iOS más adelante sin reescribirlo.

## 🏗️ Qué está implementado

- **Login** (`lib/ui/login_screen.dart`, `lib/state/robot_view_model.dart`) - campos editables de IP/puerto del servidor más `POST /api/login` contra `admin`/`admin` (prerrellenado - la cuenta por defecto que todo servidor de este ecosistema genera por sí mismo en su primer arranque; un servidor también puede tener cuentas "operator" adicionales de menor privilegio, creadas desde Config > Users en la UI del navegador), token de sesión persistido entre arranques vía `shared_preferences`. Un botón "Scan local network" (`lib/network/discovery.dart`) encuentra servidores sin que el usuario necesite saber ya la IP.
- **Descubrimiento de red** (`lib/network/discovery.dart`) - escaneo concurrente de `GET /api/hydra-info` a través de la(s) subred(es) local(es) real(es) propia(s) de este dispositivo, derivadas del `NetworkInterface.list()` propio de `dart:io` en vez de una única suposición fija, ya que la LAN de un teléfono tiene tantas probabilidades de ser `192.168.0.x` o `10.x.x.x` como `192.168.1.x`. Recae en `192.168.1.x` solo si la enumeración de interfaces en sí vuelve vacía.
- **Sincronización de comandos atómicos** (el propio `_sendAtomicCommand()` de `lib/state/robot_view_model.dart`) - cada escritura (enable/disable/play/pause/stop/jog/valve/pump/speed/vision) usa el endpoint real `POST /api/robot/:id/command`, una carga útil pequeña y dirigida en vez de sobrescribir todo el árbol de settings, con propagación correcta de robot combinado (`combinedWith`) para los 5 comandos que la necesitan.
- **Sincronización WebSocket en vivo** (`lib/network/hydra_websocket.dart`) - siempre adjunta `?token=` a la URL de conexión (el propio upgrade `/ws` de `server.ts` lo exige incondicionalmente), maneja tanto tipos de difusión `"settings"` como `"delta"`, se reconecta automáticamente al caerse.
- **Dashboard** (`lib/ui/dashboard_screen.dart`) - tarjetas por robot, reactivas en tiempo real vía el propio `ChangeNotifier` de `Provider`, convención de LED (verde parpadeando = activo, rojo fijo = inactivo) y visualización de robot combinado (mostrada solo en el lado seguidor, resuelta por id) igualando el propio Dashboard Overview de HYDRA-UMC-STUDIO.
- **Control Manual** (`lib/ui/control_screen.dart`, `lib/ui/widgets/joystick_pad.dart`) - D-pad de jog (con/sin objetivo de mesa XY), sliders de velocidad/aceleración, interruptores de válvula/bomba, y protección real de pulsación larga en E-STOP/STOP (un toque rápido no hace nada salvo un aviso háptico + visual, solo una pulsación sostenida genuina envía el comando).
- **Cámara** (`lib/ui/camera_screen.dart`, `lib/ui/widgets/mjpeg_view.dart`) - un pequeño analizador de stream MJPEG hecho a mano (sin paquete de terceros), un estado claro de "Camera Disabled" en vez de una imagen en blanco silenciosa, y un interruptor para activar/desactivar el sistema de visión de un robot directamente desde el servidor (el comando atómico `"vision"` propio de `server.ts`).
- **Vista 3D** (`lib/ui/three_d_screen.dart`) - embebe el propio viewport 3D en tiempo real de HYDRA-UMC-STUDIO en un WebView (`?hideUI=true&robotId=&token=`), el mismo enfoque que la app de Android, por la misma razón (obtiene gratis la escena 3D real, actualmente en producción). Recae en un placeholder honesto en plataformas que `webview_flutter` no soporta (el target de escritorio Windows de este repositorio, usado para verificación de build).
- **Métricas del sistema** (`lib/state/robot_view_model.dart`) - `GET /api/system/metrics` consultado cada 5s, la misma cadencia que los otros 2 clientes, mostrado en el Dashboard.

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
  superar 9 se resetea a 0 y minor sube +1 - p. ej. `1.0.9` ->
  `1.1.0`. Major nunca se toca automáticamente.
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
│   │   └── auth_prefs.dart          # Conexion y token persistidos (shared_preferences)
│   ├── state/
│   │   └── robot_view_model.dart    # Unico ChangeNotifier que escucha cada pantalla
│   └── ui/
│       ├── login_screen.dart        # Campos de host/puerto/usuario/pass + "Scan local network"
│       ├── main_screen.dart         # Contenedor de navegacion inferior (Dashboard/Control/Camara/3D/Ajustes)
│       ├── dashboard_screen.dart    # Tarjetas por robot + barra de metricas del sistema
│       ├── control_screen.dart      # Controles de jog/velocidad/valvula/bomba/reproduccion
│       ├── camera_screen.dart       # Visor MJPEG + interruptor de vision on/off
│       ├── three_d_screen.dart      # Embebe el propio viewport 3D de STUDIO via WebView
│       ├── settings_screen.dart     # Informacion de conexion + cerrar sesion
│       └── widgets/
│           ├── joystick_pad.dart     # D-pad de jog (deliberadamente no un stick analogico, ver cabecera del archivo)
│           ├── digital_readout.dart, status_led.dart
│           └── mjpeg_view.dart       # Analizador de stream MJPEG hecho a mano
├── ios/                              # Proyecto Xcode (compilar solo desde macOS)
├── windows/                          # Target de escritorio Windows - verificacion de build sin un Mac
├── docs/ARCHITECTURE.md
├── test/widget_test.dart
├── images/
├── README.md                         # este archivo (ingles)
└── README_spa.md / README_ita.md / README_fra.md / README_deu.md  # traducciones
```

## 🔗 Proyectos Relacionados

Este proyecto es parte de un ecosistema robótico más amplio del mismo autor (JuanenRac / Electro Hobby 3D). Vale la pena conocerlo, ya que una petición podría en realidad ser sobre uno de estos en vez de sobre este repositorio:

**Plataforma HYDRA-UMC** — la célula de microfábrica multi-robot
- **[HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC)** — la placa base en sí: host Raspberry Pi CM5 + coprocesador de tiempo real STM32H745 de doble núcleo, orquestando hasta 8 brazos robóticos distribuidos por CAN-OTA/SPI-OTA. Hardware + firmware propios, GPL-3.0/CERN-OHL-S v2/CC BY-SA 4.0.
- **[HYDRA-UMC STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO)** — panel de control basado en web para HYDRA-UMC: visualización 3D multi-robot, grabación de cinemática/trayectorias, flasheo y pruebas CAN-OTA para toda la plataforma. React + Vite + Three.js.
- **[HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER)** — el backend headless (Node/Express/WebSocket) que antes venía integrado dentro del propio proceso de HYDRA-UMC STUDIO. Gestiona la API REST/WS de control de robots, la persistencia de settings.json, la autenticación JWT y el descubrimiento mDNS; STUDIO ahora es un cliente frontend estático puro que se comunica con él por red.
- **[HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL)** — app de control Android para HYDRA-UMC por Wi-Fi/Bluetooth. App real y funcional - conjunto completo de funciones de control remoto, autenticación JWT, almacenamiento cifrado de credenciales.
- **HYDRA-UMC-IOS-CONTROL** *(este repositorio)* — app de control iOS/iPadOS para HYDRA-UMC por Wi-Fi, construida en Flutter (multiplataforma, verificable en Windows sin un Mac; el empaquetado final del `.ipa` todavía necesita Xcode). App real y funcional - mismo conjunto de funciones que la app de Android.
- **[HYDRA-UMC-SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE)** — centro de comando de escritorio (Python/PySide6) para enjambres: descubrimiento de red multi-controlador, sincronización bidireccional en vivo, viewport 3D de robot real, espacio de trabajo acoplable estilo Photoshop. Real y funcional, no un placeholder.
- **[HYDRA-UMC-EDITOR-URDF](https://github.com/JuanenRac/HYDRA-UMC-EDITOR-URDF)** — creador/editor gráfico de escritorio (Python/PySide6) para el catálogo de modelos propio de este proyecto: extrae archivos fuente de GitHub o de una carpeta local, valida la viabilidad de los grados de libertad (DOF), edita color/escala/cinemática con una vista previa 3D en vivo, y envía el resultado terminado a un servidor STUDIO en ejecución. Real y funcional, no un placeholder.
- **[HYDRA-UMC-DSI](https://github.com/JuanenRac/HYDRA-UMC-DSI)** — UI táctil nativa en Flutter para la propia pantalla táctil DSI de 5"/7" de HYDRA-UMC (1280×720, misma resolución en ambos tamaños) en la Compute Module 5, controlando este mismo servidor directamente desde la placa. Scaffold real y funcional con las 6 pantallas del catálogo (dashboard, control manual, cámara, vista 3D simplificada, métricas de sistema, login) conectadas al servidor en vivo; el build real del target Linux aún no se ha ejecutado en hardware real (entorno de trabajo solo Windows hasta ahora - ver el README propio de ese proyecto).

**Plataforma URTC** — el controlador de cabezal de herramienta que lleva cada brazo robótico de HYDRA-UMC
- **[URTC](https://github.com/JuanenRac/URTC)** — Universal Robot Tool Controller: controlador de cabezal de herramienta por bus CAN basado en STM32F303, 25 perfiles de herramienta completamente implementados, actualización de firmware CAN-OTA.
- **[URTC Flasher](https://github.com/JuanenRac/URTC-FLASHER)** — herramienta de escritorio de flasheo CAN-OTA + chip completo por SWD/JTAG para placas URTC (Windows/Linux).
- **[URTC Tester](https://github.com/JuanenRac/URTC-TESTER)** — herramienta de escritorio de diagnóstico en vivo por bus CAN para placas URTC, un panel por perfil de herramienta (Windows/Linux).
- **[URTC Web Studio](https://github.com/JuanenRac/URTC-WEB-STUDIO)** — alternativa basada en navegador a las 2 herramientas de escritorio de arriba (Web Serial API + SLCAN), sin instalación local necesaria.

---

## 👤 Autor

**JuanenRac** (Electro Hobby 3D)
📧 electrohobby3d@gmail.com
📺 youtube.com/@electrohobby3d

---

## 📜 Licencia

GNU General Public License v3.0 (GPL-3.0) para el código fuente - ver [`LICENSE`](LICENSE).

La documentación (este README y sus propias traducciones - `README_spa.md`, `README_ita.md`, `README_fra.md`, `README_deu.md`) está disponible bajo **Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)**. Texto completo en https://creativecommons.org/licenses/by-sa/4.0/.
