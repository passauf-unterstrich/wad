// ChunkPlanner.swift
// Entscheidet beim Live-Chunking, wo die Aufnahme geschnitten wird (SPEC 1.4): immer mitten in
// einer Sprechpause, damit kein Wort zerteilt wird. Reine Rechenlogik, deshalb vollständig getestet.
// Erfahrungswerte aus Linus' alter Version: Schnitt an Pausen, Notschnitt bei zu langem Stück.

enum ChunkPlanner {
    /// Frühestens nach so viel Audio wird geschnitten. Kürzere Stücke geben dem Modell zu wenig Zusammenhang.
    static let minChunk = seconds(10)
    /// Spätestens hier wird geschnitten, auch ohne Pause: Whisper verarbeitet 30-Sekunden-Fenster.
    static let maxChunk = seconds(30)
    /// So lange muss eine Stille mindestens dauern, um als Satz- oder Gedankenpause zu gelten.
    static let minPause = seconds(0.6)
    /// Weniger erkannte Sprache als das gilt als Stille. Solche Stücke gehen gar nicht erst an das
    /// Modell, so entstehen keine Halluzinationen wie „Untertitel im Auftrag des ZDF“.
    static let minSpeech = seconds(0.3)

    /// Wo das nächste Stück enden soll, gemessen ab Beginn des offenen Bereichs. `nil` heißt: noch warten.
    /// - Parameters:
    ///   - speech: erkannte Sprachabschnitte im offenen Bereich, aufsteigend.
    ///   - length: Länge des offenen Bereichs in Samples.
    static func cutPoint(speech: [Range<Int>], length: Int) -> Int? {
        guard length >= minChunk else { return nil }

        // Pausen zwischen zwei Abschnitten und die Stille nach dem letzten, jeweils als Bereich.
        var pauses = zip(speech, speech.dropFirst()).map { $0.upperBound..<$1.lowerBound }
        if let last = speech.last { pauses.append(last.upperBound..<length) }

        let candidates = pauses.filter { $0.count >= minPause }
            .map { $0.lowerBound + $0.count / 2 }
            .filter { (minChunk...maxChunk).contains($0) }
        if let latest = candidates.last { return latest }

        // Notschnitt ohne lange Pause: in der längsten Lücke, die es gibt, sonst hart bei der Obergrenze.
        guard length >= maxChunk else { return nil }
        let gap = pauses.filter { $0.lowerBound >= minChunk && $0.upperBound <= maxChunk }
            .max { $0.count < $1.count }
        return gap.map { $0.lowerBound + $0.count / 2 } ?? maxChunk
    }

    /// Ob in einem Stück genug Sprache steckt, um es umzuwandeln.
    static func containsSpeech(_ speech: [Range<Int>]) -> Bool {
        speech.reduce(0) { $0 + $1.count } >= minSpeech
    }

    private static func seconds(_ value: Double) -> Int {
        Int(value * AudioBuffer.sampleRate)
    }
}
