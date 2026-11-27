// HYDRA-UMC-IOS-CONTROL - the texts of the app in eight languages (one JSON table each, with the same keys).
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

public struct Translator {
    public static let languages = ["en", "es", "de", "fr", "it", "ja", "zh", "pt"]

    public let language: String
    private let table: [String: String]
    private let fallback: [String: String]

    public init(language: String) {
        let chosen = Translator.languages.contains(language) ? language : "en"
        self.language = chosen
        table = Translator.load(chosen)
        fallback = chosen == "en" ? table : Translator.load("en")
    }

    /// The language of the app: the one the person chose, else the first of the phone the app has, else English.
    public static func resolve(chosen: String?, preferred: [String]) -> String {
        if let chosen, languages.contains(chosen) { return chosen }
        for tag in preferred {
            let base = String(tag.prefix(2)).lowercased()
            if languages.contains(base) { return base }
        }
        return "en"
    }

    public static func load(_ language: String) -> [String: String] {
        guard let url = Bundle.module.url(forResource: language, withExtension: "json", subdirectory: "i18n"),
              let data = try? Data(contentsOf: url),
              let table = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] else { return [:] }
        return table
    }

    public func callAsFunction(_ key: String, _ values: [String: String] = [:]) -> String {
        var text = table[key] ?? fallback[key] ?? key
        for (name, value) in values { text = text.replacingOccurrences(of: "{\(name)}", with: value) }
        return text
    }
}
