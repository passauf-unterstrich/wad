// TestDoubles.swift
// Attrappen für Mikrofon und Spracherkennung, damit die Tests ohne echte Hardware laufen.

import Foundation

final class FakeMicrophone: AudioCapture {
    struct StartFailure: Error {}

    var failsToStart = false
    private(set) var isRunning = false
    private(set) var startCount = 0
    private(set) var buffer: AudioBuffer?
    private var onAudio: (() -> Void)?

    func start(onAudio: @escaping () -> Void) throws -> AudioBuffer {
        if failsToStart { throw StartFailure() }
        startCount += 1
        isRunning = true
        self.onAudio = onAudio
        let buffer = AudioBuffer(maxDuration: 60)
        self.buffer = buffer
        return buffer
    }

    func stop() {
        isRunning = false
    }

    /// Simuliert Ton vom Mikrofon. Werte ungleich null zählen für die Attrappe als Sprache.
    func deliver(seconds: Double, speech: Bool) {
        let samples = [Float](repeating: speech ? 0.5 : 0, count: Int(seconds * AudioBuffer.sampleRate))
        samples.withUnsafeBufferPointer { buffer?.append($0) }
        onAudio?()
    }
}

/// Erkennt „Sprache“ an Samples ungleich null und liefert pro Stück einen nummerierten Text.
final class FakeTranscriber: Transcriber {
    private(set) var chunkLengths: [Int] = []
    private(set) var prompts: [String?] = []
    private(set) var languages: [String?] = []

    func speechSegments(in samples: UnsafeBufferPointer<Float>) -> [Range<Int>] {
        var segments: [Range<Int>] = []
        var start: Int?
        for (i, sample) in samples.enumerated() {
            if sample != 0, start == nil { start = i }
            if sample == 0, let s = start { segments.append(s..<i); start = nil }
        }
        if let s = start { segments.append(s..<samples.count) }
        return segments
    }

    func transcribe(_ samples: UnsafeBufferPointer<Float>, language: String?, prompt: String?) throws -> Transcription {
        chunkLengths.append(samples.count)
        prompts.append(prompt)
        languages.append(language)
        return Transcription(text: "Stück \(chunkLengths.count)", language: "de")
    }
}
