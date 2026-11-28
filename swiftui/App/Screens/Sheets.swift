// HYDRA-UMC-IOS-CONTROL - the sheets: search of servers, pairing, security of the connection, help and about.
// Their close button is on the left: the top right corner belongs to the STOP.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import SwiftUI
import AVFoundation
import UIKit
import HydraCore

struct SheetFrame<Content: View>: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) { content }
                    .padding(16)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.tr("commonClose")) { dismiss() }.accessibilityIdentifier("sheet-close")
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct DiscoverySheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetFrame(model.tr("discoveryTitle")) {
            ForEach(model.found) { server in
                MenuRow(symbol: "server.rack", title: server.name, subtitle: "\(server.address.host):\(server.address.port)") {
                    model.fill(server.address)
                    dismiss()
                }
            }
            if model.searching {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(model.tr("loginScanSearching")).font(.system(size: 13)).foregroundColor(Theme.muted)
                }
            } else if model.found.isEmpty {
                Text(model.tr("loginScanNoneFound")).font(.system(size: 13)).foregroundColor(Theme.muted)
            }
            Panel(tint: Theme.amber) {
                Text(model.tr("discoveryNotThere")).font(.system(size: 14, weight: .semibold))
                Text(model.tr("discoverySteps")).font(.system(size: 12)).foregroundColor(Theme.muted)
            }
            Toggle(model.tr("loginScanSkipMobileVpn"), isOn: Binding(get: { model.controller.skipMobileAndVpn }, set: { model.controller.skipMobileAndVpn = $0; model.startSearch() }))
                .font(.system(size: 13))
            Button(model.tr("commonRetry")) { model.startSearch() }.buttonStyle(PrimaryButtonStyle())
            Button(model.tr("firstRunByHand")) { dismiss() }.buttonStyle(PrimaryButtonStyle(secondary: true))
        }
        .onAppear { model.startSearch() }
        .onDisappear { model.stopSearch() }
    }
}

struct PairingSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var camera = AVCaptureDevice.authorizationStatus(for: .video)

    /// The sheet closes first, so the question of the pairing is not hidden under it.
    private func read(_ text: String) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { model.controller.receivePairing(text) }
    }

    var body: some View {
        SheetFrame(model.tr("loginScanQr")) {
            if AVCaptureDevice.default(for: .video) != nil && camera != .denied && camera != .restricted {
                QrScanner(found: read).frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                Panel(tint: Theme.amber) { Text(model.tr("pairingCameraUnavailable")).font(.system(size: 13)) }
            }
            TextField(model.tr("pairingPasteLabel"), text: $link).textInputAutocapitalization(.never).autocorrectionDisabled().hydraField()
            Button(model.tr("pairingPasteButton")) { read(link) }.buttonStyle(PrimaryButtonStyle()).disabled(link.isEmpty)
            Text(model.tr("pairingSwitchHint")).font(.system(size: 12)).foregroundColor(Theme.muted)
        }
        .task {
            if camera == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
                camera = AVCaptureDevice.authorizationStatus(for: .video)
            }
        }
    }
}

/// The camera reading a QR code; it reports the first one and stops.
struct QrScanner: UIViewRepresentable {
    let found: (String) -> Void

    final class Preview: UIView, AVCaptureMetadataOutputObjectsDelegate {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        let session = AVCaptureSession()
        var found: ((String) -> Void)?
        private let queue = DispatchQueue(label: "hydra.qr")
        private var done = false

        func start() {
            guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = output.availableMetadataObjectTypes.contains(.qr) ? [.qr] : []
            (layer as? AVCaptureVideoPreviewLayer)?.session = session
            (layer as? AVCaptureVideoPreviewLayer)?.videoGravity = .resizeAspectFill
            queue.async { [session] in session.startRunning() }
        }

