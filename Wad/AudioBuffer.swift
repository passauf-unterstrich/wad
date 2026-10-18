// AudioBuffer.swift
// Hält eine Aufnahme als 16-kHz-Mono-Samples ausschließlich im Arbeitsspeicher (SPEC 2.3).
// Der Speicher wird einmal für die längstmögliche Aufnahme reserviert und nie vergrößert.
// So entstehen keine verstreuten Kopien, und wipe() erwischt wirklich jedes Sample.
//
// Gleichzeitigkeit: Das Mikrofon hängt hinten an, während vorne schon umgewandelt wird.
// Einmal geschriebene Samples ändern sich nie mehr, deshalb schützt die Sperre nur `count`,
// und Lesen blockiert die Aufnahme nie, auch nicht während einer langen Umwandlung.

import Foundation

final class AudioBuffer {
    /// Whisper erwartet 16 000 Samples pro Sekunde, einkanalig.
    static let sampleRate: Double = 16_000

    let capacity: Int
    private let storage: UnsafeMutablePointer<Float>
    private let lock = NSLock()
    private var storedCount = 0

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

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCount
    }

    /// Hängt Samples an. Was über die Kapazität hinausgeht, wird verworfen: Der Puffer kann
    /// physisch nicht mehr als die Höchstdauer fassen. Wird vom Audio-Thread aufgerufen.
    func append(_ samples: UnsafeBufferPointer<Float>) {
        guard let source = samples.baseAddress else { return }
        lock.lock()
        defer { lock.unlock() }
        let n = min(samples.count, capacity - storedCount)
        (storage + storedCount).update(from: source, count: n)
        storedCount += n
    }

    /// Gibt die Samples ab `start` bis zum aktuellen Ende zum Lesen frei, ohne sie zu kopieren.
    func withSamples<T>(from start: Int = 0, _ body: (UnsafeBufferPointer<Float>) -> T) -> T {
        let end = count
        let start = min(start, end)
        return body(UnsafeBufferPointer(start: storage + start, count: end - start))
    }

    /// Überschreibt einen bereits umgewandelten Bereich mit Nullen.
    func wipe(range: Range<Int>) {
        let range = range.clamped(to: 0..<count)
        let bytes = range.count * MemoryLayout<Float>.stride
        _ = memset_s(storage + range.lowerBound, bytes, 0, bytes)
    }

    /// Überschreibt alle Samples mit Nullen. `memset_s` darf der Compiler im Gegensatz zu einer
    /// normalen Schleife nicht wegoptimieren. Grenze: Kopien, die Apples Audio-System intern
    /// kurzzeitig hält, liegen außerhalb von Wads Reichweite.
    func wipe() {
        lock.lock()
        defer { lock.unlock() }
        let bytes = storedCount * MemoryLayout<Float>.stride
        _ = memset_s(storage, bytes, 0, bytes)
        storedCount = 0
    }
}
