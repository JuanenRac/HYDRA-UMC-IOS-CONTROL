// HYDRA-UMC-IOS-CONTROL - the help by topic and level with its search, and the diagnostic report a person can share.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

public enum HelpTopic: String, CaseIterable, Identifiable, Sendable {
    case start, home, control, cameras, alerts, account, safety

    public var id: String { rawValue }

    public var titleKey: String {
        switch self {
        case .start: return "helpStartTitle"
        case .home: return "navHome"
        case .control: return "navControl"
        case .cameras: return "navCameras"
        case .alerts: return "navAlerts"
        case .account: return "helpAccountTitle"
        case .safety: return "helpSafetyTitle"
        }
    }

    public var symbol: String {
        switch self {
        case .start: return "wifi"
        case .home: return "house"
        case .control: return "arrow.up.and.down.and.arrow.left.and.right"
        case .cameras: return "video"
        case .alerts: return "bell"
        case .account: return "person"
        case .safety: return "shield"
        }
    }

    public func textKey(_ level: HelpLevel) -> String { "help_\(rawValue)_\(level.rawValue)" }

    /// The topic of a page of the bottom bar.
    public static func of(_ tab: MainTab) -> HelpTopic {
        switch tab {
        case .home: return .home
        case .control: return .control
        case .cameras: return .cameras
        case .alerts: return .alerts
        case .more: return .account
        }
    }

    /// The topics that hold every word of `query` in their title or in any of their texts.
    public static func search(_ query: String, _ text: (String) -> String) -> [HelpTopic] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return allCases.filter { topic in
            let all = ([topic.titleKey] + HelpLevel.texts.map { topic.textKey($0) }).map(text).joined(separator: " ")
            return words.allSatisfy { all.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }
}

public enum HelpLevel: String, CaseIterable, Identifiable, Sendable {
    case basic, advanced, technical, all

    public var id: String { rawValue }

    /// The levels that have a text of their own.
    public static let texts: [HelpLevel] = [.basic, .advanced, .technical]

    public var labelKey: String {
        switch self {
        case .basic: return "helpLevelBasic"
        case .advanced: return "helpLevelAdvanced"
        case .technical: return "helpLevelTechnical"
        case .all: return "noticesFilterAll"
        }
    }

    public var shown: [HelpLevel] { self == .all ? HelpLevel.texts : [self] }
}

public extension HydraController {
    /// The level of help the person chose last.
    var helpLevel: HelpLevel {
        get { prefs.string("hydra_help_level").flatMap(HelpLevel.init(rawValue:)) ?? .basic }
        set {
            prefs.set(newValue.rawValue, "hydra_help_level")
            changed()
        }
    }

    /// What is useful to find a fault, and nothing that names anyone or anything: no address, user name, token, fingerprint,
    /// server or robot name, and no text of a message.
    func diagnostic(appVersion: String, system: String) -> String {
        func flag(_ value: Bool) -> String { value ? "on" : "off" }
        let linkName: String
        switch link {
        case .connected: linkName = "connected"
        case .connecting: linkName = "connecting"
        case .disconnected: linkName = "disconnected"
        }
        let address = client?.address
        return [
            "HYDRA-UMC Control (iOS, native) \(appVersion)",
            "system: \(system)",
            "language: \(Translator.resolve(chosen: chosenLanguage, preferred: Locale.preferredLanguages))",
            "signed in: \(screen == .main ? "yes" : "no")",
            "live link: \(linkName)",
            "encrypted connection: \(client.map { $0.usesTls ? "yes" : "no" } ?? "-")",
            "certificate fingerprint kept: \(address.map { tlsSettings.pin(for: $0) != nil ? "yes" : "no" } ?? "-")",
            "plain HTTP allowed: \(flag(tlsSettings.allowPlainHttp))",
            "saved servers: \(savedServers.count)",
            "robots: \(robots.count), online: \(robots.filter(\.online).count)",
            "showing saved data: \(showingSavedData ? "yes" : "no")",
            "listen only: \(flag(control.listenOnly))",
            "continuous jog: \(flag(control.deadManEnabled))",
            "HOME/RESET: \(flag(control.homeResetEnabled))",
            "biometric lock: \(flag(biometricEnabled))",
            "pairing: \(flag(pairingEnabled))",
            "push: \(pushAvailable ? flag(pushEnabled) : "not in this build")",
            "notices kept: \(notices.count)",
            "STOP without answer: \(stopUnconfirmed ? "yes" : "no")",
        ].joined(separator: "\n")
    }
}