        func stop() { queue.async { [session] in session.stopRunning() } }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !done, let text = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
            done = true
            stop()
            found?(text)
        }
    }

    func makeUIView(context: Context) -> Preview {
        let view = Preview()
        view.found = found
        if AVCaptureDevice.authorizationStatus(for: .video) == .authorized { view.start() }
        return view
    }

    func updateUIView(_ view: Preview, context: Context) {
        if view.session.inputs.isEmpty, AVCaptureDevice.authorizationStatus(for: .video) == .authorized { view.start() }
    }

    static func dismantleUIView(_ view: Preview, coordinator: ()) { view.stop() }
}

struct SecuritySheet: View {
    @EnvironmentObject var model: AppModel
    @State private var fingerprint = ""
    @State private var read: (fingerprint: String, subject: String)?
    @State private var notice: String?

    private var address: ServerAddress? {
        if model.controller.signedIn { return model.controller.server?.address }
        return ServerAddress.parse(host: model.formHost, port: model.formPort)
    }

    private func toggle(_ keyPath: WritableKeyPath<TlsSettings, Bool>) -> Binding<Bool> {
        Binding(get: { model.controller.tlsSettings[keyPath: keyPath] }, set: { value in
            var settings = model.controller.tlsSettings
            settings[keyPath: keyPath] = value
            model.controller.setTls(settings)
        })
    }

    private func save(_ value: String) {
        guard let address else { notice = model.tr("securityNeedsHost"); return }
        if !value.isEmpty && Fingerprint.normalize(value) == nil { notice = model.tr("securityFingerprintInvalid"); return }
        model.controller.setTls(model.controller.tlsSettings.withPin(value.isEmpty ? nil : value, for: address))
        fingerprint = Fingerprint.normalize(value) ?? ""
        read = nil
        notice = nil
    }

    private func fetch() {
        guard let address else { notice = model.tr("securityNeedsHost"); return }
        Task {
            if let found = await CertificateReader.read(address) {
                read = found
                notice = nil
            } else {
                notice = model.tr("securityFetchFailed", ["server": "\(address.host):\(address.port)"])
            }
        }
    }

    var body: some View {
        SheetFrame(model.tr("moreSecurityTitle")) {
            Text(model.tr("securityIntro")).font(.system(size: 13)).foregroundColor(Theme.muted)
            Panel {
                Toggle(isOn: toggle(\.allowPlainHttp)) {
                    VStack(alignment: .leading) {
                        Text(model.tr("securityAllowPlain")).font(.system(size: 14))
                        Text(model.tr("securityAllowPlainSubtitle")).font(.system(size: 12)).foregroundColor(Theme.muted)
                    }
                }
                Toggle(isOn: toggle(\.allowPlainRemote)) {
                    VStack(alignment: .leading) {
                        Text(model.tr("securityAllowRemote")).font(.system(size: 14))
                        Text(model.tr("securityAllowRemoteSubtitle")).font(.system(size: 12)).foregroundColor(Theme.muted)
                    }
                }
                .disabled(!model.controller.tlsSettings.allowPlainHttp)
            }
            Panel {
                Text(model.tr("securityFingerprintLabel")).font(.system(size: 13, weight: .semibold))
                if let address { Text("\(address.host):\(address.port)").font(.system(size: 12)).foregroundColor(Theme.muted) }
                TextField(model.tr("securityFingerprintLabel"), text: $fingerprint).textInputAutocapitalization(.never).autocorrectionDisabled().hydraField()
                Button(model.tr("commonSave")) { save(fingerprint) }.buttonStyle(PrimaryButtonStyle())
                Button(model.tr("securityFetch"), action: fetch).buttonStyle(PrimaryButtonStyle(secondary: true))
                if let read {
                    Text(model.tr("securityFetched", ["subject": read.subject, "fingerprint": Fingerprint.display(read.fingerprint)])).font(.system(size: 12)).textSelection(.enabled)
                    Button(model.tr("securityTrust")) { save(read.fingerprint) }.buttonStyle(PrimaryButtonStyle())
                }
                if let notice { Text(notice).font(.system(size: 13)).foregroundColor(Theme.alert) }
            }
        }
        .onAppear { if let address { fingerprint = model.controller.tlsSettings.pin(for: address) ?? "" } }
    }
}

