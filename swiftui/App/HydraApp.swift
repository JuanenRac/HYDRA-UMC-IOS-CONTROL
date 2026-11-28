// HYDRA-UMC-IOS-CONTROL - the native iPhone and iPad app of HYDRA-UMC (in development, next to the published Flutter app).
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import SwiftUI
import HydraCore

@main
struct HydraApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .task { await model.start() }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        model.becameActive()
                    } else if phase == .background {
                        model.enteredBackground()
                    } else {
                        // a call or the control centre over the app: a held jog ends
                        model.controller.control.interrupt()
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch model.controller.screen {
            case .starting: StartingView()
            case .welcome: FirstRunView()
            case .locked: LockedView()
            case .login: LoginView()
            case .main: MainView()
            }
        }
        .background(WindowReader { window in model.stopWindows.attach(model: model, host: window) }.ignoresSafeArea())
        .alert(model.tr("pairingDialogTitle"), isPresented: Binding(get: { model.controller.pendingPairing != nil }, set: { if !$0 { model.controller.dismissPairing() } }), presenting: model.controller.pendingPairing) { _ in
            Button(model.tr("pairingDialogConfirm")) { model.controller.confirmPairing() }
            Button(model.tr("commonCancel"), role: .cancel) { model.controller.dismissPairing() }
        } message: { offer in
            Text([
                model.tr("pairingDialogMessage", ["name": offer.name, "host": offer.address.host, "port": String(offer.address.port)]),
                model.tr("pairingDialogFingerprint", ["fingerprint": Fingerprint.display(offer.fingerprint)]),
                model.tr("pairingDialogPinReplace"),
            ].joined(separator: "\n\n"))
        }
    }
}
