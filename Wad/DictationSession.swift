// DictationSession.swift
// Ein einzelnes Diktat von der Aufnahme bis zum fertigen Text. Merkt sich, bis wohin schon
// umgewandelt wurde, welche Sprache erkannt ist und welcher Text schon eingefügt wurde.
// Jedes Audiostück wird direkt nach seiner Umwandlung mit Nullen überschrieben (SPEC 2.3).
//
// Alles außer `isCancelled` wird ausschließlich auf der Hintergrund-Warteschlange benutzt.

final class DictationSession {
    let audio: AudioBuffer
    /// Nur Hauptthread: Wurde das Diktat abgebrochen, wird nichts mehr eingefügt.
    var isCancelled = false

    private let transcriber: Transcriber
    /// Richtige Schreibweisen aus der Vokabelliste, die das Modell vorab als Hinweis bekommt.
    private let vocabularyHint: String?
    private var offset = 0
    private var language: String?
    private var texts: [String] = []

    /// - Parameter language: fest gewählte Sprache wie „de“. `nil` erkennt sie am ersten Stück.
    init(audio: AudioBuffer, transcriber: Transcriber, language: String? = nil, vocabularyHint: String? = nil) {
        self.audio = audio
        self.transcriber = transcriber
        self.language = language
        self.vocabularyHint = vocabularyHint
    }

    /// Der ganze Text des Diktats, Stücke mit Leerzeichen verbunden.
    var fullText: String { texts.joined(separator: " ") }

    /// Live: sucht im noch offenen Teil eine passende Pause und wandelt das Stück davor um.
    /// Rückgabe ist der einzufügende Text, sonst `nil`.
    func transcribeReadyChunk() -> String? {
        let (cut, text) = audio.withSamples(from: offset) { open -> (Int?, String?) in
            guard open.count >= ChunkPlanner.minChunk else { return (nil, nil) }
            let speech = transcriber.speechSegments(in: open)
            guard let cut = ChunkPlanner.cutPoint(speech: speech, length: open.count) else { return (nil, nil) }
            return (cut, transcribe(open, upTo: cut, speech: speech))
        }
        if let cut { advance(by: cut) }
        return text
    }

    /// Nach dem Loslassen: wandelt alles um, was noch offen ist.
    func transcribeRemainder() -> String? {
        let (length, text) = audio.withSamples(from: offset) { open -> (Int, String?) in
            (open.count, transcribe(open, upTo: open.count, speech: transcriber.speechSegments(in: open)))
        }
        advance(by: length)
        return text
    }

    /// Vorschau: wandelt den noch offenen Teil probeweise um, ohne ihn als fertig abzuhaken.
    /// Das Ergebnis ist nur ein vorläufiger Text fürs Vorschau-Fenster und wird nirgends gespeichert.
    func transcribeDraft() -> String? {
        audio.withSamples(from: offset) { open -> String? in
            let speech = transcriber.speechSegments(in: open)
            guard ChunkPlanner.containsSpeech(speech) else { return nil }
            let prompt = [vocabularyHint, texts.last].compactMap { $0 }.joined(separator: " ")
            return try? transcriber.transcribe(open, language: language, prompt: prompt.isEmpty ? nil : prompt).text
        }
    }

    /// Löscht Audio und Zwischenstände. Danach existiert von diesem Diktat nur noch, was eingefügt wurde.
    func discard() {
        audio.wipe()
        texts.removeAll()
    }

    private func transcribe(_ open: UnsafeBufferPointer<Float>, upTo cut: Int, speech: [Range<Int>]) -> String? {
        let speechInChunk = speech.filter { $0.lowerBound < cut }.map { $0.clamped(to: 0..<cut) }
        guard ChunkPlanner.containsSpeech(speechInChunk) else { return nil }

        let chunk = UnsafeBufferPointer(rebasing: open[0..<cut])
        let prompt = [vocabularyHint, texts.last].compactMap { $0 }.joined(separator: " ")
        guard let result = try? transcriber.transcribe(chunk, language: language, prompt: prompt.isEmpty ? nil : prompt),
              !result.text.isEmpty else { return nil }

        language = language ?? result.language
        let needsSpace = !texts.isEmpty && !(result.text.first.map { ",.;:!?)".contains($0) } ?? false)
        texts.append(result.text)
        return needsSpace ? " " + result.text : result.text
    }

    private func advance(by length: Int) {
        audio.wipe(range: offset..<(offset + length))
        offset += length
    }
}
