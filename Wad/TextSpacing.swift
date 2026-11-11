// TextSpacing.swift
// Wo zwischen zwei Textstücken ein Leerzeichen steht. Japanisch und Chinesisch kennen keine Leerzeichen
// zwischen Wörtern. Entschieden wird an den Zeichen selbst, nicht an der eingestellten Sprache: So stimmt es
// auch, wenn „Sprachoffen“ die Sprache erst beim Diktieren erkennt.

import Foundation

extension Character {
    /// Chinesische Zeichen, Kana sowie die zugehörigen Satzzeichen und Vollbreit-Formen. Koreanisch gehört
    /// nicht dazu, es trennt Wörter mit Leerzeichen.
    var isCJK: Bool {
        guard let scalar = unicodeScalars.first?.value else { return false }
        switch scalar {
        case 0x2E80...0x2FDF,       // Radikale
             0x3000...0x30FF,       // Satzzeichen, Hiragana, Katakana
             0x3100...0x312F,       // Bopomofo
             0x31C0...0x33FF,       // Striche, Katakana-Erweiterung, Umschlossenes
             0x3400...0x4DBF,       // Chinesische Zeichen, Erweiterung A
             0x4E00...0x9FFF,       // Chinesische Zeichen
             0xF900...0xFAFF,       // Kompatibilitätszeichen
             0xFF00...0xFFEF,       // Vollbreit- und Halbbreit-Formen
             0x20000...0x3FFFF:     // Chinesische Zeichen, weitere Erweiterungen
            return true
        default:
            return false
        }
    }
}

enum TextSpacing {
    /// Gehört zwischen diese zwei Zeichen ein Leerzeichen? Nicht am Textanfang, nicht vor Satzzeichen, nicht nach einer öffnenden Klammer,
    /// nicht neben schon vorhandenem Leerraum und nicht neben Japanisch oder Chinesisch.
    static func needsSpace(between left: Character?, and right: Character?) -> Bool {
        guard let left, let right, !left.isWhitespace, !right.isWhitespace else { return false }
        return !",.;:!?)".contains(right) && !"([{„‚«/".contains(left) && !left.isCJK && !right.isCJK
    }

    /// Hängt `next` an `text`, nur wenn nötig mit Leerzeichen.
    static func join(_ text: String, _ next: String) -> String {
        needsSpace(between: text.last, and: next.first) ? text + " " + next : text + next
    }
}

extension TextSpacing {
    /// Whisper vergisst gelegentlich das Leerzeichen nach einem Satzende („Gut.Dann“). Setzt es dort ein,
    /// aber nur, wenn es eindeutig ein neuer Satz ist: davor ein Wort aus mindestens zwei Buchstaben, danach
    /// ein Großbuchstabe und ein Kleinbuchstabe. So bleiben „z.B.“, „U.S.A.“, „3.5“, „wad.app“ und „ASP.NET“ unberührt.
    static func separatingSentences(_ text: String) -> String {
        let characters = Array(text)
        guard characters.count >= 4 else { return text }
        var result = ""
        result.reserveCapacity(text.count + 4)
        for (index, character) in characters.enumerated() {
            result.append(character)
            guard ".!?".contains(character), index >= 2, index + 2 < characters.count else { continue }
            let before = characters[index - 1], beforeThat = characters[index - 2]
            let next = characters[index + 1], afterNext = characters[index + 2]
            if before.isLetter, before.isLowercase, beforeThat.isLetter, !before.isCJK,
               next.isUppercase, afterNext.isLowercase {
                result.append(" ")
            }
        }
        return result
    }

    /// Kleinschreibung ganz ohne Großbuchstaben und ohne „ß“: aus „Straße“ wird „strasse“,
    /// aus „STRASSE“ oder „ẞ“ ebenso. Läuft nach den Vokabeln, gewinnt also immer.
    static func lowercased(_ text: String) -> String {
        text.lowercased(with: .current).replacingOccurrences(of: "ß", with: "ss")
    }
}

