<p align="center">
  <img src="images/HYDRA_UMC_BANNER.svg" alt="HYDRA-UMC-IOS-CONTROL banner" width="100%">
</p>

# 📱 HYDRA-UMC CONTROL (iOS)

<p align="center">
  <a href="README.md">🇺🇸 English</a> |
  <a href="README_spa.md">🇪🇸 Español</a> |
  <a href="README_fra.md">🇫🇷 Français</a> |
  <a href="README_ita.md">🇮🇹 Italiano</a> |
  <a href="README_deu.md">🇩🇪 Deutsch</a> |
  <a href="README_zho.md">🇨🇳 简体中文</a> |
  <a href="README_jpn.md">🇯🇵 日本語</a> |
  🇵🇹 <b>Português</b>
</p>


<p align="center">
  <img src="https://img.shields.io/badge/License-GPL%203.0--or--later-blue.svg" alt="GPL 3.0 or later">
  <img src="https://img.shields.io/badge/Framework-Flutter-02569B.svg" alt="Flutter">
  <img src="https://img.shields.io/badge/Language-Dart-0175C2.svg" alt="Dart">
  <img src="https://img.shields.io/badge/Platform-iOS-000000.svg" alt="iOS">
</p>


Uma aplicação Flutter multiplataforma (Dart) que controla um robô da plataforma [HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC) por Wi-Fi, falando exatamente o mesmo contrato [`REMOTE_API.md`](https://github.com/JuanenRac/HYDRA-UMC-SERVER/blob/main/docs/REMOTE_API.md) que o [HYDRA-UMC SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE) e o [HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL) usam - descoberta, início de sessão, comandos atómicos por robô e sincronização WebSocket em direto contra uma instância [HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER) em execução (o back-end headless separado do processo do próprio HYDRA-UMC STUDIO - o STUDIO é agora um cliente de frontend puro dele, tal como esta aplicação).

> **Estado de segurança (safety e security):** este ecossistema não é um sistema de segurança certificado. Ainda não existe um caminho de E-STOP por hardware, nem limites ou interlocks impostos pelo firmware, nem um comando de movimento verificado; as imagens de firmware são verificadas com CRC32 e um HMAC-SHA256 de chave partilhada, não com uma assinatura assimétrica; TLS e TLS mútuo são opcionais e estão desativados por defeito; nenhuma placa própria foi ainda montada ou testada. Leia a [base de segurança](https://github.com/JuanenRac/HYDRA-UMC-DOCS/blob/main/docs/SECURITY_BASELINE.md) e o [modelo de ameaças](https://github.com/JuanenRac/HYDRA-UMC-DOCS/blob/main/docs/THREAT_MODEL.md) antes de confiar em qualquer afirmação aqui para a segurança de uma pessoa.

## 📋 Num relance

| | |
|---|---|
| Versão | `0.2.6` |
| Maturidade | Funcional |
| Tecnologia | Flutter 3.x / Dart |
| Destino | Um iPhone ou iPad |
| Em hardware real | Ainda não: não há registo de execução em hardware real para esta versão |

## 🔀 Porquê Flutter e não Swift nativo

Esta aplicação destina-se a iOS/iPadOS, mas é construída em **Flutter** em vez de Swift/SwiftUI: o ambiente de trabalho deste repositório é só Windows, e um projeto Swift nativo pode ser *escrito* no Windows mas nunca *compilado nem executado* aí (o Xcode e o SDK do iOS são só para macOS). O alvo de desktop Windows do próprio Flutter permite que esta aplicação seja realmente compilada, executada e testada nesta máquina - `flutter analyze` limpo, `flutter build windows` com êxito, `flutter test` a passar, e o `.exe` compilado arranca e renderiza sem erros de execução - em vez de escrever milhares de linhas de Swift às cegas, sem forma de verificar nada até haver um Mac disponível.

**Isto não retira a própria restrição da Apple** - um `.ipa` real continua a exigir o Xcode num Mac (ou num executor de CI macOS) para compilar e assinar; nada na escolha da framework muda isso. O que o Flutter compra é a capacidade de verificar hoje, nesta máquina, todas as outras linhas da lógica desta aplicação (rede, estado, interface) e de distribuir mais tarde uma base de código idêntica para iOS sem reescrita.

## 🏗️ O que está implementado

- **Início de sessão** (`lib/ui/login_screen.dart`, `lib/state/robot_view_model.dart`) - IP/porta do servidor e campos de credenciais do operador editáveis, mais `POST /api/login`; nenhuma conta nem palavra-passe vem preenchida. Um servidor de produção exige credenciais de arranque configuradas explicitamente para o seu primeiro administrador, e contas adicionais de «operador», com menos privilégios, podem ser criadas em Config > Users na interface do navegador. O token de sessão persiste entre arranques no porta-chaves do iOS (`flutter_secure_storage`); o anfitrião e a porta ficam em `shared_preferences`. Um botão «Procurar na rede local» (`lib/network/discovery.dart`) encontra servidores sem que o utilizador precise de já saber o IP.
- **Descoberta de rede** (`lib/network/discovery.dart`) - dois caminhos independentes correm ao mesmo tempo a partir da folha «Procurar na rede local»: mDNS/Bonjour real (`discoverMdns()`, consulta o serviço `_hydra._tcp.local` que o `server.ts` publica através do pacote `multicast_dns` - esta aplicação é a primeira dos 3 clientes remotos do ecossistema a tê-lo) mais uma análise concorrente por força bruta de `GET /api/hydra-info` pela(s) sub-rede(s) locais reais do próprio dispositivo (`scanSubnets()`, derivada do `NetworkInterface.list()` do `dart:io` em vez de um único palpite codificado, já que a LAN de um telemóvel é tão provavelmente `192.168.0.x` ou `10.x.x.x` como `192.168.1.x`, recorrendo a `192.168.1.x` apenas se a própria enumeração de interfaces vier vazia). O mDNS falhar em silêncio numa compilação iOS sem autorização é esperado (o direito Multicast Networking da própria Apple não é concedido por um simples `flutter build ios`) - a análise de sub-rede continua a funcionar de forma independente em qualquer dos casos.
- **Porta de início de sessão biométrico** (`lib/network/biometric_helper.dart`, `lib/ui/biometric_gate_screen.dart`) - Face ID/Touch ID/Windows Hello através do `package:local_auth`, um interruptor opcional em `Definições` que condiciona a restauração, no arranque, de uma sessão guardada ainda válida (esta aplicação nunca guarda uma palavra-passe em bruto, apenas um token bearer - adaptado do desenho de repreenchimento de palavra-passe do próprio HYDRA-UMC-ANDROID-CONTROL a essa diferença).
- **Sincronização atómica de comandos** (o `_sendAtomicCommand()` do `lib/state/robot_view_model.dart`) - cada escrita (play/pause/stop/jog/válvula/bomba/velocidade/visão) usa o endpoint real `POST /api/robot/:id/command`, um payload pequeno e dirigido em vez de sobrescrever toda a árvore de definições, com a propagação correta dos robôs combinados (`combinedWith`) para os 5 comandos que a precisam.
- **Sincronização WebSocket em direto** (`lib/network/hydra_websocket.dart`) - envia o token como subprotocolo `hydra.bearer` e nunca no URL da ligação (o `server.ts` recusa `/ws?token=` por defeito), trata ambos os tipos de difusão `"settings"` e `"delta"`, volta a ligar-se automaticamente quando cai.
- **Painel** (`lib/ui/dashboard_screen.dart`) - cartões por robô, reativos em tempo real através do próprio `ChangeNotifier` do `Provider`, convenção de LED (verde a pulsar = ativo, vermelho fixo = inativo) e apresentação de robôs combinados (mostrada apenas do lado do seguidor, resolvida por id) em linha com o Dashboard Overview do próprio HYDRA-UMC-STUDIO.
- **Controlo manual** (`lib/ui/control_screen.dart`, `lib/ui/widgets/joystick_pad.dart`) - D-pad de jog (com/sem alvo da mesa XY), cursores de velocidade/aceleração, interruptores de válvula/bomba e o **STOP** global (`lib/ui/widgets/stop_all.dart`): um só toque, sem pressão longa nem confirmação, pára todos os robôs (`POST /api/stop-all`) e fica na barra superior de cada separador, incluindo o de Controlo. A resposta é mostrada robô a robô (aviso se um robô falhou ou a paragem não foi guardada; os robôs reservados por outra conta ficam assinalados), um erro de rede é repetido uma vez, um servidor acima do seu limite de pedidos ou sem essa rota é servido com a paragem por robô, e se ninguém responder fica um aviso permanente «STOP não confirmado» até um STOP posterior obter resposta. O botão redondo de paragem por robô mantém a sua proteção de pressão longa.
- **Interruptores opcionais** - dois interruptores, ambos desligados por predefinição: *Bloquear comandos com dados guardados* (Definições) retém todos os comandos exceto o STOP enquanto o ecrã mostra a cópia guardada do estado dos robôs e não o estado real, e *Não analisar redes de dados móveis nem VPN* (ecrã de início de sessão) deixa essas interfaces fora da análise da sub-rede. Os botões do D-pad de jog têm pelo menos 44 pt e o VoiceOver anuncia-os com o eixo e a direção; a imagem da câmara é fechada enquanto a app está em segundo plano.
- **Câmara** (`lib/ui/camera_screen.dart`, `lib/ui/widgets/mjpeg_view.dart`) - um pequeno analisador de fluxo MJPEG feito à mão (sem pacote de terceiros), um estado claro «Câmara desativada» em vez de uma imagem em branco silenciosa e um interruptor para ligar/desligar o sistema de visão de um robô diretamente a partir do servidor (o comando atómico `"vision"` do `server.ts`).
- **Vista 3D** (`lib/ui/three_d_screen.dart`) - embebe a vista 3D em tempo real do próprio HYDRA-UMC-STUDIO numa WebView (`?hideUI=true&robotId=&token=`), a mesma abordagem da aplicação Android e pela mesma razão (obtém de graça a cena 3D real e atualmente distribuída). Recorre a um marcador honesto nas plataformas que o `webview_flutter` não suporta (o alvo de desktop Windows deste repositório, usado para verificação de compilação).
- **Métricas do sistema** (`lib/state/robot_view_model.dart`) - `GET /api/system/metrics` consultado a cada 5 s, a mesma cadência dos outros 2 clientes, mostrado no Painel.
- **Interface em 8 idiomas** (`lib/l10n/`, pipeline padrão `flutter gen-l10n`) - inglês, espanhol, francês, alemão, italiano, japonês, chinês e português, em linha com todos os outros clientes deste ecossistema. Uma substituição persistente em `Definições > Idioma` usa por defeito o locale do SO; o `RobotViewModel.lastError` é um `HydraError` tipado em vez de texto em inglês já formatado, pelo que as mensagens de erro da lógica de negócio (falhas de início de sessão/ligação/comando) também se localizam corretamente, e não apenas a decoração estática dos ecrãs. Um teste (`test/localization_test.dart`) falha se algum idioma perder uma chave ou mudar um `{marcador}` do inglês.
- **Cache de estado offline** (`lib/network/state_cache.dart`) - a última árvore de definições conhecida persiste em disco (com atraso de 1 s) ao lado do instante real em que foi guardada, para que os ecrãs Painel/Controlo mostrem de imediato, ao arrancar, dados reais - ainda que possivelmente desatualizados - dos robôs, em vez de um estado vazio enquanto a ida e volta em direto do `connect()` ainda decorre. Um aviso real e visível (não apenas um palpite silencioso) diz «a mostrar dados em cache das HH:mm» enquanto isso se mantiver verdade. Substituído pela obtenção real no instante em que esta tem êxito.
- **Telemetria** (`lib/ui/telemetry_screen.dart`) - um registo ao estilo de terminal, do mais recente para o mais antigo, de eventos reais do ciclo de vida de ligação/início de sessão/comando, limitado a 50 entradas, com uma ação de limpar o registo - a mesma convenção «Matrix Green» do separador Telemetria do próprio HYDRA-UMC-ANDROID-CONTROL.
- **Assistente de voz na aplicação** (`lib/ui/voice_assistant_dialog.dart`) - um ícone de microfone na barra da aplicação abre uma caixa de diálogo para escrever uma pergunta ou uma ordem, enviada ao `HYDRA-UMC-VOICE-UI` pela mesma rota real `POST /api/voice/turn` do Server que o botão de voz na aplicação e o relé do Watch emparelhado do próprio HYDRA-UMC-ANDROID-CONTROL usam. Nunca envia áudio - por agora só entrada de texto, já que o reconhecimento de fala no dispositivo precisa da framework Speech nativa do iOS, que este ambiente de desenvolvimento só para Windows não consegue compilar nem verificar contra um dispositivo real/Xcode. Uma resposta nunca invoca diretamente um comando de robô.

## 🚀 Compilação

Requer o [Flutter SDK](https://docs.flutter.dev/get-started/install) (canal estável). Este repositório é compilado/verificado com o Flutter 3.47.0. Só `windows/` e `ios/` estão configuradas como plataformas neste repositório (sem pastas `android/`, `linux/`, `web/` nem `macos/`) - o Windows existe para que a lógica desta aplicação possa ser compilada e executada sem um Mac; o iOS é o alvo real.

### Scripts de compilação

```bash
./build.sh     # Git Bash / WSL - flutter pub get + flutter build windows
build.bat      # cmd.exe / PowerShell - flutter pub get + flutter build windows
```

Ambos produzem `build/windows/x64/runner/Release/hydra_umc_control.exe`, e ambos não alteram a versão da aplicação - ver [Versionamento](#-versionamento) abaixo.

### Compilação manual

```bash
flutter pub get
flutter analyze          # análise estática - não precisa de compilador
flutter test             # testes de widgets
dart run tool/bump_version.dart  # sobe a versão, tal como o build.sh/build.bat fazem
flutter build windows    # produz build/windows/x64/runner/Release/hydra_umc_control.exe
flutter run -d windows   # ou -d <id-do-dispositivo-ios> a partir de um Mac
```

**Compilar o `.ipa` real de iOS** exige o Xcode no macOS - a partir dessa máquina: `flutter build ipa` (ou abra o `ios/Runner.xcworkspace` diretamente no Xcode). Isto não pode ser feito a partir do Windows; ver «Porquê Flutter e não Swift nativo» acima.

## 🔢 Versionamento

Este repositório segue uma política de todo o ecossistema: compilar nunca altera a versão. O comando `bump` explícito (`python tools/hydra_project_tool.py bump`) executa o `tool/bump_version.dart`, que aplica:

- **Patch, estilo odómetro (base 10):** +1 em cada bump; quando passaria
  de 9 volta a 0 e é o minor que ganha +1 - p. ex. `0.0.9` -> `0.1.0`. O major
  nunca é tocado automaticamente.
- **Número de compilação** (a parte depois do `+`): um contador monótono
  simples, +1 em cada bump, sem transporte.

O mesmo script regenera o `lib/app_version.dart` (gerado, não editado à mão -
um ficheiro `const` simples, não uma nova dependência de execução como o
`package_info_plus`), que a aplicação lê em execução para mostrar a sua própria
versão no ecrã **Definições**. Consulte o [CHANGELOG.md](CHANGELOG.md) para o
histórico de versões.

## 📂 Estrutura do repositório

```text
HYDRA-UMC-IOS-CONTROL/
├── build.bat, build.sh              # flutter pub get + subida de versão + flutter build windows
├── tool/
│   └── bump_version.dart            # Subida de versão ao estilo conta-quilómetros (executada só pelo comando `bump` explícito)
├── lib/
│   ├── main.dart                    # Ponto de entrada da aplicação, ChangeNotifierProvider + porta de login
│   ├── app_version.dart             # GERADO - regenerado pelo tool/bump_version.dart, não editar à mão
│   ├── models/
│   │   ├── server_info.dart         # Entrada de descoberta/ligação - espelha o ServerInfo dos outros 2 clientes
│   │   ├── hydra_state.dart         # RobotView/ControllerView/HydraState - vistas finas e mutáveis sobre a árvore bruta do settings.json
│   │   ├── assistant_reply.dart    # modelo da resposta do assistente de voz na aplicação
│   │   └── stop_all_result.dart    # resposta do STOP global, robô a robô
│   ├── network/
│   │   ├── hydra_api_client.dart    # REST: login, definições, comando atómico de robô, métricas do sistema
│   │   ├── hydra_websocket.dart     # Cliente de sincronização em direto /ws
│   │   ├── discovery.dart           # Análise concorrente da(s) sub-rede(s) local(is) real(is) do próprio dispositivo contra GET /api/hydra-info
│   │   ├── auth_prefs.dart          # Ligação (shared_preferences) + token (porta-chaves) persistidos
│   │   ├── biometric_helper.dart    # Invólucro fino sobre o package:local_auth (porta Face ID/Touch ID)
│   │   └── state_cache.dart         # Portado do StateCache.kt do Android - último estado bom conhecido, persistido entre arranques
│   ├── state/
│   │   ├── robot_view_model.dart    # Único ChangeNotifier a que todos os ecrãs escutam
│   │   └── hydra_error.dart         # Superfície de erros tipada do RobotViewModel (sem BuildContext próprio)
│   ├── l10n/                        # Localizações geradas reais (8 idiomas) - ver o l10n.yaml na raiz do repositório
│   │   ├── app_localizations.dart   # Classe base gerada
│   │   ├── app_localizations_en.dart, _es.dart, _it.dart, _fr.dart, _de.dart, _ja.dart, _zh.dart, _pt.dart
│   │   └── language_prefs.dart      # Substituição de idioma persistida (shared_preferences)
│   └── ui/
│       ├── login_screen.dart        # Campos anfitrião/porta/utilizador/palavra-passe + «Procurar na rede local»
│       ├── biometric_gate_screen.dart # Mostrado pelo _RootGate do main.dart enquanto o Face ID/Touch ID está pendente
│       ├── main_screen.dart         # Esqueleto de navegação inferior (Painel/Controlo/Câmara/3D/Telemetria/Definições)
│       ├── dashboard_screen.dart    # Cartões por robô + barra de métricas do sistema
│       ├── control_screen.dart      # Controlos de jog/velocidade/válvula/bomba/reprodução
│       ├── camera_screen.dart       # Visualizador MJPEG + interruptor de visão ligada/desligada
│       ├── three_d_screen.dart      # Embebe a vista 3D do próprio STUDIO através de uma WebView
│       ├── telemetry_screen.dart    # Portado do TelemetryScreen.kt do Android
│       ├── voice_assistant_dialog.dart # Botão de microfone/texto na aplicação para o HYDRA-UMC-VOICE-UI
│       ├── settings_screen.dart     # Informação da ligação + terminar sessão
│       └── widgets/
│           ├── joystick_pad.dart     # D-pad de jog (deliberadamente não um manípulo analógico, ver o cabeçalho do ficheiro)
│           ├── stop_all.dart            # botão STOP global e o seu aviso de resultado / «não confirmado»
│           ├── digital_readout.dart, status_led.dart
│           └── mjpeg_view.dart       # Analisador de fluxo MJPEG feito à mão
├── ios/                              # Projeto Xcode (compilar apenas a partir do macOS)
├── windows/                          # Alvo de desktop Windows - verificação de compilação sem um Mac
├── docs/ARCHITECTURE.md
├── test/                             # widget_test, auth_prefs_test, discovery_interfaces_test, format_uptime_test, hostile_answers_test, hydra_error_test, hydra_websocket_reconnect_test, hydra_websocket_token_test, joystick_pad_test, localization_test, main_screen_cached_state_banner_test, mjpeg_lifecycle_test, robot_view_model_background_pause_test, robot_view_model_cached_state_test, robot_view_model_server_errors_test, robot_view_model_silent_refresh_test, robot_view_model_stop_all_test, saved_data_block_test, session_storage_test, state_cache_test, telemetry_log_test, voice_turn_test, websocket_uri_test
├── images/
├── README.md                         # este ficheiro
└── README_spa.md / README_ita.md / README_fra.md / README_deu.md / README_zho.md / README_jpn.md / README_por.md  # traduções
```

---

## 🔗 Projetos relacionados

Este projeto faz parte do ecossistema de robótica HYDRA-UMC do mesmo autor (JuanenRac / Electro Hobby 3D). Vale a pena conhecê-los, porque um pedido pode ser, na verdade, sobre um destes e não sobre este repositório.

**Projeto-mãe**
- **[HYDRA-UMC-SERVER](https://github.com/JuanenRac/HYDRA-UMC-SERVER)** — o back-end headless real (REST/WebSocket) com que todos os clientes de controlo realmente comunicam; o back-end contra o qual correm o início de sessão, os comandos atómicos e a sincronização WebSocket desta aplicação.

**Projetos irmãos** — também falam com a API do próprio HYDRA-UMC-SERVER, cada um como cliente próprio
- **[HYDRA-UMC-STUDIO](https://github.com/JuanenRac/HYDRA-UMC-STUDIO)** — painel web de controlo com visualização 3D em tempo real de vários robôs; a sua própria vista 3D está embebida diretamente no ecrã de Vista 3D desta aplicação através de uma WebView.
- **[HYDRA-UMC-SUITE](https://github.com/JuanenRac/HYDRA-UMC-SUITE)** — centro de comando de enxame para desktop (PySide6) para vários servidores ao mesmo tempo, empacotado como executável independente; fala exatamente o mesmo contrato `REMOTE_API.md` que esta aplicação.
- **[HYDRA-UMC-ANDROID-CONTROL](https://github.com/JuanenRac/HYDRA-UMC-ANDROID-CONTROL)** — aplicação Android nativa de controlo, com início de sessão biométrico e um companheiro Wear OS emparelhado; fala exatamente o mesmo contrato `REMOTE_API.md` que esta aplicação.
- **[HYDRA-UMC-DSI](https://github.com/JuanenRac/HYDRA-UMC-DSI)** — interface tátil nativa para o ecrã tátil DSI de 7" integrado, executada no próprio CM5.
- **[HYDRA-UMC-BRIDGE-AMR](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-AMR)** — fronteira de coordenação para frotas AGV/AMR através de um publicador MQTT VDA 5050 (testado apenas contra uma frota emulada).
- **[HYDRA-UMC-BRIDGE-CNC](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-CNC)** — coordenador de células CNC de alto nível com acesso ao estado GRBL e aos bytes de controlo (testado apenas contra um emulador).
- **[HYDRA-UMC-BRIDGE-DROIDS](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-DROIDS)** — fronteira de coordenação para droides com patas/humanoides, com um emissor de comandos para o Boston Dynamics Spot (testado apenas contra um emulador).
- **[HYDRA-UMC-BRIDGE-LASER](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-LASER)** — coordenador de células laser que lê 3 sinais GPIO (chave, caixa e interlock) (testado apenas contra um chip simulado; não pode armar nem disparar um laser).
- **[HYDRA-UMC-BRIDGE-OPENPNP](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-OPENPNP)** — coordenador seguro de fluxo de placa de alto nível para pick-and-place com OpenPnP.
- **[HYDRA-UMC-BRIDGE-PRINTER3D](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-PRINTER3D)** — fronteira de coordenação segura para impressoras 3D Moonraker/Klipper, com comandos de trabalho reais protegidos por portas.
- **[HYDRA-UMC-BRIDGE-ROS2](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-ROS2)** — coordenador com um transporte ROS 2 baseado em rclpy importado sob demanda (ainda não executado contra uma instalação ROS 2).
- **[HYDRA-UMC-BRIDGE-UAV](https://github.com/JuanenRac/HYDRA-UMC-BRIDGE-UAV)** — fronteira de coordenação para UAV com câmara, com um emissor de comandos MAVLink (testado apenas contra um emulador).

**Diretamente relacionados**
- **[HYDRA-UMC-WATCH](https://github.com/JuanenRac/HYDRA-UMC-WATCH)** — aplicação companheira WearOS com padrões de alerta tátil e um relé de voz para o telemóvel emparelhado (ainda não executada num relógio físico); o companheiro de pulso do HYDRA-UMC-ANDROID-CONTROL (só WearOS - esta aplicação iOS ainda não tem uma contraparte para Apple Watch).
- **[HYDRA-UMC-HIL-BRIDGE](https://github.com/JuanenRac/HYDRA-UMC-HIL-BRIDGE)** — encaminhador hardware-in-the-loop com um interlock de software de colisão entre a simulação e o hardware real (testado sem hardware real); a ponte que permite a esta aplicação controlar remotamente o gémeo digital, em hardware-in-the-loop.

**Também fazem parte do ecossistema**

*Hardware e plataforma centrais*
- **[HYDRA-UMC](https://github.com/JuanenRac/HYDRA-UMC)** — o desenho da placa-mãe do braço robótico: anfitrião CM5 + STM32H745 de dois núcleos, pensado para orquestrar até 8 braços de ferramenta por CAN-OTA/SPI-OTA (firmware numa fase inicial; ainda sem placa montada).
- **[HYDRA-UMC-OS](https://github.com/JuanenRac/HYDRA-UMC-OS)** — camada de produto reproduzível do Raspberry Pi OS para o CM5: agente só de leitura, configuração/perfis validados, aprovisionamento Wi-Fi de primeiro contacto.
- **[HYDRA-UMC-SDK](https://github.com/JuanenRac/HYDRA-UMC-SDK)** — o contrato JSON-Schema partilhado e a fronteira de software de controlo de trabalhos contra a qual cada bridge valida os seus comandos (não é uma função de segurança certificada).
- **[HYDRA-UMC-CONNECTOR-HUB](https://github.com/JuanenRac/HYDRA-UMC-CONNECTOR-HUB)** — registo declarativo de manifestos de adaptador e validador para conectores de máquinas externas; estende a ideia de contrato do SDK a máquinas externas sem substituir os projetos de gateway industrial.

*Backend central e clientes*
- **[HYDRA-UMC-EDITOR-URDF](https://github.com/JuanenRac/HYDRA-UMC-EDITOR-URDF)** — criador/editor gráfico de URDF para desktop que envia os modelos concluídos para o catálogo do STUDIO.
- **[HYDRA-UMC-EDITOR-STL](https://github.com/JuanenRac/HYDRA-UMC-EDITOR-STL)** — editor de modelos STL para desktop que transforma/substitui/remove/adiciona peças reais no mesmo catálogo de modelos que o HYDRA-UMC-EDITOR-URDF também edita.

*Plataforma de ferramentas URTC*
- **[URTC](https://github.com/JuanenRac/URTC)** — firmware da placa física Universal Robot Tool Controller, mais de 25 perfis de ferramenta por barramento CAN.
- **[URTC-FLASHER](https://github.com/JuanenRac/URTC-FLASHER)** — ferramenta gráfica de gravação para desktop das placas URTC, por CAN-OTA e também SWD/JTAG de chip completo.
- **[URTC-TESTER](https://github.com/JuanenRac/URTC-TESTER)** — ferramenta de diagnóstico CAN em tempo real para desktop das placas URTC, com um painel por perfil de ferramenta.
- **[URTC-WEB-STUDIO](https://github.com/JuanenRac/URTC-WEB-STUDIO)** — alternativa no navegador ao URTC-TESTER através da Web Serial API, sem instalação local.
- **[URTC-GATEWAY](https://github.com/JuanenRac/URTC-GATEWAY)** — gateway à frente do barramento CAN do URTC: lista de identificadores permitidos, limite de taxa e chave de sessão; software testado num computador, ainda não num barramento real.

*Nó de IA de visão (Hailo-8)*
- **[HYDRA-UMC-VISION-NODE](https://github.com/JuanenRac/HYDRA-UMC-VISION-NODE)** — centro de integração do pipeline de visão Hailo-8, com uma verificação real de prontidão de hardware por fase.
- **[HYDRA-UMC-DETECTION-HEF](https://github.com/JuanenRac/HYDRA-UMC-DETECTION-HEF)** — registo real de modelos compilados com verificação segura de carga por arquitetura Hailo e soma de verificação.
- **[HYDRA-UMC-VISION-STREAMER](https://github.com/JuanenRac/HYDRA-UMC-VISION-STREAMER)** — pipeline GStreamer real e gerador de configuração MediaMTX com uma fronteira de integração HailoRT real.
- **[HYDRA-UMC-VISUAL-SERVOING-API](https://github.com/JuanenRac/HYDRA-UMC-VISUAL-SERVOING-API)** — lei de correção de servovisão baseada em posição com autorização condicionada ao estado da zona; ainda sem estimativa de pose por câmara.
- **[HYDRA-UMC-SAFETY-ZONES](https://github.com/JuanenRac/HYDRA-UMC-SAFETY-ZONES)** — lógica v0 de violação de zonas, atualidade da calibração e pedido de E-STOP que lê as posições dos objetos de um ficheiro; nenhum detetor a alimenta e ainda não há E-STOP físico ligado.

*Nó de IA cognitiva (Hailo-10)*
- **[HYDRA-UMC-COGNITIVE-NODE](https://github.com/JuanenRac/HYDRA-UMC-COGNITIVE-NODE)** — centro de integração do pipeline cognitivo do Hailo-10 (orquestração de LLM/VLA/voz).
- **[HYDRA-UMC-VLA-ENGINE](https://github.com/JuanenRac/HYDRA-UMC-VLA-ENGINE)** — codificação/descodificação real de tokens de ação e geração de trajetórias para um modelo Visão-Linguagem-Ação.
- **[HYDRA-UMC-VOICE-UI](https://github.com/JuanenRac/HYDRA-UMC-VOICE-UI)** — front-end de voz real (VAD + analisador de intenções) com um relé para o relógio limitado e protegido por confirmação.
- **[HYDRA-UMC-SEMANTIC-PLANNER](https://github.com/JuanenRac/HYDRA-UMC-SEMANTIC-PLANNER)** — decomposição real de tarefas baseada em regras e recuperação semântica de erros sobre os códigos de erro do MCU.
- **[HYDRA-UMC-DOCS-QA](https://github.com/JuanenRac/HYDRA-UMC-DOCS-QA)** — pesquisa real de documentos TF-IDF só com a biblioteca padrão sobre a documentação Markdown deste ecossistema.
- **[HYDRA-UMC-LOCAL-TECHNICIAN](https://github.com/JuanenRac/HYDRA-UMC-LOCAL-TECHNICIAN)** — técnico de manutenção de IA local, protegido por políticas, para o próprio ecossistema: observa, diagnostica e propõe correções; os dois níveis de maior risco não estão implementados de propósito.

*Orquestração e enxame*
- **[HYDRA-UMC-ORCHESTRATOR](https://github.com/JuanenRac/HYDRA-UMC-ORCHESTRATOR)** — centro de integração com um contrato real de relatório de saúde gRPC/Protobuf e uma máquina de estados de missões.
- **[HYDRA-UMC-JOB-DISPATCHER](https://github.com/JuanenRac/HYDRA-UMC-JOB-DISPATCHER)** — fila real de trabalhos por prioridade com deduplicação, sobre uma API HTTP real.
- **[HYDRA-UMC-NODE-HEALING](https://github.com/JuanenRac/HYDRA-UMC-NODE-HEALING)** — vigilante real de saúde da frota por gRPC com repetição/recuo e deteção de identidade incoerente.
- **[HYDRA-UMC-PATH-PLANNER-3D](https://github.com/JuanenRac/HYDRA-UMC-PATH-PLANNER-3D)** — planeador real de trajetórias 3D baseado em RRT com validação real de colisões com obstáculos e espaço de trabalho.
- **[HYDRA-UMC-SWARM-SYNC](https://github.com/JuanenRac/HYDRA-UMC-SWARM-SYNC)** — sincronização real de estado CRDT LWW-Element-Map, testada por propriedades para a convergência de várias células.

*Gémeo digital e simulação*
- **[HYDRA-UMC-TWIN](https://github.com/JuanenRac/HYDRA-UMC-TWIN)** — centro de integração do motor de gémeo digital, com um contrato real de sincronização de compatibilidade de versões.
- **[HYDRA-UMC-PHYSICS-REPLICA](https://github.com/JuanenRac/HYDRA-UMC-PHYSICS-REPLICA)** — cinemática direta real e validação de limites de juntas sobre um subconjunto real de URDF.
- **[HYDRA-UMC-SYNTHETIC-DATA-GEN](https://github.com/JuanenRac/HYDRA-UMC-SYNTHETIC-DATA-GEN)** — gerador procedural real de cenas 2D com exportação de anotações YOLO/COCO.

*Dados e análise*
- **[HYDRA-UMC-DATALAKE](https://github.com/JuanenRac/HYDRA-UMC-DATALAKE)** — armazém real de séries temporais sobre sqlite3 com uma API HTTP real de ingestão/consulta.
- **[HYDRA-UMC-ANOMALY-DETECTOR](https://github.com/JuanenRac/HYDRA-UMC-ANOMALY-DETECTOR)** — detetor real de anomalias por FFT e linha de base estatística, com monitorização de deriva.
- **[HYDRA-UMC-PRODUCTION-REPORTS](https://github.com/JuanenRac/HYDRA-UMC-PRODUCTION-REPORTS)** — cálculo real de OEE/disponibilidade sobre o histórico do DATALAKE, com exportação CSV reprodutível.
- **[HYDRA-UMC-TELEMETRY-COLLECTOR](https://github.com/JuanenRac/HYDRA-UMC-TELEMETRY-COLLECTOR)** — pipeline real de ingestão CAN/WebSocket para o DATALAKE, com deduplicação por sequência.

*Gateway industrial*
- **[HYDRA-UMC-GATEWAY-INDUSTRIAL](https://github.com/JuanenRac/HYDRA-UMC-GATEWAY-INDUSTRIAL)** — centro de integração que retransmite para protocolos industriais, com uma camada real de lista de comandos permitidos e contrapressão.
- **[HYDRA-UMC-OPCUA-SERVER](https://github.com/JuanenRac/HYDRA-UMC-OPCUA-SERVER)** — espaço de endereços OPC-UA real, verificado com uma sessão de cliente real do protocolo binário.
- **[HYDRA-UMC-MQTT-BROKER](https://github.com/JuanenRac/HYDRA-UMC-MQTT-BROKER)** — broker MQTT real com autenticação opcional por cliente e ACL de tópicos.
- **[HYDRA-UMC-MTCONNECT-ADAPTER](https://github.com/JuanenRac/HYDRA-UMC-MTCONNECT-ADAPTER)** — endpoints XML MTConnect `/probe` e `/current` reais com saída em modo degradado.

*Ferramentas complementares e operações do ecossistema*
- **[HYDRA-UMC-DASHBOARD-AI](https://github.com/JuanenRac/HYDRA-UMC-DASHBOARD-AI)** — painéis de Resumos Inteligentes e Realce de Anomalias sobre o DATALAKE/ANOMALY-DETECTOR, com um recurso estatístico honesto.
- **[HYDRA-UMC-TOOL-CLI](https://github.com/JuanenRac/HYDRA-UMC-TOOL-CLI)** — CLI da frota com um contrato de códigos de saída real e estável, um cliente vivo genuíno da API do HYDRA-UMC-SERVER.
- **[URTC-SMART-RACK](https://github.com/JuanenRac/URTC-SMART-RACK)** — firmware de um rack de montagem de placas com descodificação real do ID da ferramenta e lógica de pré-aquecimento Smart Idle.
- **[URTC-VISION-TOOL](https://github.com/JuanenRac/URTC-VISION-TOOL)** — firmware mais um companheiro de visão em Python real para uma cabeça de ferramenta de inspeção térmica/RGB.
- **[HYDRA-UMC-UPDATER](https://github.com/JuanenRac/HYDRA-UMC-UPDATER)** — ferramenta administrativa de desktop que descobre, clona e atualiza todos os repositórios deste ecossistema.
- **[HYDRA-UMC-OS-REBUILDER](https://github.com/JuanenRac/HYDRA-UMC-OS-REBUILDER)** — ferramenta de desktop para Windows/Linux que constrói uma imagem do CM5 pronta a gravar com as versões mais recentes do ecossistema, com configuração de primeiro arranque de Wi-Fi/utilizador/SSH ao estilo do Raspberry Pi Imager.
- **[HYDRA-UMC-OPS-AGENT](https://github.com/JuanenRac/HYDRA-UMC-OPS-AGENT)** — coordenador de incidentes de manutenção: um papel de borda de poucos privilégios recolhe um inventário/estado higienizado, um papel de plano de controlo mostra-o só de leitura e pede a um fornecedor de IA que sugira um diagnóstico; nunca aplica um patch nem implanta nada.
- **[HYDRA-UMC-DEV-SERVER](https://github.com/JuanenRac/HYDRA-UMC-DEV-SERVER)** — anfitrião de desenvolvimento reproduzível (Raspberry Pi 5 / CM5) que guarda o código-fonte do ecossistema e executa tarefas limitadas de compilação/teste numa fila durável; um papel de desenvolvimento dedicado, explicitamente não um CM5 operacional.

---

## 📚 Documentação e comunidade

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — o contrato de transporte Wi-Fi que esta aplicação fala contra o `server.ts` (endpoint a endpoint), porque é que ainda não há caminho por Bluetooth, o mecanismo real de descoberta por dois caminhos e a relação desta aplicação com o resto do ecossistema.
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — pilha tecnológica e diretrizes de código para um pull request.
- **[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)** — as normas de comportamento esperadas nesta comunidade.
- **[SECURITY.md](SECURITY.md)** — como comunicar uma vulnerabilidade e as áreas de segurança em que este projeto se concentra.
- **[SUPPORT.md](SUPPORT.md)** — onde fazer perguntas e comunicar erros.
- **[LICENSE.md](LICENSE.md)** — a licença deste projeto.

## 👤 AUTOR
**JuanenRac** (Electro Hobby 3D)
📧 electrohobby3d@gmail.com
📺 [youtube.com/@electrohobby3d](https://youtube.com/@electrohobby3d)

## 📜 LICENÇA

GNU General Public License v3.0 or later (GPL-3.0-or-later) para o código-fonte - veja [`LICENSE`](LICENSE).

A documentação (este README e as suas próprias traduções - `README_spa.md`, `README_ita.md`, `README_fra.md`, `README_deu.md`, `README_zho.md`, `README_jpn.md`, `README_por.md`) está disponível sob a **Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)**. Texto completo em https://creativecommons.org/licenses/by-sa/4.0/.

