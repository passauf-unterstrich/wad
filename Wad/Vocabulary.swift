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

    private static func parse(_ rawLine: Substring) -> Entry? {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
        let parts = line.components(separatedBy: "->").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 1 { return Entry(wrong: nil, right: parts[0]) }
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return Entry(wrong: parts[0], right: parts[1])
    }

    /// Ersetzt jede falsche Schreibweise, aber nur als ganzes Wort und unabhängig von Groß- und
    /// Kleinschreibung. „Watt“ in „Wattestäbchen“ bleibt also unangetastet.
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
        while let found = result.range(of: word, options: .caseInsensitive, range: searchStart..<result.endIndex) {
            let startsWord = found.lowerBound == result.startIndex || !isWordCharacter(result[result.index(before: found.lowerBound)])
            let endsWord = found.upperBound == result.endIndex || !isWordCharacter(result[found.upperBound])
            if startsWord && endsWord {
                let offset = result.distance(from: result.startIndex, to: found.lowerBound)
                result.replaceSubrange(found, with: replacement)
                searchStart = result.index(result.startIndex, offsetBy: offset + replacement.count)
            } else {
                searchStart = found.upperBound
            }
        }
        return result
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}
