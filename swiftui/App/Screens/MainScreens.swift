// HYDRA-UMC-IOS-CONTROL - the app in use: the header (with the place of the STOP), the bottom bar and the pages. Control is in ControlScreen.swift; Cameras and Alerts are still skeletons.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import SwiftUI
import HydraCore

struct MainView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            TabView(selection: $model.selectedTab) {
                ForEach(MainTab.allCases) { tab in
                    page(tab)
                        .tabItem { Label(model.tr(tab.titleKey), systemImage: tab.symbol) }
                        .tag(tab)
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
    }

    @ViewBuilder
    private func page(_ tab: MainTab) -> some View {
        switch tab {
        case .home: HomeView()
        case .control: ControlView()
        case .cameras: PendingView(tab: tab)
        case .alerts: PendingView(tab: tab)
        case .more: MoreView()
        }
    }
}

struct HeaderView: View {
    @EnvironmentObject var model: AppModel

    private var status: String {
        let key: String
        switch model.controller.link {
        case .connected: key = "statusOnline"
        case .connecting: key = "statusConnecting"
        case .disconnected: key = "statusUnreachable"
        }
        return model.tr(key, ["server": model.controller.server?.name ?? ""])
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HydraMark(size: 34)
                Text("HYDRA-UMC").font(.system(size: 18, weight: .black)).kerning(2).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                // the STOP is drawn here by its own window, above everything
                Color.clear.frame(width: CGFloat(StopLayout.width), height: CGFloat(StopLayout.height))
            }
            .padding(.horizontal, CGFloat(StopLayout.margin))
            .frame(height: CGFloat(StopLayout.headerHeight))
            HStack(spacing: 8) {
                StatusDot(color: model.controller.linkOk ? Theme.ok : Theme.amber)
                Text(status).font(.system(size: 12)).foregroundColor(Theme.muted).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
            // on every page: what is shown may no longer be true
            if model.controller.isStale, let at = model.controller.stateTime {
                Text(model.tr("savedDataBanner", ["time": model.time(at)]))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Theme.amber)
                    .accessibilityIdentifier("saved-data-banner")
            }
            Rectangle().fill(Theme.outline).frame(height: 1)
        }
    }
}

struct Page<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(14)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
    }
}

struct RobotList: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.controller.robots.isEmpty {
            Text(model.tr("robotsNone")).font(.system(size: 13)).foregroundColor(Theme.muted)
        } else {
            ForEach(model.controller.robots) { robot in
                Panel {
                    HStack(spacing: 12) {
                        IconBadge(symbol: "gearshape.2", tint: model.controller.linkOk ? Theme.accent : Theme.muted)
                        Text(robot.name).font(.system(size: 14, weight: .semibold))
                    }
                }
            }
        }
    }
}

struct PendingView: View {
    @EnvironmentObject var model: AppModel
    let tab: MainTab

    var body: some View {
        Page {
            ScreenTitle(symbol: tab.symbol, title: model.tr(tab.titleKey))
            Panel(tint: Theme.amber) { Text(model.tr("notYet")).font(.system(size: 13)) }
        }
    }
}

/// The switches of control. Every one that lets something move starts off.
struct ControlSettings: View {
    @EnvironmentObject var model: AppModel

    private var control: RobotControl { model.controller.control }

    private func toggle(_ title: String, _ hint: String, _ value: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { value }, set: set)) {
            VStack(alignment: .leading) {
                Text(model.tr(title)).font(.system(size: 14, weight: .semibold))
                Text(model.tr(hint)).font(.system(size: 12)).foregroundColor(Theme.muted)
            }
        }
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.tr("navControl")).font(.system(size: 15, weight: .bold))
                toggle("settingsListenOnly", "settingsListenOnlySubtitle", control.listenOnlyGeneral) { control.setListenOnly($0) }
                    .accessibilityIdentifier("switch-listen-only")
                toggle("settingsListenOnlyServer", "settingsListenOnlyServerSubtitle", control.listenOnlyThisServer) { control.setListenOnlyThisServer($0) }
                toggle("settingsBlockCachedCommands", "settingsBlockCachedCommandsSubtitle", control.blockOnSavedData) { control.setBlockOnSavedData($0) }
                toggle("settingsConfirmPlay", "settingsConfirmPlaySubtitle", control.confirmPlay) { control.setConfirmPlay($0) }
                toggle("homeResetSwitchLabel", "homeResetSwitchHint", control.homeResetEnabled) { control.setHomeResetEnabled($0) }
                    .accessibilityIdentifier("switch-home-reset")
                toggle("deadManSwitchLabel", "deadManSwitchHint", control.deadManEnabled) { control.setDeadManEnabled($0) }
                    .accessibilityIdentifier("switch-dead-man")
                toggle("linkBlockSwitchLabel", "linkBlockSwitchHint", control.blockOnBadLink) { control.setBlockOnBadLink($0) }
                toggle("linkIndicatorSwitchLabel", "linkIndicatorSwitchHint", control.linkIndicator) { control.setLinkIndicator($0) }
                Text(model.tr("accessConditionalLabel")).font(.system(size: 14, weight: .semibold))
                Picker(model.tr("accessConditionalLabel"), selection: Binding(get: { control.conditionalMode }, set: { control.setConditionalMode($0) })) {
                    Text(model.tr("commonOff")).tag(ConditionalMode.off)
                    Text(model.tr("commonStandard")).tag(ConditionalMode.standard)
                    Text(model.tr("accessConditionalStrict")).tag(ConditionalMode.strict)
                }
                .pickerStyle(.segmented)
                Text(model.tr("accessConditionalHint")).font(.system(size: 12)).foregroundColor(Theme.muted)
            }
        }
    }
}

