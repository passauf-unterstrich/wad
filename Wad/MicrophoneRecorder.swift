// MicrophoneRecorder.swift
// Nimmt über das Mikrofon auf, solange start() … stop() läuft, und schreibt direkt in einen
// AudioBuffer, den der Aufnahme-Automat schon während der Aufnahme lesen kann. Für jede
// Aufnahme entsteht eine frische Audio-Engine, die stop() vollständig abbaut. Damit gibt
// macOS das Mikrofon sofort frei, und der orange Punkt verschwindet. Ändert sich mitten in
// der Aufnahme das Audiogerät, läuft die Aufnahme auf dem neuen Gerät weiter.

import AVFoundation

final class MicrophoneRecorder: AudioCapture {
    enum RecorderError: LocalizedError {
        case noMicrophone, unsupportedFormat

        var errorDescription: String? {
            switch self {
            case .noMicrophone: "Kein Mikrofon gefunden"
            case .unsupportedFormat: "Audioformat des Mikrofons wird nicht unterstützt"
            }
        }
    }

    /// Wird aufgerufen, wenn das Mikrofon während der Aufnahme wegfällt und sich auch auf
    /// einem anderen Gerät nicht weiterführen lässt.
    var onMicrophoneLost: (() -> Void)?

    private var engine: AVAudioEngine?
    private var deviceObserver: NSObjectProtocol?
    private var buffer: AudioBuffer?
    private var onAudio: (() -> Void)?

    func start(onAudio: @escaping () -> Void) throws -> AudioBuffer {
        let buffer = AudioBuffer(maxDuration: DictationController.maxDuration)
        self.buffer = buffer
        self.onAudio = onAudio
        do {
            try startEngine()
        } catch {
            self.buffer = nil
            self.onAudio = nil
            throw error
        }
        return buffer
    }

    func stop() {
        stopEngine()
        buffer = nil
        onAudio = nil
    }

    /// Baut eine frische Engine auf dem gerade gültigen Mikrofon auf. Sie schreibt in den Puffer
    /// der laufenden Aufnahme, auch wenn sie mitten in der Aufnahme neu entsteht.
    private func startEngine() throws {
        guard let buffer, let onAudio else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else { throw RecorderError.noMicrophone }

        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioBuffer.sampleRate,
                                         channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.unsupportedFormat
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { pcm, _ in
            Self.convert(pcm, with: converter, into: buffer)
            onAudio()
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
            self?.audioConfigurationChanged()
        }
        self.engine = engine
    }

    private func stopEngine() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            engine.reset()
        }
        engine = nil
        if let deviceObserver { NotificationCenter.default.removeObserver(deviceObserver) }
        deviceObserver = nil
    }

    /// macOS meldet eine geänderte Audio-Konfiguration nicht nur beim Mikrofonwechsel, sondern auch,
    /// wenn sich Lautsprecher, Bluetooth-Geräte oder andere Apps am Ton zu schaffen machen. Die Engine
    /// hält dann an. Bisher endete damit das ganze Diktat. Jetzt baut Wad die Engine sofort neu auf und
    /// schreibt in denselben Puffer weiter: Die Aufnahme läuft weiter, es fehlen höchstens Sekundenbruchteile.
    private func audioConfigurationChanged() {
        guard engine != nil else { return }
        stopEngine()
        do {
            try startEngine()
            log.notice("Audio-Konfiguration geändert, Aufnahme läuft weiter")
        } catch {
            log.error("Mikrofon nach Änderung nicht verfügbar: \(error.localizedDescription, privacy: .public)")
            onMicrophoneLost?()
        }
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
