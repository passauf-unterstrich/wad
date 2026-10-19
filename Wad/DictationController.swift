// DictationController.swift
// Der Zustandsautomat einer Aufnahme: bereit → nimmt auf → verarbeitet → bereit.
// Die einzige Stelle, die das Mikrofon starten darf, der Sitz aller Absicherungen gegen eine
// weiterlaufende Aufnahme (SPEC 2.2) und der Taktgeber des Live-Chunkings (SPEC 1.4).

import Foundation

/// Alles, was der Automat vom Mikrofon braucht. In Tests steht hier eine Attrappe.
protocol AudioCapture: AnyObject {
    /// Startet das Mikrofon und gibt den Puffer zurück, in den es schreibt.
    /// `onAudio` meldet von einem beliebigen Thread, dass neue Samples angekommen sind.
    func start(onAudio: @escaping () -> Void) throws -> AudioBuffer
    /// Schaltet das Mikrofon vollständig ab.
    func stop()
}

final class DictationController {
    enum State: Equatable {
        case idle, recording, processing
    }

    enum Mode: Equatable {
        /// Stücke werden an Sprechpausen eingefügt, während man weiterspricht.
        case live
        /// Alles wird erst nach dem Loslassen umgewandelt und als Ganzes eingefügt.
        case atEnd
    }

    /// Harte Obergrenze einer Aufnahme. Bewusst eine feste Konstante, keine Einstellung.
    static let maxDuration: TimeInterval = 10 * 60
    /// Kürzere Tipper gelten als versehentlich: nichts wird umgewandelt, nichts eingefügt.
    static let minDuration: TimeInterval = 0.3
    /// Takt der Gegenprüfung, ob die Taste wirklich noch gehalten wird: fünfmal pro Sekunde.
    static let safetyCheckInterval: TimeInterval = 0.2

    var mode = Mode.live
    /// Liefert zu Beginn jedes Diktats den Vokabel-Hinweis fürs Modell.
    var vocabularyHint: () -> String? = { nil }
    private(set) var state: State = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var onStateChange: ((State) -> Void)?
    /// Text zum Einfügen: im Live-Modus Stück für Stück, sonst einmal am Ende.
    var onText: ((String) -> Void)?
    /// Der vollständige Text, sobald ein Diktat fertig ist.
    var onDictationFinished: ((String) -> Void)?
    /// Ein kurzer, verständlicher Hinweis, wenn etwas nicht wie erwartet lief.
    var onNotice: ((String) -> Void)?

    private let capture: AudioCapture
    private let transcriber: Transcriber
    private let isKeyPhysicallyDown: () -> Bool
    private let now: () -> Date
    private let background: (@escaping () -> Void) -> Void
    private let main: (@escaping () -> Void) -> Void

    private var session: DictationSession?
    private var startedAt: Date?
    private var safetyTimer: Timer?
    private var nextLiveCheck = 0
    private var isLiveCheckPending = false
    private var keyUpChecks = 0

