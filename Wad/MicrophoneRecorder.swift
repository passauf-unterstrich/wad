// MicrophoneRecorder.swift
// Nimmt über das Mikrofon auf, solange start() … stop() läuft, und schreibt direkt in einen
// AudioBuffer. Für jede Aufnahme entsteht eine frische Audio-Engine, die stop() vollständig
// abbaut. Damit gibt macOS das Mikrofon sofort frei, und der orange Punkt verschwindet.

import AVFoundation

final class MicrophoneRecorder: AudioCapture {
    enum RecorderError: LocalizedError {
        case noMicrophone, unsupportedFormat

        var errorDescription: String? {
            switch self {
            case .noMicrophone: "Kein Mikrofon verfügbar"
            case .unsupportedFormat: "Audioformat des Mikrofons wird nicht unterstützt"
            }
        }
    }

    /// Wird aufgerufen, wenn sich das Audiogerät während der Aufnahme ändert (z. B. AirPods).
    var onDeviceChange: (() -> Void)?

    private var engine: AVAudioEngine?
    private var buffer: AudioBuffer?
    private var deviceObserver: NSObjectProtocol?

    func start() throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else { throw RecorderError.noMicrophone }

        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioBuffer.sampleRate,
                                         channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.unsupportedFormat
        }

        let buffer = AudioBuffer(maxDuration: DictationController.maxDuration)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { pcm, _ in
            Self.convert(pcm, with: converter, into: buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }

        deviceObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.onDeviceChange?()
        }
        self.engine = engine
        self.buffer = buffer
    }

    func stop() -> AudioBuffer {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            engine.reset()
        }
        engine = nil
        if let deviceObserver { NotificationCenter.default.removeObserver(deviceObserver) }
        deviceObserver = nil
        defer { buffer = nil }
        return buffer ?? AudioBuffer(maxDuration: 0)
    }

    /// Rechnet ein Stück Mikrofon-Audio auf 16 kHz mono um und hängt es an. Läuft auf dem Audio-Thread.
    private static func convert(_ pcm: AVAudioPCMBuffer, with converter: AVAudioConverter, into buffer: AudioBuffer) {
        let ratio = converter.outputFormat.sampleRate / pcm.format.sampleRate
        let capacity = AVAudioFrameCount((Double(pcm.frameLength) * ratio).rounded(.up))
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { return }

        var delivered = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if delivered {
                status.pointee = .noDataNow
                return nil
            }
            delivered = true
            status.pointee = .haveData
            return pcm
        }
        guard error == nil, let samples = output.floatChannelData?[0] else { return }
        buffer.append(UnsafeBufferPointer(start: samples, count: Int(output.frameLength)))
    }
}
