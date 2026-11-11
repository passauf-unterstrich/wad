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
    /// Ein bloßes „Absatz“ kommt nach „neuer Absatz“, sonst bliebe „neuer“ stehen.
    private static let commands: [(words: String, mark: String)] = [
        ("neuer absatz|new paragraph", "\n\n"),
        ("absatz", "\n\n"),
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
            // Nach einem Umbruch fällt auch ein Umbruch weg, den Whisper oder Wad schon gesetzt hat:
            // Aus „Absatz.\n\nDann“ wird eine Leerzeile, nicht zwei.
            if trimsSpace { piece = String(piece.drop { $0.isWhitespace }) }
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
                // Stand davor schon ein Umbruch („Absatz, neuer Absatz“), bleibt es bei höchstens einer Leerzeile.
                var breaks = 0
                while result.last?.isNewline == true { result.removeLast(); breaks += 1 }
                result += String(repeating: "\n", count: min(max(breaks, mark.count), 2))
            } else {
                result += mark
            }
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

extension TextSpacing {
    /// Nie mehr als eine Leerzeile: Endet der Text davor schon mit einem Umbruch, etwa nach einem angesagten
    /// „Absatz“, fällt der Leerraum am Anfang des neuen Stücks weg, auch sein eigener Absatz.
    static func trimmingLeadingBreak(_ text: String, after last: Character?) -> String {
        guard let last, last.isNewline else { return text }
        return String(text.drop { $0.isWhitespace })
    }
}

/// Absätze automatisch (Schalter, ab Werk an). Wer beim Sprechen lange innehält, beginnt meist einen neuen
/// Gedanken. Wad macht dort eine Leerzeile, aber erst, wenn der Absatz davor schon zwei Sätze hat: Kurzes
/// Nachdenken mitten im Gedanken soll keinen Absatz aus einem halben Satz machen. Spätestens nach sechs Sätzen
/// kommt einer auch ohne Pause, damit lange Diktate nicht zu einem Block werden. Dazu bekommen Anrede und
/// Grußformel in Briefen und Mails ihre eigene Zeile.
/// Ein Absatz ist immer eine Leerzeile. Nie zwischen zwei Diktaten und nie vor dem ersten Stück eines Diktats,
/// denn wohin ein neues Diktat kommt, entscheidet der Cursor.
struct ParagraphPlanner {
    /// So lange Stille macht einen Absatz.
    static let pause: TimeInterval = 2.0
    static let minSentences = 2
    static let maxSentences = 6
    static let paragraphBreak = "\n\n"

    /// Sätze im laufenden Absatz.
    private(set) var sentences = 0
    /// Sätze im ganzen Diktat, ohne die Anrede. Eine Grußformel braucht davor einen Brief.
    private(set) var totalSentences = 0

    private static let sentenceMarks: Set<Character> = [".", "!", "?", "。", "！", "？"]
    private static let greetings = ["sehr geehrter", "sehr geehrte", "guten morgen", "guten tag", "guten abend",
                                    "good morning", "hallo", "hello", "hi", "hey", "moin", "servus",
                                    "liebes", "lieber", "liebe", "dear"]
    /// Eine Grußformel braucht davor nur einen Satz: Auch eine kurze Nachricht bekommt ihren Gruß abgesetzt.
    static let closingSentences = 1
    /// Grußformeln, die immer als Gruß zählen, mit oder ohne Namen dahinter.
    private static let longClosings = withSwissSpelling([
        "mit freundlichen grüßen", "freundliche grüße", "herzliche grüße", "schöne grüße", "viele grüße",
        "liebe grüße", "beste grüße", "lieben gruß", "herzlichen gruß", "schönen gruß", "besten gruß",
        "viele liebe grüße", "best regards", "kind regards", "best wishes", "warm regards",
    ])
    /// Kurze Grüße sind auch gewöhnliche Wörter („LG ist gut.“, „Danke.“). Sie zählen nur, wenn ein Name
    /// das Stück beendet: „Gruß Linus“, „LG, Anna.“
    private static let shortClosings = withSwissSpelling([
        "gruß", "grüße", "lg", "vg", "ciao", "tschüss", "tschüs", "bis bald", "bis dann", "bis später",
        "cheers", "thanks", "danke", "best", "regards",
    ])
    /// Diese Anreden sind auch gewöhnliche Wörter („Liebe ist schön, aber …“). Als Anrede zählen sie nur
    /// vor einem großgeschriebenen Namen oder Titel. „Hallo zusammen,“ braucht das nicht.
    private static let greetingsBeforeName: Set<String> = ["sehr geehrter", "sehr geehrte", "liebes", "lieber", "liebe", "dear"]

