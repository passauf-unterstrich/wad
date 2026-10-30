// TextSpacing.swift
// Wo zwischen zwei Textstücken ein Leerzeichen steht. Japanisch und Chinesisch kennen keine Leerzeichen
// zwischen Wörtern. Entschieden wird an den Zeichen selbst, nicht an der eingestellten Sprache: So stimmt es
// auch, wenn „Sprachoffen“ die Sprache erst beim Diktieren erkennt.

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
    /// Gehört zwischen diese zwei Zeichen ein Leerzeichen? Nicht am Textanfang, nicht vor Satzzeichen,
    /// nicht neben schon vorhandenem Leerraum und nicht neben Japanisch oder Chinesisch.
    static func needsSpace(between left: Character?, and right: Character?) -> Bool {
        guard let left, let right, !left.isWhitespace, !right.isWhitespace else { return false }
        return !",.;:!?)".contains(right) && !left.isCJK && !right.isCJK
    }

    /// Hängt `next` an `text`, nur wenn nötig mit Leerzeichen.
    static func join(_ text: String, _ next: String) -> String {
        needsSpace(between: text.last, and: next.first) ? text + " " + next : text + next
    }
}
