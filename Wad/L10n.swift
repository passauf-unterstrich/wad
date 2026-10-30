// L10n.swift
// Wads Oberflächensprache. Sie ist eine eigene Einstellung im Menü, unabhängig von der Sprache von macOS,
// und gilt sofort, ohne Neustart. Deshalb liest Wad die Texte selbst aus en/de/ja.lproj, statt macOS
// entscheiden zu lassen. Alle Texte kommen als fertige Zeichenkette von `L10n.t`, nie als Literal in die Oberfläche.

import Combine
import Foundation

enum MenuLanguage: String, CaseIterable {
    case en, de, ja

    /// Jede Sprache steht im Menü in ihrem eigenen Namen, damit man sie auch findet, wenn man die aktuelle nicht lesen kann.
    var nativeName: String {
        switch self {
        case .en: "English"
        case .de: "Deutsch"
        case .ja: "日本語"
        }
    }

    /// Einstellung in macOS' Einstellungsablage.
    static let defaultsKey = "Menüsprache"
    /// Die Eingabesprache fürs Modell. Bis 1.2.0 wurde sie erst mit der ersten eigenen Wahl gespeichert.
    static let inputLanguageKey = "Sprache"
    /// Die wählbaren Eingabesprachen: Kürzel aus der Sprachtabelle von whisper.cpp. Die Namen stehen als
    /// „language.<Kürzel>“ in den Texten.
    static let inputLanguages = ["de", "en", "fr", "es", "ja", "fi", "zh", "sw"]

    /// Alle Einstellungen, die eine Wad-Version vor 1.3.0 angelegt haben kann. Bewusst diese feste Liste und nicht
    /// „gibt es irgendwelche Einstellungen“: macOS legt selbst welche an, auch bei einer frischen Installation.
    static let earlierWadKeys = ["Einfügen", "Sprache", "Kleinschreibung", "Höchstdauer freies Diktieren",
                                 "Letzte Diktate mitschreiben", "Zwischenablage mitschreiben",
                                 "Zuletzt gestartete Version", "Alte Version geprüft", "Anmeldeobjekt eingerichtet",
                                 "Update-Prüfung", "Update-Frage gezeigt", "Letzte Update-Prüfung",
                                 "Übersprungene Version", "Angekündigte Version", "Fenstermanager", "Fenster-Kürzel"]

    /// Die gemerkte Sprache. Beim allerersten Start entscheidet Wad einmal: Neu installiert heißt Englisch, ein Update
    /// von einer älteren Version bleibt Deutsch, damit niemandem das Menü plötzlich die Sprache wechselt.
    /// Die Entscheidung wird sofort gemerkt, denn ab jetzt legt Wad selbst Einstellungen an und sähe beim
    /// nächsten Start aus wie ein Update. Dasselbe gilt für die Eingabesprache: Wer nie eine gewählt hat,
    /// behält nach einem Update Deutsch, neu installiert folgt sie dem Mac. Danach sind beide Einstellungen unabhängig.
    /// - Parameter preferred: die Sprachen des Mac, wichtigste zuerst.
    static func resolve(in defaults: UserDefaults, preferred: [String] = Locale.preferredLanguages) -> MenuLanguage {
        if let stored = defaults.string(forKey: defaultsKey).flatMap(MenuLanguage.init) { return stored }
        let language: MenuLanguage = earlierWadKeys.contains { defaults.object(forKey: $0) != nil } ? .de : .en
        defaults.set(language.rawValue, forKey: defaultsKey)
        if defaults.object(forKey: inputLanguageKey) == nil {
            defaults.set(language == .en ? inputLanguage(preferred: preferred) : "de", forKey: inputLanguageKey)
        }
        return language
    }

    /// Die erste Sprache des Mac, wenn Wad sie erkennt, sonst Englisch. „zh-Hans-CN“ zählt als „zh“.
    static func inputLanguage(preferred: [String]) -> String {
        let code = preferred.first.flatMap { Locale(identifier: $0).language.languageCode?.identifier }
        return code.flatMap { inputLanguages.contains($0) ? $0 : nil } ?? "en"
    }
}

final class L10n: ObservableObject {
    /// Muss ganz am Anfang von Wads Start zum ersten Mal benutzt werden, bevor Wad Einstellungen anlegt (siehe `resolve`).
    static let shared = L10n()

    @Published var language: MenuLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: MenuLanguage.defaultsKey)
            onChange?()
        }
    }
    /// Für alles, was sich nicht von selbst neu zeichnet, etwa Fenstertitel.
    var onChange: (() -> Void)?

    private let tables: [MenuLanguage: [String: String]]

    private init() {
        language = MenuLanguage.resolve(in: .standard)
        // Wad kompiliert seine Quellen auch direkt in die Tests. So finden beide ihre eigenen Texte.
        let bundle = Bundle(for: L10n.self)
        var tables: [MenuLanguage: [String: String]] = [:]
        for language in MenuLanguage.allCases {
            let url = bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil,
                                 localization: language.rawValue)
            tables[language] = url.flatMap { NSDictionary(contentsOf: $0) as? [String: String] } ?? [:]
        }
        self.tables = tables
    }

    func table(for language: MenuLanguage) -> [String: String] { tables[language] ?? [:] }

    /// Der Text in der gewählten Sprache. Fehlt er dort, Englisch, sonst der Schlüssel selbst.
    static func t(_ key: String) -> String {
        shared.table(for: shared.language)[key] ?? shared.table(for: .en)[key] ?? key
    }

    /// Wie `t(_:)`, mit eingesetzten Werten für %@ und %ld.
    static func t(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), arguments: arguments)
    }
}
