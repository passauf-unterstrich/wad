// AudioBuffer.swift
// Hält eine Aufnahme als 16-kHz-Mono-Samples ausschließlich im Arbeitsspeicher (SPEC 2.3).
// Der Speicher wird einmal für die längstmögliche Aufnahme reserviert und nie vergrößert.
// So entstehen keine verstreuten Kopien, und wipe() erwischt wirklich jedes Sample.

import Foundation

final class AudioBuffer {
    /// Whisper erwartet 16 000 Samples pro Sekunde, einkanalig.
    static let sampleRate: Double = 16_000

    let capacity: Int
    private(set) var count = 0
    private let storage: UnsafeMutablePointer<Float>
    private let lock = NSLock()

    /// macOS stellt so große Bereiche erst bereit, wenn hineingeschrieben wird. Zehn Minuten
    /// Reserve kosten also nur so viel Arbeitsspeicher, wie tatsächlich aufgenommen wurde.
    init(maxDuration: TimeInterval) {
        capacity = Int(maxDuration * Self.sampleRate)
        storage = .allocate(capacity: max(capacity, 1))
    }

    deinit {
        wipe()
        storage.deallocate()
    }

    /// Hängt Samples an. Was über die Kapazität hinausgeht, wird verworfen: Der Puffer kann
    /// physisch nicht mehr als die Höchstdauer fassen. Wird vom Audio-Thread aufgerufen.
    func append(_ samples: UnsafeBufferPointer<Float>) {
        guard let source = samples.baseAddress else { return }
        lock.lock()
        defer { lock.unlock() }
        let n = min(samples.count, capacity - count)
        (storage + count).update(from: source, count: n)
        count += n
    }

    /// Überschreibt alle Samples mit Nullen. `memset_s` darf der Compiler im Gegensatz zu einer
    /// normalen Schleife nicht wegoptimieren. Grenze: Kopien, die Apples Audio-System intern
    /// kurzzeitig hält, liegen außerhalb von Wads Reichweite.
    func wipe() {
        lock.lock()
        defer { lock.unlock() }
        let bytes = count * MemoryLayout<Float>.stride
        _ = memset_s(storage, bytes, 0, bytes)
        count = 0
    }
}
