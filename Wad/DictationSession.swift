// DictationSession.swift
// Ein einzelnes Diktat von der Aufnahme bis zum fertigen Text. Merkt sich, bis wohin schon
// umgewandelt wurde, welche Sprache erkannt ist und welcher Text schon eingefügt wurde.
// Jedes Audiostück wird direkt nach seiner Umwandlung mit Nullen überschrieben (SPEC 2.3).
//
// Alles außer `isCancelled` wird ausschließlich auf der Hintergrund-Warteschlange benutzt.

import Foundation

final class DictationSession {
    let audio: AudioBuffer
    /// Nur Hauptthread: Wurde das Diktat abgebrochen, wird nichts mehr eingefügt.
    var isCancelled = false

    private let transcriber: Transcriber
    /// Richtige Schreibweisen aus der Vokabelliste, die das Modell vorab als Hinweis bekommt.
    private let vocabularyHint: String?
    private var offset = 0
    private var language: String?
    /// Die fertigen Stücke, jedes mit seinem Trenner davor (nichts, Leerzeichen oder Leerzeile).
    private var texts: [String] = []
    /// Absätze automatisch: an langen Pausen eine Leerzeile, dazu Anrede und Grußformel auf eigene Zeilen.
    private let autoParagraphs: Bool
    private var paragraphs = ParagraphPlanner()
    /// Ist „Satzzeichen ansagen“ an, kommt ein Punkt an Sprechpausen und am Ende nur von der Ansage, nie von Whisper.
    private let spokenPunctuation: Bool
    /// Whispers Punkt am Ende des letzten Stücks, noch nicht eingefügt. Ob er bleibt, zeigt erst das nächste Stück
    /// (`PausePunctuation`). Spätestens am Ende des Diktats kommt er dazu.
    private var heldPeriod = false
    /// Stille nach der letzten Sprache im schon Umgewandelten, in Samples. Mit ihr zählt auch eine Pause,
    /// die genau auf einen Schnitt fällt oder in einem Stück ganz ohne Sprache liegt.
    private var trailingSilence = 0
    /// Ab so viel Stille kann ein Absatz kommen.
    private static let paragraphPause = Int(ParagraphPlanner.pause * AudioBuffer.sampleRate)
    /// Whisper mischt im Chinesischen Kurz- und Langzeichen. Dieser Satz in Kurzzeichen lenkt es auf Kurzzeichen.
    private static let simplifiedChineseHint = "以下是普通话的句子。"

    /// - Parameter language: fest gewählte Sprache wie „de“. `nil` erkennt sie am ersten Stück.
    init(audio: AudioBuffer, transcriber: Transcriber, language: String? = nil, vocabularyHint: String? = nil,
         autoParagraphs: Bool = false, spokenPunctuation: Bool = false) {
        self.audio = audio
        self.transcriber = transcriber
        self.language = language
        self.vocabularyHint = vocabularyHint
        self.autoParagraphs = autoParagraphs
        self.spokenPunctuation = spokenPunctuation
    }

    /// Der ganze Text des Diktats, Stücke verbunden wie beim Einfügen.
    var fullText: String { texts.reduce("", TextSpacing.join) }

