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
    /// Höchstdauer beim freien Diktieren über das Menü. Einstellbar, nie länger als `maxDuration`.
    var handsFreeLimit: TimeInterval = 5 * 60
    /// Läuft gerade eine frei gestartete Aufnahme, die nicht an der gehaltenen Taste hängt?
    private(set) var isHandsFree = false
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
    /// Ein kurzer, verständlicher Hinweis, wenn eine Aufnahme anders endete als gewollt.
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
        // Beim freien Diktieren beendet ein kurzer Druck auf die Taste die Aufnahme.
        if isHandsFree {
            finish(reason: "Freies Diktieren beendet")
            return
        }
        startRecording(handsFree: false)
    }

    /// Freies Diktieren über das Menü: nimmt auf, bis „Aufnahme stoppen“, die Taste oder die Höchstdauer es beendet.
    func startHandsFree() {
        startRecording(handsFree: true)
    }

    func stopHandsFree() {
        guard isHandsFree else { return }
        finish(reason: "Freies Diktieren beendet")
    }

    /// Eine neue Aufnahme darf auch starten, während die vorige noch umgewandelt wird. Die
    /// Warteschlange arbeitet der Reihe nach, also kommt der ältere Text immer zuerst an.
    private func startRecording(handsFree: Bool) {
        guard state != .recording else { return }
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
        isHandsFree = handsFree
        state = .recording
        startSafetyTimer()
    }

    /// Ein Loslassen zählt nur, wenn das System die Taste auch wirklich oben sieht. Andere Programme
    /// können Sondertasten-Signale senden; ein solches falsches „losgelassen“ beendet nichts mehr.
    /// War es echt, beendet spätestens die Gegenprüfung die Aufnahme kurz danach.
    func keyReleased() {
        guard !isHandsFree, state == .recording else { return }
        guard !isKeyPhysicallyDown() else {
            log.notice("Loslassen gemeldet, Taste aber noch unten: Aufnahme läuft weiter")
            return
        }
        finish(reason: "Taste losgelassen")
    }

    /// Beendet die Aufnahme, obwohl der Nutzer weiterreden wollte, etwa weil das Mikrofon wegfiel.
    /// Das bis dahin Gesagte wird trotzdem eingefügt, und der Nutzer erfährt, warum es endete.
    func stopUnexpectedly(reason: String) {
        guard state == .recording else { return }
        finish(reason: reason)
        onNotice?("Aufnahme gestoppt: \(reason)")
    }

    /// Bricht ein laufendes Diktat ab und verwirft es, etwa bei Ruhezustand oder Bildschirmsperre.
    /// Mit `notify` erfährt der Nutzer davon; still bleibt es nur, wenn er es selbst ausgelöst hat.
    func cancel(reason: String, notify: Bool = false) {
        guard state == .recording, let session else { return }
        if notify { onNotice?("Aufnahme abgebrochen: \(reason)") }
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
        // Beim freien Diktieren hängt nichts an der Taste, dort zählt nur die Höchstdauer.
        keyUpChecks = isHandsFree || isKeyPhysicallyDown() ? 0 : keyUpChecks + 1
        let limit = isHandsFree ? min(handsFreeLimit, Self.maxDuration) : Self.maxDuration
        if keyUpChecks >= 2 {
            finish(reason: "Loslassen verpasst, Gegenprüfung")
        } else if now().timeIntervalSince(startedAt) >= limit {
            finish(reason: "Zeitlimit erreicht")
            onNotice?("Aufnahme nach \(Int(limit / 60)) Minuten automatisch beendet, Text ist eingefügt")
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
                // Läuft inzwischen schon die nächste Aufnahme, bleibt es bei „nimmt auf“.
                if self?.state == .processing { self?.state = .idle }
            }
        }
    }

    func stopMicrophone() {
        safetyTimer?.invalidate()
        safetyTimer = nil
        startedAt = nil
        isHandsFree = false
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