    /// - Parameters:
    ///   - isKeyPhysicallyDown: fragt direkt beim System nach, ob die Taste gerade unten ist.
    ///   - now: Uhr, in Tests ersetzbar, damit niemand zehn Minuten warten muss.
    ///   - background: führt Arbeit der Spracherkennung aus, nacheinander, nie gleichzeitig.
    ///   - main: kehrt auf den Hauptthread zurück.
    init(capture: AudioCapture, transcriber: Transcriber,
         isKeyPhysicallyDown: @escaping () -> Bool,
         now: @escaping () -> Date = Date.init,
         background: @escaping (@escaping () -> Void) -> Void,
         main: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }) {
        self.capture = capture
        self.transcriber = transcriber
        self.isKeyPhysicallyDown = isKeyPhysicallyDown
        self.now = now
        self.background = background
        self.main = main
    }

    func keyPressed() {
        guard state == .idle else { return }
        let audio: AudioBuffer
        do {
            audio = try capture.start { [weak self] in
                self?.main { self?.audioArrived() }
            }
        } catch {
            log.error("Mikrofon ließ sich nicht starten: \(error.localizedDescription, privacy: .public)")
            onNotice?(error.localizedDescription)
            return
        }
        session = DictationSession(audio: audio, transcriber: transcriber, vocabularyHint: vocabularyHint())
        nextLiveCheck = ChunkPlanner.minChunk
        startedAt = now()
        keyUpChecks = 0
        state = .recording
        startSafetyTimer()
    }

    func keyReleased() {
        finish(reason: "Taste losgelassen")
    }

    /// Bricht ein laufendes Diktat ab und verwirft es, etwa bei Ruhezustand oder Bildschirmsperre.
    func cancel(reason: String) {
        guard state == .recording, let session else { return }
        session.isCancelled = true
        stopMicrophone()
        background { session.discard() }
        log.notice("Aufnahme abgebrochen: \(reason, privacy: .public)")
        state = .idle
    }

    /// Die Gegenprüfung. Läuft während der Aufnahme im Takt, in Tests wird sie direkt aufgerufen.
    func checkSafeguards() {
        guard state == .recording, let startedAt else { return }
        // Erst wenn die Taste zweimal hintereinander oben ist, gilt das Loslassen als verpasst.
        // So beendet ein kurzer Aussetzer (etwa während Wad einfügt) nie ein laufendes Diktat,
        // und eine hängende Aufnahme endet trotzdem nach spätestens 0,4 Sekunden.
        keyUpChecks = isKeyPhysicallyDown() ? 0 : keyUpChecks + 1
        if keyUpChecks >= 2 {
            finish(reason: "Loslassen verpasst, Gegenprüfung")
        } else if now().timeIntervalSince(startedAt) >= Self.maxDuration {
            finish(reason: "Zeitlimit erreicht")
            onNotice?("Aufnahme nach 10 Minuten automatisch beendet")
        }
    }
}
private extension DictationController {
    /// Live-Modus: höchstens einmal pro Sekunde neuen Tons nach einer passenden Pause suchen.
    /// Ausgelöst vom Eintreffen neuer Samples, nicht von einem eigenen Takt.
    func audioArrived() {
        guard state == .recording, mode == .live, !isLiveCheckPending, let session else { return }
        guard session.audio.count >= nextLiveCheck else { return }
        nextLiveCheck = session.audio.count + Int(AudioBuffer.sampleRate)
        isLiveCheckPending = true
        background { [weak self] in
            let text = session.transcribeReadyChunk()
            self?.main {
                self?.isLiveCheckPending = false
                if let text, !session.isCancelled { self?.onText?(text) }
            }
        }
    }

    func finish(reason: String) {
        guard state == .recording, let session, let startedAt else { return }
        let duration = now().timeIntervalSince(startedAt)
        stopMicrophone()
        log.notice("Aufnahme beendet: \(reason, privacy: .public)")
        guard duration >= Self.minDuration else {
            background { session.discard() }
            state = .idle
            return
        }
        state = .processing
        // Die Warteschlange arbeitet der Reihe nach: Ein noch laufendes Live-Stück ist vorher fertig.
        background { [weak self] in
            let text = session.transcribeRemainder()
            let fullText = session.fullText
            session.discard()
            self?.main {
                if let text, !session.isCancelled { self?.onText?(text) }
                if !fullText.isEmpty { self?.onDictationFinished?(fullText) }
                self?.state = .idle
            }
        }
    }

    func stopMicrophone() {
        safetyTimer?.invalidate()
        safetyTimer = nil
        startedAt = nil
        session = nil
        capture.stop()
    }

    /// Der Takt läuft in allen Run-Loop-Modi, also auch, während ein Menü offen ist.
    func startSafetyTimer() {
        let timer = Timer(timeInterval: Self.safetyCheckInterval, repeats: true) { [weak self] _ in
            self?.checkSafeguards()
        }
        RunLoop.main.add(timer, forMode: .common)
        safetyTimer = timer
    }
}