    /// Der Zusammenhang fürs Modell: Vokabeln, bei Chinesisch der Hinweis auf Kurzzeichen, das vorige Stück.
    /// Ein zurückgehaltener Punkt fehlt darin, so schreibt Whisper einen angefangenen Satz eher weiter.
    private var prompt: String? {
        let previous = texts.last?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [vocabularyHint, language == "zh" ? Self.simplifiedChineseHint : nil, previous].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

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

    /// Nach dem Loslassen: wandelt alles um, was noch offen ist. Ein zurückgehaltener Punkt kommt jetzt dazu,
    /// direkt ans letzte Wort, aber nicht mit „Satzzeichen ansagen“: Dann setzt nur die Ansage den Schlusspunkt.
    func transcribeRemainder() -> String? {
        let (length, text) = audio.withSamples(from: offset) { open -> (Int, String?) in
            (open.count, transcribe(open, upTo: open.count, speech: transcriber.speechSegments(in: open)))
        }
        advance(by: length)
        guard heldPeriod, !texts.isEmpty else { return text }
        heldPeriod = false
        if spokenPunctuation { return text }
        texts[texts.count - 1] += "."
        return (text ?? "") + "."
    }

    /// Vorschau: wandelt den noch offenen Teil probeweise um, ohne ihn als fertig abzuhaken.
    /// Das Ergebnis ist nur ein vorläufiger Text fürs Vorschau-Fenster und wird nirgends gespeichert.
    func transcribeDraft() -> String? {
        audio.withSamples(from: offset) { open -> String? in
            let speech = transcriber.speechSegments(in: open)
            guard ChunkPlanner.containsSpeech(speech) else { return nil }
            return (try? transcriber.transcribe(open, language: language, prompt: prompt).text)
                .map { TextSpacing.separatingSentences(PausePunctuation.removingEllipses($0)) }
        }
    }

    /// Löscht Audio und Zwischenstände. Danach existiert von diesem Diktat nur noch, was eingefügt wurde.
    func discard() {
        audio.wipe()
        texts.removeAll()
        heldPeriod = false
    }

    /// Wandelt das Stück bis `cut` um. Mit „Absätze automatisch“ einzeln je Abschnitt zwischen langen Pausen,
    /// so kann der Absatz genau dort hin, auch bei „Nach dem Diktat“, wo alles in einem Stück kommt.
    private func transcribe(_ open: UnsafeBufferPointer<Float>, upTo cut: Int, speech: [Range<Int>]) -> String? {
        let speechInChunk = speech.filter { $0.lowerBound < cut }.map { $0.clamped(to: 0..<cut) }
        guard ChunkPlanner.containsSpeech(speechInChunk), let lastSpeech = speechInChunk.last else {
            trailingSilence += cut
            return nil
        }
        defer { trailingSilence = cut - lastSpeech.upperBound }

        let groups = autoParagraphs
            ? ParagraphPlanner.groups(speech: speechInChunk, length: cut, pause: Self.paragraphPause,
                                      minSpeech: ChunkPlanner.minSpeech)
            : [(range: 0..<cut, pauseBefore: speechInChunk[0].lowerBound)]
        var piece = ""
        for (index, group) in groups.enumerated() {
            let chunk = UnsafeBufferPointer(rebasing: open[group.range])
            guard let result = try? transcriber.transcribe(chunk, language: language, prompt: prompt),
                  !result.text.isEmpty else { continue }

            language = language ?? result.language
            let text = TextSpacing.separatingSentences(PausePunctuation.removingEllipses(result.text))
            guard !text.isEmpty else { continue }

            // Erst entscheiden, ob der Punkt vom letzten Stück bleibt. Wenn ja, klebt er am letzten Wort und kommt
            // vor dieses Stück. Wenn nein, zählt er auch nicht als Satz für die Absätze.
            var period = ""
            if heldPeriod, let previous = texts.last {
                heldPeriod = false
                if PausePunctuation.keepsHeldPeriod(after: previous, before: text, spokenPunctuation: spokenPunctuation) {
                    texts[texts.count - 1] += "."
                    period = "."
                } else if autoParagraphs {
                    paragraphs.retractSentence()
                }
            }
            var laidOut: String
            if autoParagraphs {
                let pause = index == 0 ? trailingSilence + group.pauseBefore : group.pauseBefore
                laidOut = paragraphs.layout(text, after: texts.last, pause: Double(pause) / AudioBuffer.sampleRate)
            } else {
                laidOut = TextSpacing.needsSpace(between: texts.last?.last, and: text.first) ? " " + text : text
            }
            // Den eigenen Schlusspunkt erst einmal zurückhalten. Erst nach dem Anordnen: Eine Grußformel mit Namen
            // hat ihren Punkt dort schon verloren und bekommt so auch keinen zurück.
            (laidOut, heldPeriod) = PausePunctuation.splittingTrailingPeriod(laidOut)
            texts.append(laidOut)
            piece += period + laidOut
        }
        return piece.isEmpty ? nil : piece
    }

    private func advance(by length: Int) {
        audio.wipe(range: offset..<(offset + length))
        offset += length
    }
}
