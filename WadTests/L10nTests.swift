// L10nTests.swift
// Prüft die Menüsprache: dass neue Installationen Englisch und Updates Deutsch bekommen, und dass
// alle drei Sprachen vollständig sind und zum Quelltext passen.

import XCTest

final class L10nTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "com.linushundt.WadTests.L10n"
    private var repository: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent() }

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        L10n.shared.language = .de
    }

    // MARK: Erster Start

    func testFreshInstallGetsEnglish() {
        XCTAssertEqual(MenuLanguage.resolve(in: defaults), .en)
    }

    func testFreshInstallListensInTheLanguageOfTheMac() {
        for (preferred, expected) in [("de-DE", "de"), ("en-US", "en"), ("fr-CH", "fr"), ("es-419", "es"), ("ja-JP", "ja"),
                                      ("fi-FI", "fi"), ("zh-Hans-CN", "zh"), ("zh-Hant-TW", "zh"), ("sw-KE", "sw")] {
            defaults.removePersistentDomain(forName: suite)
            XCTAssertEqual(MenuLanguage.resolve(in: defaults, preferred: [preferred]), .en, "Das Menü bleibt Englisch")
            XCTAssertEqual(defaults.string(forKey: MenuLanguage.inputLanguageKey), expected, preferred)
        }
    }

    func testFreshInstallOnAnUnsupportedLanguageListensInEnglish() {
        XCTAssertEqual(MenuLanguage.inputLanguage(preferred: ["it-IT", "de-DE"]), "en", "Nur die erste Sprache zählt")
        XCTAssertEqual(MenuLanguage.inputLanguage(preferred: ["ko-KR"]), "en")
        XCTAssertEqual(MenuLanguage.inputLanguage(preferred: []), "en")
        XCTAssertEqual(MenuLanguage.inputLanguage(preferred: ["???"]), "en")
    }

    func testUpdateWithoutOwnChoiceKeepsListeningInGerman() {
        defaults.set("1.2.0", forKey: "Zuletzt gestartete Version")
        XCTAssertEqual(MenuLanguage.resolve(in: defaults, preferred: ["ja-JP"]), .de)
        XCTAssertEqual(defaults.string(forKey: MenuLanguage.inputLanguageKey), "de", "Bisher galt Deutsch, ohne dass es gespeichert war")
    }

    func testUpdateKeepsChosenInputLanguage() {
        defaults.set("auto", forKey: MenuLanguage.inputLanguageKey)
        _ = MenuLanguage.resolve(in: defaults)
        XCTAssertEqual(defaults.string(forKey: MenuLanguage.inputLanguageKey), "auto")
    }

    func testInputLanguageStaysAfterSwitchingTheMenuLater() {
        _ = MenuLanguage.resolve(in: defaults, preferred: ["fi-FI"])
        defaults.set("de", forKey: MenuLanguage.defaultsKey)
        _ = MenuLanguage.resolve(in: defaults, preferred: ["ja-JP"])
        XCTAssertEqual(defaults.string(forKey: MenuLanguage.inputLanguageKey), "fi", "Menü und Eingabe sind unabhängig")
    }

    func testAnyEarlierSettingKeepsGerman() {
        for key in MenuLanguage.earlierWadKeys {
            defaults.removePersistentDomain(forName: suite)
            defaults.set(true, forKey: key)
            XCTAssertEqual(MenuLanguage.resolve(in: defaults), .de, key)
        }
    }

    func testForeignSettingsDoNotCountAsEarlierWad() {
        defaults.set("macOS", forKey: "NSWindow Frame Irgendwas")
        XCTAssertEqual(MenuLanguage.resolve(in: defaults), .en, "macOS legt selbst Einstellungen an")
    }

    func testDecisionSurvivesTheSettingsWadWritesAfterwards() {
        XCTAssertEqual(MenuLanguage.resolve(in: defaults), .en)
        defaults.set("1.3.0", forKey: "Zuletzt gestartete Version")
        XCTAssertEqual(MenuLanguage.resolve(in: defaults), .en, "Der zweite Start einer neuen Installation ist kein Update")
    }

    func testChoiceWins() {
        defaults.set("Kleinschreibung", forKey: "Kleinschreibung")
        defaults.set("ja", forKey: MenuLanguage.defaultsKey)
        XCTAssertEqual(MenuLanguage.resolve(in: defaults), .ja)
    }

    func testUnknownStoredLanguageIsDecidedAnew() {
        defaults.set("fr", forKey: MenuLanguage.defaultsKey)
        XCTAssertEqual(MenuLanguage.resolve(in: defaults), .en)
    }

    // MARK: Texte

    func testSwitchingAppliesImmediately() {
        L10n.shared.language = .ja
        XCTAssertEqual(L10n.t("menu.quit"), "Wadを終了")
        L10n.shared.language = .en
        XCTAssertEqual(L10n.t("menu.quit"), "Quit Wad")
        L10n.shared.language = .de
        XCTAssertEqual(L10n.t("menu.quit"), "Wad beenden")
    }

    func testInsertsValues() {
        L10n.shared.language = .de
        XCTAssertEqual(L10n.t("menu.minutes", 5), "5 Minuten")
        XCTAssertEqual(L10n.t("shortcuts.taken", "⌘⇧F", "Vollbild"), "⌘⇧F ist schon für „Vollbild“ vergeben.")
    }

    func testAllLanguagesHaveTheSameKeysAndNoEmptyTexts() {
        let english = L10n.shared.table(for: .en)
        XCTAssertFalse(english.isEmpty)
        for language in MenuLanguage.allCases {
            let table = L10n.shared.table(for: language)
            XCTAssertEqual(Set(table.keys), Set(english.keys), language.rawValue)
            XCTAssertFalse(table.values.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }, language.rawValue)
        }
    }

    func testPlaceholdersMatchInEveryLanguage() throws {
        let placeholder = try NSRegularExpression(pattern: "%(@|ld)")
        func placeholders(_ text: String) -> [String] {
            placeholder.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { (text as NSString).substring(with: $0.range) }
        }
        let english = L10n.shared.table(for: .en)
        for language in MenuLanguage.allCases {
            for (key, text) in L10n.shared.table(for: language) {
                XCTAssertEqual(placeholders(text), placeholders(english[key] ?? ""), "\(language.rawValue): \(key)")
            }
        }
    }

    func testKeyboardSymbolsSurviveTranslation() {
        for key in ["preview.doneHelp", "shortcuts.needsModifier"] {
            for language in MenuLanguage.allCases {
                let text = L10n.shared.table(for: language)[key] ?? ""
                let expected = key == "preview.doneHelp" ? "⌘↩" : "⌘"
                XCTAssertTrue(text.contains(expected), "\(language.rawValue): \(key)")
            }
        }
    }

    func testEveryInputLanguageHasAName() {
        for code in ["de", "en", "fr", "es", "ja", "fi", "zh", "sw", "auto"] {
            for language in MenuLanguage.allCases {
                XCTAssertNotNil(L10n.shared.table(for: language)["language.\(code)"], "\(language.rawValue): \(code)")
            }
        }
    }

    /// Jeder Schlüssel im Quelltext hat einen Text, und jeder Text wird benutzt.
    func testSourceAndTextsMatch() throws {
        let folder = repository.appendingPathComponent("Wad")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        let source = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
        let keys = Set(L10n.shared.table(for: .en).keys)

        let call = try NSRegularExpression(pattern: #"L10n\.t\("([A-Za-z]+\.[A-Za-z.]+)""#)
        let used = call.matches(in: source, range: NSRange(source.startIndex..., in: source))
            .map { (source as NSString).substring(with: $0.range(at: 1)) }
        XCTAssertFalse(used.isEmpty)
        XCTAssertEqual(Set(used).subtracting(keys), [], "Im Quelltext, aber ohne Text")

        let unused = keys.filter { !source.contains("\"\($0)\"") && !$0.hasPrefix("language.") }
        XCTAssertEqual(unused, [], "Texte, die niemand benutzt")
    }

    func testWhatsNewExistsInEveryLanguageAndStartsWithAGreeting() throws {
        for (language, greeting) in [(MenuLanguage.de, "Hi"), (.en, "Hi"), (.ja, "こんにちは")] {
            let url = repository.appendingPathComponent("Wad/WasIstNeu.\(language.rawValue).md")
            let text = try String(contentsOf: url, encoding: .utf8)
            let whatsNew = UpdateRules.whatsNew(text)
            XCTAssertTrue(whatsNew.intro?.hasPrefix(greeting) == true, language.rawValue)
            XCTAssertEqual(whatsNew.items.count, 4, language.rawValue)
            XCTAssertFalse(whatsNew.items.contains { $0.contains("**") }, language.rawValue)
            // CommonMark schließt Fettdruck nicht nach einem Satzzeichen direkt vor einem Buchstaben, etwa auf GitHub.
            XCTAssertNil(text.range(of: #"[：:]\*\*\S"#, options: .regularExpression), language.rawValue)
        }
    }
}