/// The help by topic and by level, with a search. Opened from a page it starts on the topic of that page.
struct HelpSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var topic: HelpTopic?
    @State private var query = ""

    init(start: HelpTopic? = nil) { _topic = State(initialValue: start) }

    private var controller: HydraController { model.controller }

    var body: some View {
        SheetFrame(model.tr("helpTitle")) {
            Picker(model.tr("helpTitle"), selection: Binding(get: { controller.helpLevel }, set: { controller.helpLevel = $0 })) {
                ForEach(HelpLevel.allCases) { Text(model.tr($0.labelKey)).tag($0) }
            }
            .pickerStyle(.segmented)
            TextField(model.tr("helpSearch"), text: $query)
                .autocorrectionDisabled()
                .hydraField()
                .accessibilityIdentifier("help-search")
            if let shown = topic, query.isEmpty {
                page(shown)
            } else {
                let found = HelpTopic.search(query) { model.tr($0) }
                if found.isEmpty { Text(model.tr("helpNothing")).font(.system(size: 13)).foregroundColor(Theme.muted) }
                ForEach(found) { entry in
                    MenuRow(symbol: entry.symbol, title: model.tr(entry.titleKey)) {
                        topic = entry
                        query = ""
                    }
                    .accessibilityIdentifier("help-topic-\(entry.rawValue)")
                }
            }
        }
    }

    @ViewBuilder
    private func page(_ shown: HelpTopic) -> some View {
        ScreenTitle(symbol: shown.symbol, title: model.tr(shown.titleKey))
        ForEach(controller.helpLevel.shown) { level in
            Panel { Text(model.tr(shown.textKey(level))).font(.system(size: 14)) }
        }
        if shown != .safety {
            Panel(tint: Theme.alert) {
                Text(model.tr("helpSafetyTitle")).font(.system(size: 14, weight: .semibold))
                Text(model.tr(HelpTopic.safety.textKey(.basic))).font(.system(size: 12)).foregroundColor(Theme.muted)
            }
        }
        if let tab = MainTab.allCases.first(where: { HelpTopic.of($0) == shown && $0 != .more }), controller.signedIn {
            MenuRow(symbol: "arrow.right", title: model.tr("helpOpenScreen")) {
                model.selectedTab = tab
                dismiss()
            }
        }
        MenuRow(symbol: "square.grid.2x2", title: model.tr("helpAllTopics")) { topic = nil }
            .accessibilityIdentifier("help-all")
    }
}

struct AboutSheet: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        SheetFrame(model.tr("aboutTitle")) {
            VStack(spacing: 8) {
                HydraMark(size: 72)
                Text("HYDRA-UMC Control").font(.system(size: 20, weight: .bold))
                Text(model.tr("aboutVersion", ["version": AppModel.version])).font(.system(size: 13)).foregroundColor(Theme.muted)
                Text("JuanenRac (Electro Hobby 3D) · GPL-3.0-or-later").font(.system(size: 12)).foregroundColor(Theme.muted)
            }
            .frame(maxWidth: .infinity)
            Text(model.tr("aboutTagline")).font(.system(size: 13))
            Panel(tint: Theme.amber) { Text(model.tr("aboutPreview")).font(.system(size: 13)) }
            Panel(tint: Theme.alert) { Text(model.tr("stopPhysical")).font(.system(size: 13)) }
            Panel {
                ShareLink(item: model.controller.diagnostic(appVersion: AppModel.version, system: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion), \(UIDevice.current.model)")) {
                    Label(model.tr("aboutShare"), systemImage: "square.and.arrow.up").font(.system(size: 14, weight: .semibold))
                }
                .accessibilityIdentifier("about-share")
                Text(model.tr("aboutShareHint")).font(.system(size: 12)).foregroundColor(Theme.muted)
            }
        }
    }
}
