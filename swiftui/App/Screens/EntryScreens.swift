// HYDRA-UMC-IOS-CONTROL - what is seen before the app is in use: start, first use, the lock and the sign-in.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import SwiftUI
import HydraCore

struct Backdrop: View {
    var body: some View {
        LinearGradient(colors: [Color(hex: 0x0A2338), Theme.background], startPoint: .top, endPoint: .center).ignoresSafeArea()
    }
}

struct Brand: View {
    let tagline: String

    var body: some View {
        VStack(spacing: 10) {
            HydraMark()
            Text("HYDRA-UMC").font(.system(size: 28, weight: .black)).kerning(5).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.6)
            Text(tagline).font(.system(size: 14)).foregroundColor(Theme.muted).multilineTextAlignment(.center)
        }
        .padding(.vertical, 12)
    }
}

struct StartingView: View {
    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 20) {
                Brand(tagline: "")
                ProgressView().tint(Theme.accent)
            }
        }
    }
}

struct FirstRunView: View {
    @EnvironmentObject var model: AppModel

    private func step(_ symbol: String, _ title: String, _ text: String, tint: Color = Theme.accent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(symbol: symbol, tint: tint, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                Text(text).font(.system(size: 12)).foregroundColor(Theme.muted)
            }
        }
    }

    private func leave(_ action: AppModel.LoginAction?) {
        model.loginAction = action
        model.controller.finishFirstRun()
    }

    var body: some View {
        ZStack {
            Backdrop()
            ScrollView {
                VStack(spacing: 14) {
                    Brand(tagline: model.tr("firstRunSubtitle"))
                    Panel {
                        step("wifi", model.tr("firstRunFindTitle"), model.tr("firstRunFindText"))
                        step("person", model.tr("firstRunAccountTitle"), model.tr("firstRunAccountText"))
                        step("hand.raised.fill", model.tr("firstRunStopTitle"), model.tr("firstRunStopText"), tint: Theme.alert)
                    }
                    Button(model.tr("firstRunSearch")) { leave(.search) }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("first-search")
                    Button(model.tr("firstRunHaveQr")) { leave(.scan) }.buttonStyle(PrimaryButtonStyle(secondary: true))
                    Button(model.tr("firstRunByHand")) { leave(nil) }.font(.system(size: 14, weight: .semibold)).padding(8).accessibilityIdentifier("first-by-hand")
                }
                .padding(20)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct LockedView: View {
    @EnvironmentObject var model: AppModel

    private func unlock() {
        Task { await model.controller.unlock(reason: model.tr("biometricReason")) }
    }

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 14) {
                Brand(tagline: model.tr("biometricUnlockToReconnect", ["server": model.controller.server?.name ?? ""]))
                if let message = model.controller.message { Text(model.text(message)).font(.system(size: 13)).foregroundColor(Theme.alert) }
                Button(model.tr("biometricUnlock"), action: unlock).buttonStyle(PrimaryButtonStyle())
                Button(model.tr("biometricSignOutInstead")) { model.controller.logout() }.font(.system(size: 14, weight: .semibold)).padding(8)
            }
            .padding(24)
            .frame(maxWidth: 520)
        }
        .task { unlock() }
    }
}

struct LoginView: View {
    @EnvironmentObject var model: AppModel
    @State private var username = ""
    @State private var password = ""
    @State private var code = ""
    @State private var showPassword = false
    @State private var sheet: LoginSheet?
    @State private var askPairing = false

    enum LoginSheet: String, Identifiable {
        case search, scan, security, help, about
        var id: String { rawValue }
    }

    private var address: ServerAddress? { ServerAddress.parse(host: model.formHost, port: model.formPort) }
    private var canSignIn: Bool { !model.controller.signingIn && !username.isEmpty && !password.isEmpty && !model.formHost.isEmpty }

    private func signIn() {
        guard canSignIn else { return }
        Task {
            await model.controller.login(host: model.formHost, port: model.formPort, username: username, password: password, code: code)
            if model.controller.screen == .main { password = ""; code = "" }
        }
    }

    private func scanCode() {
        if model.controller.pairingEnabled { sheet = .scan } else { askPairing = true }
    }

