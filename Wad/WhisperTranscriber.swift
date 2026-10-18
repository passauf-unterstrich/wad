// WhisperTranscriber.swift
// Spracherkennung mit whisper.cpp und dem eingebauten Modell large-v3-turbo (SPEC 1.5).
// Läuft vollständig lokal auf der Grafikeinheit. Laden und Umwandeln passieren nacheinander
// auf einer eigenen Warteschlange, damit die Menüleiste nie hängt.

import Foundation

final class WhisperTranscriber: Transcriber {
    enum WhisperError: LocalizedError {
        case modelMissing, modelNotLoaded, failed

        var errorDescription: String? {
            switch self {
            case .modelMissing: "Das Sprachmodell fehlt in Wad.app"
            case .modelNotLoaded: "Das Sprachmodell konnte nicht geladen werden"
            case .failed: "Die Spracherkennung ist fehlgeschlagen"
            }
        }
    }

    static let modelName = "ggml-large-v3-turbo-q5_0"

    private let queue = DispatchQueue(label: "com.linushundt.Wad.whisper", qos: .userInitiated)
    private var context: OpaquePointer?

    /// Meldet auf dem Hauptthread, ob das Laden geklappt hat.
    var onLoaded: ((Error?) -> Void)?

    /// Beginnt sofort im Hintergrund mit dem Laden (rund eine Sekunde). Aufträge, die vorher
    /// eintreffen, warten in der Warteschlange einfach dahinter.
    init() {
        queue.async { [self] in
            let error = load()
            DispatchQueue.main.async { self.onLoaded?(error) }
        }
    }

    deinit {
        if let context { whisper_free(context) }
    }

    /// Gibt das Modell frei und wartet dafür eine laufende Umwandlung ab. Muss vor dem Beenden
    /// passieren: Der Metal-Teil von whisper.cpp stürzt sonst beim Aufräumen des Prozesses ab.
    func shutdown() {
        queue.sync {
            if let context { whisper_free(context) }
            context = nil
        }
    }

    func transcribe(_ audio: AudioBuffer, completion: @escaping (Result<String, Error>) -> Void) {
        queue.async { [self] in
            let result = run(audio)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func load() -> Error? {
        // whisper.cpp schreibt sonst Diagnosetexte auf die Konsole. Wad gibt nichts aus, was es nicht muss.
        whisper_log_set({ _, _, _ in }, nil)
        guard let path = Bundle.main.path(forResource: Self.modelName, ofType: "bin") else {
            return WhisperError.modelMissing
        }
        var params = whisper_context_default_params()
        params.use_gpu = true
        context = whisper_init_from_file_with_params(path, params)
        log.notice("Sprachmodell geladen: \(self.context != nil, privacy: .public)")
        return context == nil ? WhisperError.modelNotLoaded : nil
    }

    private func run(_ audio: AudioBuffer) -> Result<String, Error> {
        guard let context else { return .failure(WhisperError.modelNotLoaded) }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))
        params.no_timestamps = true
        params.print_special = false
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.suppress_nst = true          // keine „[Musik]“- oder „(Lachen)“-Marken im Text

        let status: Int32 = "auto".withCString { language in
            params.language = language       // Sprache wird pro Diktat erkannt
            return audio.withSamples { samples in
                whisper_full(context, params, samples.baseAddress, Int32(samples.count))
            }
        }
        guard status == 0 else { return .failure(WhisperError.failed) }

        let text = (0..<whisper_full_n_segments(context))
            .map { String(cString: whisper_full_get_segment_text(context, $0)) }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .success(text)
    }
}
