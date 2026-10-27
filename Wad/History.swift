// History.swift
// Ein Verlauf mit höchstens 20 Texten, neuester oben (SPEC 1.6 und 2.4). Liegt nur im
// Arbeitsspeicher und wird nie auf die Festplatte geschrieben.

struct History: Equatable {
    static let limit = 20

    private(set) var entries: [String] = []

    /// Fügt oben ein. Gibt es den Text schon, rückt er nach oben statt doppelt zu erscheinen.
    /// Beim 21. Eintrag fällt der älteste sofort heraus.
    mutating func add(_ text: String) {
        entries.removeAll { $0 == text }
        entries.insert(text, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
    }

    /// Ersetzt eine frühere Fassung desselben Textes durch die neue, die dann oben steht.
    mutating func replace(_ old: String?, with new: String) {
        if let old { entries.removeAll { $0 == old } }
        add(new)
    }

    /// Entfernt alle Einträge sofort. Ehrliche Grenze (SPEC 2.4): Swift erlaubt nicht, den Speicher
    /// eines Textes zuverlässig mit Nullen zu überschreiben, weil jede Anzeige im Menü Kopien erzeugt,
    /// die Swift selbst verwaltet. Freigegebener Speicher bleibt im abgeschotteten Bereich von Wad,
    /// wird von macOS beim Beenden zurückgenommen und ist für andere Programme nie lesbar.
    mutating func clear() {
        entries.removeAll()
    }
}
