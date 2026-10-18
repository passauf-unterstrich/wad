// DictationController.swift
// Der Zustandsautomat einer Aufnahme: bereit → nimmt auf → verarbeitet → bereit.
// Die einzige Stelle, die das Mikrofon starten darf, und der Sitz aller Absicherungen
// gegen eine weiterlaufende Aufnahme (SPEC 2.2).

import Foundation

/// Alles, was der Automat vom Mikrofon braucht. In Tests steht hier eine Attrappe.
protocol AudioCapture: AnyObject {
    func start() throws
    /// Schaltet das Mikrofon vollständig ab und gibt die Aufnahme heraus.
    func stop() -> AudioBuffer
}

final class DictationController {
    enum State: Equatable {
        case idle, recording, processing
    }

    /// Harte Obergrenze einer Aufnahme. Bewusst eine feste Konstante, keine Einstellung.
    static let maxDuration: TimeInterval = 10 * 60
    /// Takt der Gegenprüfung, ob die Taste wirklich noch gehalten wird: fünfmal pro Sekunde.
    static let safetyCheckInterval: TimeInterval = 0.2

    private(set) var state: State = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var onStateChange: ((State) -> Void)?

    private let capture: AudioCapture
    private let isKeyPhysicallyDown: () -> Bool
    private let now: () -> Date
    private var startedAt: Date?
    private var safetyTimer: Timer?

    /// - Parameters:
    ///   - isKeyPhysicallyDown: fragt direkt beim System nach, ob die Taste gerade unten ist.
    ///   - now: Uhr, in Tests ersetzbar, damit niemand zehn Minuten warten muss.
    init(capture: AudioCapture, isKeyPhysicallyDown: @escaping () -> Bool, now: @escaping () -> Date = Date.init) {
        self.capture = capture
        self.isKeyPhysicallyDown = isKeyPhysicallyDown
        self.now = now
    }

    func keyPressed() {
        guard state == .idle else { return }
        do {
            try capture.start()
        } catch {
            log.error("Mikrofon ließ sich nicht starten: \(error.localizedDescription, privacy: .public)")
            return
        }
        startedAt = now()
        state = .recording
        startSafetyTimer()
    }

    func keyReleased() {
        finish(reason: "Taste losgelassen")
    }

    /// Bricht eine laufende Aufnahme ab und verwirft sie, etwa bei Ruhezustand oder Bildschirmsperre.
    func cancel(reason: String) {
        guard state == .recording else { return }
        stopMicrophone().wipe()
        log.notice("Aufnahme abgebrochen: \(reason, privacy: .public)")
        state = .idle
    }

    /// Die Gegenprüfung. Läuft während der Aufnahme im Takt, in Tests wird sie direkt aufgerufen.
    func checkSafeguards() {
        guard state == .recording, let startedAt else { return }
        if !isKeyPhysicallyDown() {
            finish(reason: "Loslassen verpasst, Gegenprüfung")
        } else if now().timeIntervalSince(startedAt) >= Self.maxDuration {
            finish(reason: "Zeitlimit erreicht")
        }
    }

    private func finish(reason: String) {
        guard state == .recording else { return }
        let audio = stopMicrophone()
        log.notice("Aufnahme beendet: \(reason, privacy: .public)")
        state = .processing
        // Ab Etappe 3 geht `audio` hier an die Spracherkennung. Bis dahin wird es sofort gelöscht.
        audio.wipe()
        state = .idle
    }

    private func stopMicrophone() -> AudioBuffer {
        safetyTimer?.invalidate()
        safetyTimer = nil
        startedAt = nil
        return capture.stop()
    }

    /// Der Takt läuft in allen Run-Loop-Modi, also auch, während ein Menü offen ist.
    private func startSafetyTimer() {
        let timer = Timer(timeInterval: Self.safetyCheckInterval, repeats: true) { [weak self] _ in
            self?.checkSafeguards()
        }
        RunLoop.main.add(timer, forMode: .common)
        safetyTimer = timer
    }
}
