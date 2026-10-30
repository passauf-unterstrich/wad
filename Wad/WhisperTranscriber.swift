// WhisperTranscriber.swift
// Spracherkennung mit whisper.cpp (SPEC 1.5): das Modell large-v3-turbo für den Text und
// Silero VAD, um Sprache von Stille zu unterscheiden. Beide sind in Wad.app eingebaut und
// laufen vollständig lokal. Alle Aufrufe kommen nacheinander von Wads Hintergrund-Warteschlange.

import Foundation

final class WhisperTranscriber: Transcriber {
    enum WhisperError: LocalizedError {
        case modelMissing, modelNotLoaded, failed

        var errorDescription: String? {
            switch self {
            case .modelMissing: L10n.t("error.modelMissing")
            case .modelNotLoaded: L10n.t("error.modelNotLoaded")
            case .failed: L10n.t("error.recognitionFailed")
            }
        }
    }

    private var context: OpaquePointer?
    private var vad: OpaquePointer?

    /// Lädt beide Modelle (rund eine Sekunde, beim allerersten Start länger).
    func load() throws {
        // whisper.cpp schreibt sonst Diagnosetexte auf die Konsole. Wad gibt nichts aus, was es nicht muss.
        whisper_log_set({ _, _, _ in }, nil)
        guard let modelPath = Bundle.main.path(forResource: "ggml-large-v3-turbo-q5_0", ofType: "bin"),
              let vadPath = Bundle.main.path(forResource: "ggml-silero-v6.2.0", ofType: "bin") else {
            throw WhisperError.modelMissing
        }
        var params = whisper_context_default_params()
        params.use_gpu = true
        context = whisper_init_from_file_with_params(modelPath, params)

        var vadParams = whisper_vad_default_context_params()
        vadParams.use_gpu = false            // Silero ist winzig, der Prozessor ist dafür schneller
        vadParams.n_threads = 2
        vad = whisper_vad_init_from_file_with_params(vadPath, vadParams)

        log.notice("Sprachmodelle geladen: \(self.context != nil && self.vad != nil, privacy: .public)")
        guard context != nil, vad != nil else { throw WhisperError.modelNotLoaded }
    }

    /// Gibt beide Modelle frei. Muss vor dem Beenden passieren: Der Metal-Teil von whisper.cpp
    /// stürzt sonst beim Aufräumen des Prozesses ab.
    func unload() {
        if let context { whisper_free(context) }
        if let vad { whisper_vad_free(vad) }
        context = nil
        vad = nil
    }

    func speechSegments(in samples: UnsafeBufferPointer<Float>) -> [Range<Int>] {
        guard let vad, let base = samples.baseAddress, !samples.isEmpty else { return [] }
        var params = whisper_vad_default_params()
        params.min_silence_duration_ms = Int32(Double(ChunkPlanner.minPause) / AudioBuffer.sampleRate * 1000)
        guard let segments = whisper_vad_segments_from_samples(vad, params, base, Int32(samples.count)) else {
            return []
        }
        defer { whisper_vad_free_segments(segments) }

        // whisper.cpp liefert Hundertstelsekunden, also 160 Samples je Einheit.
        let samplesPerUnit = AudioBuffer.sampleRate / 100
        return (0..<whisper_vad_segments_n_segments(segments)).compactMap { i in
            let start = Int(Double(whisper_vad_segments_get_segment_t0(segments, i)) * samplesPerUnit)
            let end = min(Int(Double(whisper_vad_segments_get_segment_t1(segments, i)) * samplesPerUnit), samples.count)
            return start < end ? start..<end : nil
        }
    }

    func transcribe(_ samples: UnsafeBufferPointer<Float>, language: String?, prompt: String?) throws -> Transcription {
        guard let context else { throw WhisperError.modelNotLoaded }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))
        params.no_timestamps = true
        params.print_special = false
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.suppress_nst = true          // keine „[Musik]“- oder „(Lachen)“-Marken im Text

        let status = (language ?? "auto").withCString { languagePointer in
            (prompt ?? "").withCString { promptPointer in
                params.language = languagePointer
                params.initial_prompt = prompt == nil ? nil : promptPointer
                return whisper_full(context, params, samples.baseAddress, Int32(samples.count))
            }
        }
        guard status == 0 else { throw WhisperError.failed }

        let text = (0..<whisper_full_n_segments(context))
            .map { String(cString: whisper_full_get_segment_text(context, $0)) }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let detected = String(cString: whisper_lang_str(whisper_full_lang_id(context)))
        return Transcription(text: text, language: detected)
    }
}
