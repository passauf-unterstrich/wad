// Transcriber.swift
// Die eine Schnittstelle zur Spracherkennung (SPEC 1.5). Der Rest von Wad kennt nur dieses
// Protokoll, so lässt sich das Modell später austauschen, ohne anderen Code anzufassen.

protocol Transcriber: AnyObject {
    /// Wandelt eine Aufnahme in Text um. Arbeitet im Hintergrund, `completion` kommt auf dem Hauptthread.
    /// Die Aufnahme wird nur gelesen, löschen muss sie der Aufrufer.
    func transcribe(_ audio: AudioBuffer, completion: @escaping (Result<String, Error>) -> Void)
}
