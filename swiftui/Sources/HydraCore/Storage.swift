// HYDRA-UMC-IOS-CONTROL - what is kept on the phone. The session lives only in the secure store; the rules are those of the published app (SDK, session_store).
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

/// Secure key/value storage of the phone (the Keychain).
public protocol SecretStore: AnyObject {
    func write(_ key: String, _ value: String) throws
    func read(_ key: String) throws -> String?
    func delete(_ key: String) throws
    /// Everything this app ever kept there.
    func deleteAll() throws
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

/// One store per server (`scope` is `ServerAddress.key`): a token is only ever read for the server that gave it.
/// * Token, user name and refresh token only in the secure store. A failed write never falls back to a plain file: the session then lives in memory for this run.
/// * A plain "logged out" marker is set before the secure delete, so a delete that fails never brings the old session back.
/// * A sign-in replaces the refresh token, so one of a previous account is never used; a renewal without a new one keeps it.
/// * A save that fails half way reverts what it wrote.
public final class SessionStore {
    private enum Key {
        static let installed = "hydra_install_marker"
    }

    private let tokenKey: String
    private let usernameKey: String
    private let refreshKey: String
    private let loggedOutKey: String

    private let secrets: SecretStore
    private let prefs: PrefsStore
    private var memory: (token: String, username: String, refresh: String?)?

    public init(secrets: SecretStore, prefs: PrefsStore, scope: String) {
        self.secrets = secrets
        self.prefs = prefs
        tokenKey = "hydra_token|\(scope)"
        usernameKey = "hydra_username|\(scope)"
        refreshKey = "hydra_refresh_token|\(scope)"
        loggedOutKey = "hydra_logged_out|\(scope)"
    }

    /// The Keychain survives an uninstall; a session left by an earlier install is never used.
    public static func purgeOnFirstRun(secrets: SecretStore, prefs: PrefsStore) {
        if prefs.bool(Key.installed) { return }
        try? secrets.deleteAll()
        prefs.set(true, Key.installed)
    }

    public func save(token: String, username: String, refreshToken: String?, replaceRefreshToken: Bool) {
        let keptRefresh = replaceRefreshToken ? refreshToken : (refreshToken ?? self.refreshToken)
        do {
            try secrets.write(tokenKey, token)
            try secrets.write(usernameKey, username)
            if let refreshToken {
                try secrets.write(refreshKey, refreshToken)
            } else if replaceRefreshToken {
                try secrets.delete(refreshKey)
            }
            prefs.set(false, loggedOutKey)
            memory = nil
        } catch {
            try? secrets.delete(tokenKey)
            try? secrets.delete(usernameKey)
            prefs.set(false, loggedOutKey)
            memory = (token, username, keptRefresh)
        }
    }

    private var loggedOut: Bool { prefs.bool(loggedOutKey) }

    private func stored(_ key: String) -> String? {
        if loggedOut { return nil }
        return (try? secrets.read(key)) ?? nil
    }

    public var token: String? { memory?.token ?? stored(tokenKey) }
    public var username: String? { memory?.username ?? stored(usernameKey) }
    public var refreshToken: String? { memory != nil ? memory?.refresh : stored(refreshKey) }

    public func clear() {
        memory = nil
        prefs.set(true, loggedOutKey)
        try? secrets.delete(tokenKey)
        try? secrets.delete(usernameKey)
        try? secrets.delete(refreshKey)
    }
}
