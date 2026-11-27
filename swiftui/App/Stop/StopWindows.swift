// HYDRA-UMC-IOS-CONTROL - the STOP lives in windows of its own, above alerts, sheets, menus and full-screen pages, so a press is never taken by a dialog.
// Each window is only as large as what it shows, so everything else stays pressable. A close or cancel button of a sheet goes on the left for that reason.
// (The windows of the system, such as a permission question or Face ID, stay above any app.)
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import SwiftUI
import UIKit
import HydraCore

@MainActor
final class StopWindows {
    private weak var model: AppModel?
    private weak var host: UIWindow?
    private var button: UIWindow?
    private var banner: UIWindow?

    func attach(model: AppModel, host: UIWindow) {
        self.model = model
        self.host = host
        update()
    }

    private func make(_ root: AnyView, in scene: UIWindowScene) -> UIWindow {
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        let controller = UIHostingController(rootView: root)
        controller.view.backgroundColor = .clear
        window.rootViewController = controller
        window.overrideUserInterfaceStyle = .dark
        return window
    }

    private func frame(_ layout: StopLayout.Frame) -> CGRect { CGRect(x: layout.x, y: layout.y, width: layout.width, height: layout.height) }

    /// Shows, places or removes the windows according to the state. Never takes the keyboard focus.
    func update() {
        guard let model, let host, let scene = host.windowScene, model.controller.showsStop else {
            button?.isHidden = true
            banner?.isHidden = true
            button = nil
            banner = nil
            return
        }
        let screen = scene.coordinateSpace.bounds
        let insets = host.safeAreaInsets
        let stop = button ?? make(AnyView(TopStopButton(model: model)), in: scene)
        button = stop
        stop.frame = frame(StopLayout.button(screenWidth: Double(screen.width), safeTop: Double(insets.top), safeRight: Double(insets.right)))
        stop.isHidden = false

        guard model.controller.stopUnconfirmed || model.controller.stopResult != nil else {
            banner?.isHidden = true
            banner = nil
            return
        }
        let measure = UIHostingController(rootView: StopBannerContent(model: model))
        let height = measure.sizeThatFits(in: CGSize(width: screen.width, height: .greatestFiniteMagnitude)).height
        let answer = banner ?? make(AnyView(ScrollView { StopBannerContent(model: model) }.ignoresSafeArea()), in: scene)
        banner = answer
        answer.frame = frame(StopLayout.banner(screenWidth: Double(screen.width), screenHeight: Double(screen.height), safeTop: Double(insets.top), contentHeight: Double(height)))
        answer.isHidden = false
    }
}

/// Finds the window of the app (for the size and the safe area) and tells when it changes.
struct WindowReader: UIViewRepresentable {
    let found: (UIWindow) -> Void

    final class Probe: UIView {
        var found: ((UIWindow) -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); report() }
        override func layoutSubviews() { super.layoutSubviews(); report() }
        private func report() {
            guard let window else { return }
            DispatchQueue.main.async { [weak self] in self?.found?(window) }
        }
    }

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.isUserInteractionEnabled = false
        view.found = found
        return view
    }

    func updateUIView(_ view: Probe, context: Context) { view.found = found }
}
