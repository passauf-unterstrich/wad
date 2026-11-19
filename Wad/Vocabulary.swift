// Vocabulary.swift
// Die Vokabelliste als reine Regel: lesen, ersetzen, Hinweis fürs Modell. Kein Speichern, keine
// Oberfläche, deshalb vollständig getestet.
//
// Format, eine Zeile pro Eintrag:
//   Mise en place      Wad soll den Begriff kennen und so schreiben.
//   Watt -> Wad        Wad ersetzt „Watt“ durch „Wad“ und kennt „Wad“.
//   # Kommentar        wird übergangen.

import Foundation

struct Vocabulary: Equatable {
    struct Entry: Equatable {
        /// Was das Modell fälschlich schreibt. `nil` bei reinen Begriffen.
        var wrong: String?
        var right: String
    }

    /// So viele Begriffe bekommt das Modell höchstens als Hinweis. Mehr kann Whisper verwirren.
    static let hintLimit = 40

    var entries: [Entry] = []

    init(entries: [Entry] = []) {
        self.entries = entries
    }

    init(text: String) {
        entries = text.split(whereSeparator: \.isNewline).compactMap(Self.parse)
    }

    /// Liest eine Zeile. `nil` bei Leerzeilen, Kommentaren und Zeilen, die kein Eintrag sind.
    static func parse<S: StringProtocol>(_ rawLine: S) -> Entry? {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
        let parts = line.components(separatedBy: "->").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 1 { return Entry(wrong: nil, right: parts[0]) }
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return Entry(wrong: parts[0], right: parts[1])
    }

    /// Ersetzt jede falsche Schreibweise, aber nur als ganzes Wort und unabhängig von Groß- und
    /// Kleinschreibung. „Watt“ in „Wattestäbchen“ bleibt also unangetastet. Japanisch und Chinesisch
    /// haben keine Wortgrenzen, solche Begriffe werden überall ersetzt.
    func apply(to text: String) -> String {
        entries.reduce(text) { result, entry in
            guard let wrong = entry.wrong else { return result }
            return Self.replaceWholeWords(wrong, with: entry.right, in: result)
        }
    }

    /// Die richtigen Schreibweisen als kurzer Satz für das Modell, oder `nil` bei leerer Liste.
    var hint: String? {
        let terms = entries.map(\.right).prefix(Self.hintLimit)
        return terms.isEmpty ? nil : terms.joined(separator: ", ") + "."
    }

    private static func replaceWholeWords(_ word: String, with replacement: String, in text: String) -> String {
        var result = text
        var searchStart = result.startIndex
        let matchesAnywhere = word.contains(where: \.isCJK)
        while let found = result.range(of: word, options: .caseInsensitive, range: searchStart..<result.endIndex) {
            let startsWord = found.lowerBound == result.startIndex || !isWordCharacter(result[result.index(before: found.lowerBound)])
            let endsWord = found.upperBound == result.endIndex || !isWordCharacter(result[found.upperBound])
            if matchesAnywhere || (startsWord && endsWord) {
                let offset = result.distance(from: result.startIndex, to: found.lowerBound)
                result.replaceSubrange(found, with: replacement)
                // Verschmilzt die Ersetzung mit einem Nachbarzeichen, ist der Text kürzer als gerechnet.
                searchStart = result.index(result.startIndex, offsetBy: offset + replacement.count,
                                           limitedBy: result.endIndex) ?? result.endIndex
            } else {
                searchStart = found.upperBound
            }
        }
        return result
    }

    /// Japanische und chinesische Zeichen gelten als Grenze: „Watt“ in „Wattです“ ist ein ganzes Wort.
    private static func isWordCharacter(_ character: Character) -> Bool {
        (character.isLetter || character.isNumber) && !character.isCJK
    }
}

