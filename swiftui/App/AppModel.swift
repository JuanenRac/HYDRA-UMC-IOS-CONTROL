// HYDRA-UMC-IOS-CONTROL - what the screens observe: the controller of HydraCore, the language, the search of servers and the haptic of the STOP.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import SwiftUI
import UIKit
import HydraCore

@MainActor
final class AppModel: ObservableObject {
    let controller: HydraController
    @Published private(set) var translator: Translator
    @Published var selectedTab: MainTab = .home
    @Published private(set) var found: [FoundServer] = []
    @Published private(set) var searching = false
    /// The address the sign-in form starts with.
    @Published var formHost = ""
    @Published var formPort = String(ServerAddress.defaultPort)
    /// What the first-use screen asked the sign-in to open.
    @Published var loginAction: LoginAction?

    enum LoginAction { case search, scan }

    let stopWindows = StopWindows()
    private let transport: UrlSessionTransport?
    private let bonjour = BonjourSearch()
    private var search: Task<Void, Never>?
    private var started = false
    private var shownPairing: ServerAddress?

    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0" }

    init() {
        let made: HydraController
        var real: UrlSessionTransport?
        #if DEBUG
        if Demo.screen != nil {
            let transport = DemoTransport()
            made = HydraController(transport: transport, discoveryTransport: transport, secrets: DemoSecrets(), prefs: DemoPrefs(), auth: PhoneAuth(), appVersion: AppModel.version)
        } else {
            let transport = UrlSessionTransport()
            real = transport
            made = HydraController(transport: transport, discoveryTransport: UrlSessionTransport(acceptAnyCertificate: true), secrets: KeychainSecrets(), prefs: DefaultsPrefs(), auth: PhoneAuth(), appVersion: AppModel.version)
        }
        #else
        let transport = UrlSessionTransport()
        real = transport
        made = HydraController(transport: transport, discoveryTransport: UrlSessionTransport(acceptAnyCertificate: true), secrets: KeychainSecrets(), prefs: DefaultsPrefs(), auth: PhoneAuth(), appVersion: AppModel.version)
        #endif
        controller = made
        self.transport = real
        translator = Translator(language: Translator.resolve(chosen: nil, preferred: Locale.preferredLanguages))
        made.onChange = { [weak self] in self?.controllerChanged() }
    }

    private var appliedTls: TlsSettings?

    private func controllerChanged() {
        if appliedTls != controller.tlsSettings {
            appliedTls = controller.tlsSettings
            transport?.apply(controller.tlsSettings)
        }
        let language = Translator.resolve(chosen: controller.chosenLanguage, preferred: Locale.preferredLanguages)
        if language != translator.language { translator = Translator(language: language) }
        if let paired = controller.pairedAddress, paired != shownPairing {
            shownPairing = paired
            fill(paired)
        }
        objectWillChange.send()
        stopWindows.update()
    }

    func tr(_ key: String, _ values: [String: String] = [:]) -> String { translator(key, values) }

    func text(_ message: Message) -> String { translator(message.key, message.values) }

    func start() async {
        guard !started else { return }
        started = true
        await controller.start()
        #if DEBUG
        if let demo = Demo.screen {
            if demo != "welcome" { controller.finishFirstRun() }
            if demo == "main" { await controller.login(host: "192.168.1.50", port: "3000", username: "demo", password: "demo", code: "") }
        }
        #endif
        if formHost.isEmpty, let server = controller.server ?? controller.savedServers.first { fill(server.address) }
    }

    func fill(_ address: ServerAddress) {
        formHost = address.host
        formPort = String(address.port)
    }

    func becameActive() {
        Task { await controller.refresh() }
    }

    func stopAll() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        Task { await controller.stopAll() }
    }

    // MARK: - Search of servers

    func startSearch() {
        stopSearch()
        found = []
        searching = true
        let add: @MainActor (FoundServer) -> Void = { [weak self] server in
            guard let self, !self.found.contains(where: { $0.id == server.id }) else { return }
            self.found.append(server)
        }
        bonjour.start { [weak self] host, port in
            Task { @MainActor in
                if let server = await self?.controller.probe(host: host, port: port) { add(server) }
            }
        }
        let prefixes = Discovery.prefixes(interfaces: NetworkInterfaces.ipv4(), lastHost: formHost.isEmpty ? nil : formHost, skipMobileAndVpn: controller.skipMobileAndVpn)
        let controller = self.controller
        search = Task { [weak self] in
            await Discovery.scan(hosts: prefixes.flatMap(Discovery.hosts), probe: { await controller.probe(host: $0) }, found: add)
            if !Task.isCancelled { self?.searching = false }
        }
    }

    func stopSearch() {
        search?.cancel()
        search = nil
        bonjour.stop()
        searching = false
    }
}