    /// Ordnet ein Stück an. `previous` ist das Stück davor im selben Diktat, `nil` beim ersten;
    /// `pause` die Stille davor in Sekunden.
    /// - Returns: das Stück mit seinem Trenner davor: nichts, ein Leerzeichen oder eine Leerzeile.
    mutating func layout(_ text: String, after previous: String?, pause: TimeInterval) -> String {
        let c = Array(text)
        var separator = ""
        var out = ""
        var i = 0
        if let previous {
            let endsSentence = previous.last(where: { !$0.isWhitespace }).map(Self.sentenceMarks.contains) ?? false
            let opensClosing = Self.closing(in: c, at: 0) != nil && totalSentences >= Self.closingSentences
            if endsSentence, sentences >= Self.maxSentences || opensClosing
                || (pause >= Self.pause && sentences >= Self.minSentences) {
                separator = Self.paragraphBreak
                sentences = 0
            } else if TextSpacing.needsSpace(between: previous.last, and: c.first) {
                separator = " "
            }
        } else if let comma = Self.greetingEnd(in: c) {
            // Die Anrede bekommt ihre eigene Zeile, aber nur vor einem richtigen Brief, nicht vor „Hey, bin gleich da.“
            var rest = comma + 1
            while rest < c.count, c[rest].isWhitespace { rest += 1 }
            if rest > comma + 1, Self.sentenceCount(in: c, from: rest) >= Self.minSentences {
                out = String(c[...comma]) + Self.paragraphBreak
                i = rest
            }
        }

        while i < c.count {
            if let end = Self.closing(in: c, at: i), totalSentences >= Self.closingSentences,
               i == 0 ? separator == Self.paragraphBreak : Self.followsSentenceOrBreak(out) {
                if i > 0 {
                    while out.last?.isWhitespace == true { out.removeLast() }
                    out += Self.paragraphBreak
                }
                sentences = 0
                // „Viele Grüße, Linus.“ wird zu „Viele Grüße“ und darunter der Name, ohne Komma und Punkt.
                if let name = Self.signature(in: c, from: end) {
                    return separator + out + String(c[i..<end]) + "\n" + name
                }
                out += String(c[i..<end])
                i = end
                continue
            }
            out.append(c[i])
            if Self.isSentenceEnd(c, at: i) {
                sentences += 1
                totalSentences += 1
                var next = i + 1
                while next < c.count, c[next].isWhitespace { next += 1 }
                // Notbremse: Nach sechs Sätzen kommt ein Absatz, wenn im selben Stück noch etwas folgt.
                if sentences >= Self.maxSentences, next < c.count {
                    out += Self.paragraphBreak
                    sentences = 0
                    i = next
                    continue
                }
            }
            i += 1
        }
        return separator + out
    }

    /// Teilt die Sprache eines Stücks an langen Pausen, damit dort ein Absatz hin kann. Jede Gruppe reicht bis
    /// zur Mitte der Pause, die nächste beginnt dort. Eine Gruppe mit zu wenig Sprache (ein Räuspern) bleibt bei
    /// ihrer Nachbarin, damit das Modell nie ein Stück ohne Wörter bekommt.
    /// - Parameters:
    ///   - speech: Sprachabschnitte im Stück, aufsteigend, in Samples.
    ///   - length: Länge des Stücks.
    ///   - pause: ab so vielen Samples Stille wird geteilt.
    ///   - minSpeech: so viel Sprache braucht eine Gruppe mindestens.
    /// - Returns: die Gruppen und jeweils die Stille davor. Bei der ersten ist das nur die Stille im Stück selbst.
    static func groups(speech: [Range<Int>], length: Int, pause: Int, minSpeech: Int) -> [(range: Range<Int>, pauseBefore: Int)] {
        guard let first = speech.first else { return [(0..<length, 0)] }
        var groups: [[Range<Int>]] = [[first]]
        for (a, b) in zip(speech, speech.dropFirst()) {
            if b.lowerBound - a.upperBound >= pause { groups.append([b]) } else { groups[groups.count - 1].append(b) }
        }
        var index = 0
        while groups.count > 1, index < groups.count {
            guard groups[index].reduce(0, { $0 + $1.count }) < minSpeech else { index += 1; continue }
            if index > 0 {
                groups[index - 1] += groups.remove(at: index)
            } else {
                let small = groups.remove(at: 0)
                groups[0] = small + groups[0]
            }
        }
        var result: [(range: Range<Int>, pauseBefore: Int)] = []
        var start = 0
        for (k, group) in groups.enumerated() {
            let pauseBefore = k == 0 ? group[0].lowerBound : group[0].lowerBound - groups[k - 1].last!.upperBound
            let end = k + 1 < groups.count ? (group.last!.upperBound + groups[k + 1][0].lowerBound) / 2 : length
            result.append((start..<end, pauseBefore))
            start = end
        }
        return result
    }

