// UpdateChecker.swift
// Die einzige Datei in Wad mit Netzwerkcode (SPEC 2.6). Ist die Update-Prüfung an, fragt Wad höchstens
// einmal am Tag bei GitHub nach der neuesten Versionsnummer. Mit der Anfrage geht nichts über Diktate,
// Vokabeln oder den Nutzer hinaus, nur „Wad/<Version>“. Herunterladen oder installieren tut Wad nie
// etwas selbst, es zeigt nur einen Hinweis (SPEC 1.9).

import AppKit

/// Eine Versionsnummer wie „1.1.0“, Teil für Teil als Zahl verglichen. „v1.2“ zählt wie „1.2.0“.
struct AppVersion: Comparable, CustomStringConvertible {
    private let parts: [Int]
    let description: String

    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let number = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        // Nur Ziffern und Punkte. Vorabversionen wie „1.2.0-beta“ passen nicht und werden so nie angeboten.
        let parts = number.split(separator: ".", omittingEmptySubsequences: false)
            .map { $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) ? Int($0) : nil }
        guard !parts.contains(nil) else { return nil }
        self.parts = parts.compactMap { $0 }
        description = number
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) where lhs.part(index) != rhs.part(index) {
            return lhs.part(index) < rhs.part(index)
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }

    private func part(_ index: Int) -> Int { index < parts.count ? parts[index] : 0 }
}

/// Die neueste Version auf GitHub. Gelesen werden nur Nummer und Beschreibung.
struct Release: Equatable {
    let version: AppVersion
    let notes: String
}

/// Wann Wad welchen Hinweis zeigt. Ohne Netzwerk, damit es sich prüfen lässt.
enum UpdateRules {
    /// Eine neuere Version, die nicht übersprungen wurde. Überspringen gilt nur bis zu einer noch neueren.
    static func isOffered(_ latest: AppVersion, current: AppVersion, skipped: AppVersion?) -> Bool {
        latest > current && skipped.map { latest > $0 } ?? true
    }

    /// Das Fenster kommt von selbst nur einmal pro Version. Danach steht der Hinweis nur noch im Menü.
    static func announces(_ latest: AppVersion, current: AppVersion, skipped: AppVersion?,
                          announced: AppVersion?) -> Bool {
        isOffered(latest, current: current, skipped: skipped) && announced != latest
    }

    /// „Was ist neu“ nur nach einem Update, nie bei einer frischen Installation. Version 1.0.x merkte sich
    /// noch keine Version. Dort verrät sich ein Update an Einstellungen, die nur eine frühere Version anlegt.
    static func showsWhatsNew(current: AppVersion, lastSeen: AppVersion?, hadEarlierVersion: Bool) -> Bool {
        guard let lastSeen else { return hadEarlierVersion }
        return current > lastSeen
    }

    /// Die Update-Prüfung ist ab Werk aus. Wad fragt erst, wenn der Nutzer sie selbst eingeschaltet hat
    /// (Entscheidung Linus, 26.10.2026: nur mit ausdrücklicher Einwilligung).
    static func isEnabled(stored: Bool?) -> Bool { stored ?? false }

    /// Der einmalige Hinweis, dass man die Prüfung einschalten kann. Wer schon einmal gewählt hat, auch
    /// im Menü, bekommt ihn nicht mehr.
    static func needsInfo(stored: Bool?, infoShown: Bool) -> Bool { stored == nil && !infoShown }

    /// Liest WasIstNeu: die erste Textzeile als Begrüßung, dazu die Stichpunkte als schlichter Text.
    static func whatsNew(_ markdown: String) -> (intro: String?, items: [String]) {
        let lines = markdown.split(whereSeparator: \.isNewline).map(String.init)
        let items = lines.filter { $0.hasPrefix("- ") }.map { plainText(String($0.dropFirst(2))) }
        return (lines.first { !$0.hasPrefix("#") && !$0.hasPrefix("- ") }, items)
    }