    var body: some View {
        ZStack {
            Backdrop()
            ScrollView {
                VStack(spacing: 12) {
                    HStack(spacing: 18) {
                        Spacer()
                        Button { sheet = .help } label: { Image(systemName: "questionmark.circle").font(.title2) }.accessibilityLabel(model.tr("helpTitle")).accessibilityIdentifier("login-help")
                        Button { sheet = .about } label: { Image(systemName: "info.circle").font(.title2) }.accessibilityLabel(model.tr("aboutTitle"))
                    }
                    .foregroundColor(Theme.muted)
                    Brand(tagline: model.tr("tagline"))
                    card
                    Text(model.tr("loginPasswordNotKept") + "\n" + model.tr("stopPhysical"))
                        .font(.system(size: 12)).foregroundColor(Theme.muted).multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if username.isEmpty { username = model.controller.lastUsername }
            switch model.loginAction {
            case .search?: sheet = .search
            case .scan?: scanCode()
            case nil: break
            }
            model.loginAction = nil
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .search: DiscoverySheet()
            case .scan: PairingSheet()
            case .security: SecuritySheet()
            case .help: HelpSheet()
            case .about: AboutSheet()
            }
        }
        .alert(model.tr("pairingOffTitle"), isPresented: $askPairing) {
            Button(model.tr("pairingTurnOn")) {
                model.controller.setPairing(true)
                sheet = .scan
            }
            Button(model.tr("commonCancel"), role: .cancel) {}
        } message: {
            Text(model.tr("pairingSwitchHint"))
        }
    }

    private var card: some View {
        Panel {
            Button(action: scanCode) { Label(model.tr("loginScanQr"), systemImage: "qrcode.viewfinder") }.buttonStyle(PrimaryButtonStyle(secondary: true))
            if !model.controller.savedServers.isEmpty {
                Text(model.tr("loginSavedServers")).font(.system(size: 12)).foregroundColor(Theme.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.controller.savedServers) { saved in
                            Button(saved.name) { model.fill(saved.address) }
                                .font(.system(size: 13, weight: address?.key == saved.id ? .bold : .regular))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(address?.key == saved.id ? Theme.accent : Theme.outline))
                                .contextMenu { Button(model.tr("loginForget"), role: .destructive) { model.controller.forget(saved) } }
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                TextField(model.tr("loginServerIp"), text: $model.formHost).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("login-host")
                    .textFieldStyle(.roundedBorder)
                TextField(model.tr("commonPort"), text: $model.formPort).keyboardType(.numberPad).accessibilityIdentifier("login-port").textFieldStyle(.roundedBorder).frame(width: 80)
            }
            Button { sheet = .search } label: { Label(model.tr("loginScanNetwork"), systemImage: "dot.radiowaves.left.and.right") }.font(.system(size: 14, weight: .semibold))
            TextField(model.tr("commonUsername"), text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder).accessibilityIdentifier("login-user")
            HStack {
                Group {
                    if showPassword { TextField(model.tr("commonPassword"), text: $password) } else { SecureField(model.tr("commonPassword"), text: $password) }
                }
                .textContentType(.password).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder).accessibilityIdentifier("login-password")
                .submitLabel(.go).onSubmit(signIn)
                Button { showPassword.toggle() } label: { Image(systemName: showPassword ? "eye.slash" : "eye") }
                    .accessibilityLabel(model.tr(showPassword ? "loginHidePassword" : "loginShowPassword"))
            }
            secondFactor
            if let message = model.controller.message {
                Text(model.text(message)).font(.system(size: 13)).foregroundColor(Theme.alert).accessibilityIdentifier("login-error")
            }
            Button(model.tr(model.controller.signingIn ? "loginSigningIn" : "loginSignIn"), action: signIn)
                .buttonStyle(PrimaryButtonStyle()).disabled(!canSignIn).accessibilityIdentifier("login-submit")
            Button(model.tr("securityOpen")) { sheet = .security }.font(.system(size: 13, weight: .semibold))
            Button(model.tr("loginCantConnect")) { sheet = .help }.font(.system(size: 13, weight: .semibold))
        }
    }

    @ViewBuilder
    private var secondFactor: some View {
        if model.controller.secondFactor != .none {
            Text(secondFactorText).font(.system(size: 13)).foregroundColor(Theme.amber)
            TextField(model.tr("loginCodeLabel"), text: $code).textContentType(.oneTimeCode).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder).accessibilityIdentifier("login-code")
            Text(model.tr("loginCodeHint")).font(.system(size: 12)).foregroundColor(Theme.muted)
        }
    }

    private var secondFactorText: String {
        switch model.controller.secondFactor {
        case .wrong: return model.tr("loginCodeWrong")
        case .wait(let seconds): return model.tr("loginCodeWait", ["seconds": String(seconds)])
        case .needed, .none: return model.tr("loginCodeNeeded")
        }
    }
}