    /// Satzende: . ! ? oder 。！？, danach Leerraum und ein Großbuchstabe, ein japanisches oder chinesisches
    /// Zeichen oder das Ende des Texts.
    private static func isSentenceEnd(_ c: [Character], at i: Int) -> Bool {
        guard sentenceMarks.contains(c[i]) else { return false }
        var next = i + 1
        if next < c.count, c[next].isCJK { return true }
        guard next == c.count || c[next].isWhitespace else { return false }
        while next < c.count, c[next].isWhitespace { next += 1 }
        return next == c.count || c[next].isUppercase
    }

    private static func sentenceCount(in c: [Character], from start: Int) -> Int {
        (start..<c.count).filter { isSentenceEnd(c, at: $0) }.count
    }

    /// Endet der Text bisher mit einem Satz oder einem Umbruch?
    private static func followsSentenceOrBreak(_ text: String) -> Bool {
        let trailing = text.reversed().prefix { $0.isWhitespace }
        if trailing.contains(where: \.isNewline) { return true }
        return text.last(where: { !$0.isWhitespace }).map(sentenceMarks.contains) ?? false
    }

    /// Beginnt bei `i` eines der Wörter als ganzes Wort, Groß- und Kleinschreibung egal? Rückgabe: wo es endet.
    private static func phrase(_ phrases: [String], in c: [Character], at i: Int) -> Int? {
        guard i == 0 || !c[i - 1].isLetter else { return nil }
        for phrase in phrases {
            let end = i + phrase.count
            guard end <= c.count, String(c[i..<end]).lowercased() == phrase,
                  end == c.count || !c[end].isLetter else { continue }
            return end
        }
        return nil
    }

    /// Beginnt bei `i` eine Grußformel? Rückgabe: wo sie endet. Ein kurzer Gruß nur mit Namen dahinter.
    private static func closing(in c: [Character], at i: Int) -> Int? {
        if let end = phrase(longClosings, in: c, at: i) { return end }
        guard let end = phrase(shortClosings, in: c, at: i), signature(in: c, from: end) != nil else { return nil }
        return end
    }

    /// Jede Formel auch in Schweizer Schreibung mit „ss“ statt „ß“, die längsten zuerst, damit „viele liebe Grüße“
    /// nicht als „liebe Grüße“ halb erkannt wird.
    private static func withSwissSpelling(_ phrases: [String]) -> [String] {
        let all = phrases + phrases.filter { $0.contains("ß") }.map { $0.replacingOccurrences(of: "ß", with: "ss") }
        return all.sorted { $0.count > $1.count }
    }

    /// Wo das Komma oder Ausrufezeichen nach einer Anrede am Textanfang steht: „Hallo Anna,“, „Liebe Frau Müller,“,
    /// „Hi!“. Zwischen Anrede und Zeichen höchstens vier Wörter.
    private static func greetingEnd(in c: [Character]) -> Int? {
        guard var p = phrase(greetings, in: c, at: 0) else { return nil }
        if greetingsBeforeName.contains(String(c[..<p]).lowercased()) {
            guard p + 1 < c.count, c[p] == " ", c[p + 1].isUppercase else { return nil }
        }
        var words = 0
        while p < c.count {
            if c[p] == "," || c[p] == "!" { return p }
            guard c[p] == " ", words < 4 else { return nil }
            var q = p + 1
            while q < c.count, !c[q].isWhitespace, !",!.?".contains(c[q]) { q += 1 }
            guard q > p + 1 else { return nil }
            words += 1
            p = q
        }
        return nil
    }

    /// Ein Name aus ein bis drei großgeschriebenen Wörtern am Ende, nach einem Komma oder Leerzeichen,
    /// wahlweise mit Punkt oder Ausrufezeichen dahinter. Rückgabe: der Name ohne diese Zeichen.
    private static func signature(in c: [Character], from start: Int) -> String? {
        var p = start
        if p < c.count, c[p] == "," { p += 1 }
        guard p < c.count, c[p].isWhitespace else { return nil }
        while p < c.count, c[p].isWhitespace { p += 1 }
        var end = c.count
        while end > p, c[end - 1].isWhitespace { end -= 1 }
        if end > p, c[end - 1] == "." || c[end - 1] == "!" { end -= 1 }
        guard end > p else { return nil }
        let words = String(c[p..<end]).split(separator: " ", omittingEmptySubsequences: false)
        guard (1...3).contains(words.count), words.allSatisfy({ word in
            word.first?.isUppercase == true && word.allSatisfy { $0.isLetter || $0 == "-" }
        }) else { return nil }
        return String(c[p..<end])
    }
}