    /// Macht aus der Beschreibung auf GitHub schlichten Text: keine Auszeichnungen, Links nur als Wort.
    static func plainText(_ markdown: String) -> String {
        var text = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let replacements = [(#"<[^>]+>"#, ""),                       // HTML-Schnipsel
                            (#"!?\[([^\]]*)\]\([^)]*\)"#, "$1"),     // [Wort](Adresse) → Wort
                            (#"(?m)^#+\s*"#, ""),                    // Überschriften
                            (#"(?m)^\s*[*+]\s+"#, "- "),             // Aufzählungen einheitlich
                            (#"\*\*|__|`"#, "")]                     // Fett und Code
        for (pattern, template) in replacements {
            text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class UpdateChecker {
    static let current = AppVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
        ?? AppVersion("0")!
    /// Dorthin führt „Zum Download“. Wad öffnet die Seite nur im Browser, lädt selbst nichts.
    static let downloadPage = URL(string: "https://linushundt.com/wad/download/")!
    /// Die einzige Adresse, die Wad je anfragt.
    private static let endpoint = URL(string: "https://api.github.com/repos/passauf-unterstrich/wad/releases/latest")!
    /// Eine Antwort von GitHub ist wenige Kilobyte groß. Was größer ist, liest Wad gar nicht erst zu Ende.
    private static let maxBytes = 256 * 1024
    private static let interval: TimeInterval = 24 * 60 * 60
    /// Frühestens so lange nach dem Start, damit Wad erst in Ruhe hochfährt.
    private static let startDelay: TimeInterval = 60

    private static let enabledKey = "Update-Prüfung"
    private static let infoShownKey = "Update-Frage gezeigt"
    private static let lastCheckKey = "Letzte Update-Prüfung"
    private static let skippedKey = "Übersprungene Version"
    private static let announcedKey = "Angekündigte Version"

    /// Die automatische Prüfung hat eine neue Version gefunden. `announce`: das Fenster zeigen, nicht nur das Menü.
    var onFound: ((Release, _ announce: Bool) -> Void)?
    /// Läuft gerade eine Aufnahme, wartet die Prüfung ein paar Minuten.
    var isBusy: () -> Bool = { false }

    /// Standard aus. Einmal weist Wad darauf hin (`needsInfo`), einschalten geht dort oder im Menü.
    var isEnabled: Bool {
        get { UpdateRules.isEnabled(stored: UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            schedule()
        }
    }
    var needsInfo: Bool {
        get {
            UpdateRules.needsInfo(stored: UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool,
                                  infoShown: UserDefaults.standard.bool(forKey: Self.infoShownKey))
        }
        set { UserDefaults.standard.set(!newValue, forKey: Self.infoShownKey) }
    }
    var skipped: AppVersion? {
        get { UserDefaults.standard.string(forKey: Self.skippedKey).flatMap(AppVersion.init) }
        set { UserDefaults.standard.set(newValue?.description, forKey: Self.skippedKey) }
    }
    private var announced: AppVersion? {
        get { UserDefaults.standard.string(forKey: Self.announcedKey).flatMap(AppVersion.init) }
        set { UserDefaults.standard.set(newValue?.description, forKey: Self.announcedKey) }
    }

    private let launched = Date()
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    /// Plant die erste Prüfung. Nach dem Ruhezustand wird neu geplant, weil ein Timer im Schlaf stehen bleibt.
    func start() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.schedule() }
        schedule()
    }

    /// Menü „Updates → Jetzt suchen …“: gilt auch bei ausgeschalteter Prüfung und für übersprungene
    /// Versionen, weil man ausdrücklich gefragt hat. `nil` heißt: auf dem neuesten Stand.
    func checkNow(completion: @escaping (Result<Release?, Error>) -> Void) {
        fetch { result in
            completion(result.map { release in release.flatMap { $0.version > Self.current ? $0 : nil } })
        }
    }

    /// Die nächste Prüfung: 24 Stunden nach der letzten, aber nie in der ersten Minute nach dem Start.
    private func schedule() {
        timer?.invalidate()
        guard isEnabled else { return }
        let lastCheck = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
        let due = max(lastCheck?.addingTimeInterval(Self.interval) ?? .distantPast,
                      launched.addingTimeInterval(Self.startDelay))
        plan(after: due.timeIntervalSinceNow)
    }

    private func plan(after delay: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(delay, 1), repeats: false) { [weak self] _ in
            self?.checkAutomatically()
        }
    }

    private func checkAutomatically() {
        guard isEnabled else { return }
        // Nie während einer Aufnahme, dann eben ein paar Minuten später.
        guard !isBusy() else { return plan(after: 5 * 60) }
        // Jeder Versuch zählt, auch ein fehlgeschlagener: So fragt Wad sicher höchstens einmal am Tag.
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
        fetch { [weak self] result in
            guard let self else { return }
            schedule()
            switch result {
            case .success(let release?):
                guard UpdateRules.isOffered(release.version, current: Self.current, skipped: skipped) else { return }
                let announce = UpdateRules.announces(release.version, current: Self.current,
                                                     skipped: skipped, announced: announced)
                if announce { announced = release.version }
                onFound?(release, announce)
            case .success(nil):
                break
            case .failure(let error):
                // Automatisch bleibt ein Fehler still, beim nächsten Mal klappt es meist wieder.
                log.notice("Update-Prüfung: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Fragt GitHub und meldet sich auf dem Hauptthread zurück. `nil`: Es gibt noch keine veröffentlichte Version.
    private func fetch(completion: @escaping (Result<Release?, Error>) -> Void) {
        Task {
            let result: Result<Release?, Error>
            do { result = .success(try await Self.latestRelease()) } catch { result = .failure(error) }
            await MainActor.run { completion(result) }
        }
    }

    private enum Failure: Error { case unexpectedAnswer, tooLarge }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let body: String?
        enum CodingKeys: String, CodingKey { case tagName = "tag_name", body }
    }

    /// Genau eine Anfrage: ohne Cookies, ohne Zwischenspeicher, nur HTTPS, nach 10 Sekunden ist Schluss.
    private static func latestRelease() async throws -> Release? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: endpoint)
        request.setValue("Wad/\(current)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.url?.scheme == "https" else { throw Failure.unexpectedAnswer }
        // GitHub sagt 404, solange noch keine Version veröffentlicht ist. Dann gibt es nichts Neueres.
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw Failure.unexpectedAnswer }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            guard data.count <= maxBytes else { throw Failure.tooLarge }
        }
        let answer = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let version = AppVersion(answer.tagName) else { throw Failure.unexpectedAnswer }
        return Release(version: version, notes: UpdateRules.plainText(answer.body ?? ""))
    }
}
