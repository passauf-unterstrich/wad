// Transcriber.swift
// Die eine Schnittstelle zur Spracherkennung (SPEC 1.5). Der Rest von Wad kennt nur dieses
// Protokoll, so lässt sich das Modell später austauschen, ohne anderen Code anzufassen.
// Alle Aufrufe blockieren und passieren nacheinander auf Wads Hintergrund-Warteschlange.

struct Transcription {
    let text: String
    /// Sprachkürzel, z. B. „de“. Wird für die restlichen Stücke eines Diktats beibehalten.
    let language: String
}

protocol Transcriber: AnyObject {
    /// Abschnitte, in denen gesprochen wird, in Samples ab Beginn von `samples`, aufsteigend.
    func speechSegments(in samples: UnsafeBufferPointer<Float>) -> [Range<Int>]

    /// Wandelt Sprache in Text um.
    /// - Parameters:
    ///   - language: `nil` erkennt die Sprache selbst.
    ///   - prompt: vorheriger Text desselben Diktats. Gibt dem Modell Zusammenhang über die Schnittstelle hinweg.
    func transcribe(_ samples: UnsafeBufferPointer<Float>, language: String?, prompt: String?) throws -> Transcription
}
