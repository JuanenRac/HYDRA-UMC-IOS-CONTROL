// HYDRA-UMC-IOS-CONTROL - what is kept on the phone. The session lives only in the secure store; the rules are those of the published app (SDK, session_store).
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

/// Secure key/value storage of the phone (the Keychain).
public protocol SecretStore: AnyObject {
    func write(_ key: String, _ value: String) throws
    func read(_ key: String) throws -> String?
    func delete(_ key: String) throws
}

/// Ordinary (not secret) preferences.
public protocol PrefsStore: AnyObject {
    func string(_ key: String) -> String?
    func set(_ value: String?, _ key: String)
}

public extension PrefsStore {
    func bool(_ key: String, default value: Bool = false) -> Bool { string(key).map { $0 == "1" } ?? value }
    func set(_ value: Bool, _ key: String) { set(value ? "1" : "0", key) }

    func codable<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        string(key).flatMap { try? JSONDecoder().decode(type, from: Data($0.utf8)) }
    }

    func setCodable<T: Encodable>(_ value: T, _ key: String) {
        set((try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) }, key)
    }
}

/// * Token, user name and refresh token only in the secure store. A failed write never falls back to a plain file: the session then lives in memory for this run.
/// * A plain "logged out" marker is set before the secure delete, so a delete that fails never brings the old session back.
/// * A sign-in replaces the refresh token, so one of a previous account is never used; a renewal without a new one keeps it.
/// * A save that fails half way reverts what it wrote.
public final class SessionStore {
    enum Key {
        static let token = "hydra_token"
        static let username = "hydra_username"
        static let refresh = "hydra_refresh_token"
        static let loggedOut = "hydra_logged_out"
        static let installed = "hydra_install_marker"
    }

    private let secrets: SecretStore
    private let prefs: PrefsStore
    private var memory: (token: String, username: String, refresh: String?)?

    public init(secrets: SecretStore, prefs: PrefsStore) {
        self.secrets = secrets
        self.prefs = prefs
    }

    public func save(token: String, username: String, refreshToken: String?, replaceRefreshToken: Bool) {
        let keptRefresh = replaceRefreshToken ? refreshToken : (refreshToken ?? self.refreshToken)
        do {
            try secrets.write(Key.token, token)
            try secrets.write(Key.username, username)
            if let refreshToken {
                try secrets.write(Key.refresh, refreshToken)
            } else if replaceRefreshToken {
                try secrets.delete(Key.refresh)
            }
            prefs.set(false, Key.loggedOut)
            memory = nil
        } catch {
            try? secrets.delete(Key.token)
            try? secrets.delete(Key.username)
            prefs.set(false, Key.loggedOut)
            memory = (token, username, keptRefresh)
        }
    }

    private var loggedOut: Bool { prefs.bool(Key.loggedOut) }

    private func stored(_ key: String) -> String? {
        if loggedOut { return nil }
        return (try? secrets.read(key)) ?? nil
    }

    public var token: String? { memory?.token ?? stored(Key.token) }
    public var username: String? { memory?.username ?? stored(Key.username) }
    public var refreshToken: String? { memory != nil ? memory?.refresh : stored(Key.refresh) }

    public func clear() {
        memory = nil
        prefs.set(true, Key.loggedOut)
        try? secrets.delete(Key.token)
        try? secrets.delete(Key.username)
        try? secrets.delete(Key.refresh)
    }

    /// The Keychain survives an uninstall; a session left by an earlier install is not used.
    public func purgeOnFirstRun() {
        if prefs.bool(Key.installed) { return }
        try? secrets.delete(Key.token)
        try? secrets.delete(Key.username)
        try? secrets.delete(Key.refresh)
        prefs.set(true, Key.installed)
    }
}