struct MoreView: View {
    @EnvironmentObject var model: AppModel
    @State private var sheet: MoreSheet?
    @State private var askSignOut = false

    enum MoreSheet: String, Identifiable {
        case security, help, about
        var id: String { rawValue }
    }

    private static let languageNames = ["en": "English", "es": "Español", "de": "Deutsch", "fr": "Français", "it": "Italiano", "ja": "日本語", "zh": "中文", "pt": "Português"]

    var body: some View {
        Page {
            ScreenTitle(symbol: MainTab.more.symbol, title: model.tr("navMore"))
            MenuRow(symbol: "lock.shield", title: model.tr("moreSecurityTitle"), subtitle: model.tr("securityIntro")) { sheet = .security }
                .accessibilityIdentifier("more-security")
            Panel {
                Toggle(isOn: Binding(get: { model.controller.biometricEnabled }, set: { on in
                    Task { await model.controller.setBiometric(on, reason: model.tr("biometricReason")) }
                })) {
                    VStack(alignment: .leading) {
                        Text(model.tr("settingsRequireBiometric")).font(.system(size: 14, weight: .semibold))
                        Text(model.tr("settingsRequireBiometricSubtitle")).font(.system(size: 12)).foregroundColor(Theme.muted)
                    }
                }
                Toggle(isOn: Binding(get: { model.controller.pairingEnabled }, set: { model.controller.setPairing($0) })) {
                    Text(model.tr("pairingSwitchLabel")).font(.system(size: 14, weight: .semibold))
                }
                if let message = model.controller.message { Text(model.text(message)).font(.system(size: 13)).foregroundColor(Theme.alert) }
            }
            ControlSettings()
            Panel {
                Picker(model.tr("commonLanguage"), selection: Binding(get: { model.controller.chosenLanguage ?? "" }, set: { model.controller.setLanguage($0.isEmpty ? nil : $0) })) {
                    Text(model.tr("languageSystem")).tag("")
                    ForEach(Translator.languages, id: \.self) { Text(MoreView.languageNames[$0] ?? $0).tag($0) }
                }
                .pickerStyle(.menu)
            }
            MenuRow(symbol: "questionmark.circle", title: model.tr("helpTitle"), subtitle: nil) { sheet = .help }
            MenuRow(symbol: "info.circle", title: model.tr("aboutTitle"), subtitle: model.tr("aboutVersion", ["version": AppModel.version])) { sheet = .about }
                .accessibilityIdentifier("more-about")
            MenuRow(symbol: "arrow.left.arrow.right", title: model.tr("moreChangeServer"), subtitle: model.tr("moreChangeServerText")) { model.controller.leaveServer() }
                .accessibilityIdentifier("more-change-server")
            MenuRow(symbol: "rectangle.portrait.and.arrow.right", title: model.tr("commonSignOut"), subtitle: model.controller.server?.name, tint: Theme.alert) { askSignOut = true }
                .accessibilityIdentifier("more-signout")
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .security: SecuritySheet()
            case .help: HelpSheet()
            case .about: AboutSheet()
            }
        }
        .alert(model.tr("signOutQuestion"), isPresented: $askSignOut) {
            Button(model.tr("commonSignOut"), role: .destructive) { model.controller.logout() }
            Button(model.tr("commonCancel"), role: .cancel) {}
        }
    }
}