/// Die Vokabeldatei Zeile für Zeile, fürs Fenster „Vokabeln“. Bearbeitet werden nur die Einträge. Kommentare,
/// Leerzeilen und Zeilen, die Wad nicht versteht, bleiben genau so stehen, wie sie in der Datei waren, ebenso jeder
/// Eintrag, den man nicht anfasst. So geht aus einer von Hand oder von einer KI gepflegten Liste nie etwas verloren.
struct VocabularyFile: Equatable {
    struct Line: Equatable {
        /// Der Eintrag, wenn die Zeile einer ist.
        var entry: Vocabulary.Entry?
        /// Der Wortlaut aus der Datei. `nil`, sobald der Eintrag geändert oder neu ist: Dann schreibt Wad ihn neu.
        var original: String?
        let id = UUID()

        static func == (a: Line, b: Line) -> Bool { a.entry == b.entry && a.original == b.original }

        /// So steht die Zeile in der Datei. Ein Eintrag ohne richtige Schreibweise ist noch nicht fertig und fehlt.
        var text: String? {
            if let original { return original }
            guard let entry else { return nil }
            let right = Self.clean(entry.right)
            guard !right.isEmpty else { return nil }
            let wrong = entry.wrong.map(Self.clean) ?? ""
            return wrong.isEmpty ? right : "\(wrong) -> \(right)"
        }

        /// „->“ trennt in der Datei die beiden Seiten, also darf es in keiner Seite selbst vorkommen.
        private static func clean(_ text: String) -> String {
            text.replacingOccurrences(of: "->", with: "→").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    var lines: [Line]

    init(text: String) {
        lines = text.isEmpty ? [] : text.components(separatedBy: "\n").map { Line(entry: Vocabulary.parse($0), original: $0) }
    }

    /// Der Dateiinhalt. Unveränderte Zeilen kommen Zeichen für Zeichen zurück.
    var text: String { lines.compactMap(\.text).joined(separator: "\n") }

    /// Die Einträge mit ihrer Stelle in `lines`.
    var entries: [(index: Int, entry: Vocabulary.Entry)] {
        lines.indices.compactMap { index in lines[index].entry.map { (index, $0) } }
    }

    mutating func update(at index: Int, wrong: String?, right: String) {
        lines[index].entry = Vocabulary.Entry(wrong: wrong, right: right)
        lines[index].original = nil
    }

    /// Hängt Einträge hinten an. Rückgabe: ihre Stellen.
    @discardableResult
    mutating func append(_ entries: [Vocabulary.Entry]) -> [Int] {
        // Ein neuer Eintrag kommt nicht hinter eine leere letzte Zeile, sonst wüchse die Datei um Leerzeilen.
        while let last = lines.last, last.entry == nil, last.original?.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
            lines.removeLast()
        }
        let start = lines.count
        lines += entries.map { Line(entry: $0, original: nil) }
        return Array(start..<lines.count)
    }

    mutating func remove(at indices: Set<Int>) {
        lines = lines.enumerated().filter { !indices.contains($0.offset) }.map(\.element)
    }

    /// Falsche Schreibweisen, die mehr als einmal vorkommen, klein geschrieben. Dann gilt nur die erste.
    var duplicateWrongs: Set<String> {
        var seen: Set<String> = [], twice: Set<String> = []
        for (_, entry) in entries {
            guard let wrong = entry.wrong?.lowercased(), !wrong.isEmpty else { continue }
            if !seen.insert(wrong).inserted { twice.insert(wrong) }
        }
        return twice
    }

    /// Eingefügter Text, etwa von einer KI: jede Zeile ein Eintrag, Kommentare und Leerzeilen fallen weg.
    static func entries(fromPasted text: String) -> [Vocabulary.Entry] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            // Aufzählungszeichen, wie KIs sie gern setzen, gehören nicht zum Begriff.
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let unbulleted = trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") || trimmed.hasPrefix("* ")
                ? String(trimmed.dropFirst(2)) : trimmed
            // „Hier ist deine Liste:“ ist eine Einleitung, kein Begriff.
            if unbulleted.hasSuffix(":") && !unbulleted.contains("->") { return nil }
            return Vocabulary.parse(unbulleted)
        }
    }
}