/// Angesagte Satzzeichen (Schalter „Satzzeichen ansagen“, Standard aus). Wer es von Apples Diktat gewohnt ist,
/// sagt „Komma“ oder „Punkt“ mit. Whisper setzt Satzzeichen aber schon selbst und schreibt das Wort dann oft
/// zusätzlich hin („gut, Komma, dann“). Hier wird aus Wort und doppeltem Zeichen genau ein Zeichen.
/// Ein echtes Wort bleibt stehen: „der springende Punkt“, „Punkt 12 Uhr“, „nach dem Komma“, „a period of time“.
enum SpokenPunctuation {
    /// Längere Ansagen zuerst, damit „neuer Absatz“ nicht als „neue…“ halb erkannt wird.
    private static let commands: [(words: String, mark: String)] = [
        ("neuer absatz|new paragraph", "\n\n"),
        ("neue zeile|new line|newline", "\n"),
        ("ausrufezeichen|exclamation mark|exclamation point", "!"),
        ("fragezeichen|question mark", "?"),
        ("doppelpunkt|colon", ":"),
        ("semikolon|strichpunkt|semicolon", ";"),
        ("komma|comma", ","),
        ("punkt|full stop|period", "."),
    ]

    /// Steht eines dieser Wörter direkt davor, ist das Satzzeichen-Wort ein echtes Wort.
    private static let articles: Set<String> = [
        "der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "einem", "eines", "einer",
        "kein", "keine", "keinen", "keinem", "dieser", "diesen", "diesem", "jeder", "jeden", "jedem",
        "welcher", "welchen", "welchem", "zum", "am", "im", "beim", "vom", "für", "pro",
        "a", "an", "the", "this", "that", "every", "each", "one", "per",
    ]

    private static let pattern: NSRegularExpression = {
        let words = commands.map { "(" + $0.words.replacingOccurrences(of: " ", with: "\\s+") + ")" }.joined(separator: "|")
        return try! NSRegularExpression(pattern: "([\\s,.;:!?]*)\\b(?:\(words))\\b[,.;:!?]*", options: [.caseInsensitive])
    }()

    static func apply(to text: String) -> String {
        let source = text as NSString
        var result = ""
        var position = 0
        var startsSentence = false
        var trimsSpace = false

        func appendSource(upTo end: Int) {
            var piece = source.substring(with: NSRange(location: position, length: end - position))
            if trimsSpace { piece = String(piece.drop { $0 == " " }) }
            if startsSentence, let index = piece.firstIndex(where: { !$0.isWhitespace }), piece[index].isLetter {
                piece.replaceSubrange(index...index, with: String(piece[index]).uppercased())
            }
            if !piece.isEmpty { startsSentence = false; trimsSpace = false }
            result += piece
        }

        for match in pattern.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            guard let group = (2...(commands.count + 1)).first(where: { match.range(at: $0).location != NSNotFound }) else { continue }
            let mark = commands[group - 2].mark
            let before = source.substring(to: match.range.location)
            let after = source.substring(from: NSMaxRange(match.range))
            if isRealWord(before: before, after: after) { continue }

            appendSource(upTo: match.range.location)
            let isNewline = mark.hasPrefix("\n")
            // Hat Whisper vor „neue Zeile“ schon einen Punkt gesetzt, bleibt er. Vor allen anderen Zeichen fällt
            // sein eigenes Zeichen weg, das angesagte gewinnt.
            if isNewline {
                result += source.substring(with: match.range(at: 1)).filter { !$0.isWhitespace }
                while result.last == " " { result.removeLast() }
            }
            result += mark
            if !isNewline, let next = after.first, next.isLetter || next.isNumber { result += " " }
            startsSentence = isNewline || ".!?".contains(mark)
            trimsSpace = isNewline
            position = NSMaxRange(match.range)
        }
        appendSource(upTo: source.length)
        return result
    }

    /// „der Punkt“, „den wichtigsten Punkt“, „Punkt 12“, „Punkt für Punkt“: kein Befehl.
    private static func isRealWord(before: String, after: String) -> Bool {
        let next = after.drop { $0.isWhitespace }
        if next.first?.isNumber == true { return true }
        let nextWord = next.prefix { $0.isLetter }.lowercased()
        if nextWord == "für" || nextWord == "for" || nextWord == "uhr" { return true }
        // Hat Whisper davor schon ein Satzzeichen gesetzt, war es als Ansage gemeint.
        guard let last = before.last(where: { !$0.isWhitespace }), last.isLetter || last.isNumber else { return false }
        let words = before.split { !$0.isLetter && !$0.isNumber }.suffix(2).map(String.init)
        guard let previous = words.last else { return false }
        if articles.contains(previous.lowercased()) { return true }
        // Ein kleingeschriebenes Adjektiv nach einem Artikel: „der springende Punkt“, „einen wichtigen Punkt“.
        let isAdjective = previous.first?.isLowercase == true
            && ["e", "en", "er", "es", "em"].contains { previous.hasSuffix($0) }
        return words.count == 2 && articles.contains(words[0].lowercased()) && isAdjective
    }
}
