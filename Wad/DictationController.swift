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
    /// Doppeltipp: Der zweite Druck muss so kurz nach dem Loslassen des ersten Tipps kommen.
    static let doubleTapWindow: TimeInterval = 0.4
    /// Ein Tipp beendet freies Diktieren erst, wenn es so lange läuft. Sonst stoppte ein dritter Tipp gleich wieder.
    static let minHandsFreeBeforeStop: TimeInterval = 0.5
    /// So lange nach dem Ende eines freien Diktats startet ein Doppeltipp kein neues.
    static let doubleTapPause: TimeInterval = 1

    /// Gilt ab der nächsten Aufnahme, eine laufende behält ihren Modus.
    var mode = Mode.live
    /// Sprache fürs Modell, z. B. „de“. `nil` erkennt sie zu Beginn jedes Diktats selbst (SPEC 1.5).
    /// Gilt wie `mode` ab der nächsten Aufnahme.
    var language: String?
    /// Liefert im Live-Modus zusätzlich vorläufigen Text fürs Vorschau-Fenster (SPEC 1.10).
    /// Gilt ab der nächsten Aufnahme.
    var deliversDrafts = false
    /// Abstand der Probeläufe für den vorläufigen Text, in Sekunden neuen Tons.
    static let draftInterval = 1.5
    /// Zählt die Aufnahmen. Jede Rückmeldung nennt die Nummer ihres Diktats, denn das vorige kann
    /// noch fertig werden, während schon das nächste aufgenommen wird.
    private(set) var dictationNumber = 0
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
    var onText: ((_ text: String, _ dictation: Int) -> Void)?
    /// Vorläufiger Text des noch offenen Teils. Wird vom nächsten fertigen Stück abgelöst.
    var onDraft: ((_ draft: String, _ dictation: Int) -> Void)?
    /// Der vollständige Text, sobald ein Diktat fertig ist. `isDelivered` ist falsch, wenn das
    /// Diktat nicht weitergegeben werden soll, etwa weil der Bildschirm gesperrt wurde.
    var onDictationFinished: ((_ text: String, _ isDelivered: Bool, _ dictation: Int) -> Void)?
    /// Ein kurzer, verständlicher Hinweis, wenn eine Aufnahme anders endete als gewollt.
    var onNotice: ((String) -> Void)?
    /// Sagt im Hinweis, wo ein nicht eingefügtes Diktat geblieben ist. Ist „Letzte Diktate“ aus, bleibt es nirgends.
    var undeliveredNote = "Der Text liegt unter „Letzte Diktate“."

    private let capture: AudioCapture
    private let transcriber: Transcriber
    private let isKeyPhysicallyDown: () -> Bool
    private let now: () -> Date
    private let background: (@escaping () -> Void) -> Void
    private let main: (@escaping () -> Void) -> Void

    private var session: DictationSession?
    private var isLive = true
    private var isDrafting = false
    private var nextDraft = 0
    private var startedAt: Date?
    private var safetyTimer: Timer?
    private var nextLiveCheck = 0
    private var isLiveCheckPending = false
    private var keyUpChecks = 0
    /// Wann zuletzt ein Tipp losgelassen wurde, der als erste Hälfte eines Doppeltipps zählen kann.
    private var lastTapEnd: Date?
    /// Wann zuletzt ein freies Diktat endete, egal wodurch.
    private var handsFreeEndedAt: Date?

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

    /// - Parameter isAlone: Seit dem letzten Loslassen wurde keine andere Taste gedrückt und keine
    ///   andere Sondertaste gehalten. Nur dann kann dieser Druck die zweite Hälfte eines Doppeltipps sein.
    func keyPressed(isAlone: Bool = false) {
        // Beim freien Diktieren beendet ein kurzer Druck auf die Taste die Aufnahme,
        // aber erst nach einer halben Sekunde, damit ein dritter Tipp sie nicht gleich wieder stoppt.
        if isHandsFree {
            guard let startedAt, now().timeIntervalSince(startedAt) >= Self.minHandsFreeBeforeStop else {
                log.notice("Tipp direkt nach dem Start des freien Diktierens übergangen")
                return
            }
            finish(reason: "Freies Diktieren beendet")
            return
        }
        // Doppeltipp: Der erste Tipp hat eine zu kurze Aufnahme gestartet, die schon still verworfen ist.
        // Der zweite Druck startet freies Diktieren, sein Loslassen beendet es nicht.
        let tapEnd = lastTapEnd
        lastTapEnd = nil
        if isAlone, state != .recording, let tapEnd, now().timeIntervalSince(tapEnd) < Self.doubleTapWindow,
           handsFreeEndedAt.map({ now().timeIntervalSince($0) >= Self.doubleTapPause }) ?? true {
            log.notice("Doppeltipp: freies Diktieren")
            startRecording(handsFree: true)
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
        session = DictationSession(audio: audio, transcriber: transcriber, language: language,
                                   vocabularyHint: vocabularyHint())
        // Freies Diktieren läuft immer wie „Zwischenablage mit Vorschau“: live und mit grauem Entwurf,
        // egal welcher Modus eingestellt ist. Die Einstellung selbst bleibt dabei unverändert.
        isLive = handsFree || mode == .live
        isDrafting = isLive && (deliversDrafts || handsFree)
        nextDraft = Int(Self.draftInterval * AudioBuffer.sampleRate)
        dictationNumber += 1
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
    /// - Parameter isAlone: Zwischen Drücken und Loslassen kam keine andere Taste oder Sondertaste dazu.
    ///   Nur dann kann ein zu kurzer Druck die erste Hälfte eines Doppeltipps sein.
    func keyReleased(isAlone: Bool = false) {
        guard !isHandsFree, state == .recording, let startedAt else { return }
        guard !isKeyPhysicallyDown() else {
            log.notice("Loslassen gemeldet, Taste aber noch unten: Aufnahme läuft weiter")
            return
        }
        // Zu kurz zum Diktieren: `finish` verwirft die Aufnahme still, ohne Hinweis und ohne Ton.
        let isTap = isAlone && now().timeIntervalSince(startedAt) < Self.minDuration
        finish(reason: "Taste losgelassen")
        lastTapEnd = isTap ? now() : nil
    }

    /// Beendet die Aufnahme, obwohl der Nutzer weiterreden wollte, etwa weil das Mikrofon wegfiel
    /// oder der Bildschirm gesperrt wurde. Nichts Gesagtes geht verloren: Mit `insert` wird der Rest
    /// eingefügt. Ohne, etwa auf dem Sperrbildschirm, wo Einfügen nichts Gutes bewirkt, landet das
    /// ganze Diktat nur unter „Letzte Diktate“. Der Nutzer erfährt in jedem Fall, warum es endete.
    /// - Parameter reason: Satzteil, z. B. „weil der Bildschirm gesperrt wurde“.
    func stopUnexpectedly(reason: String, insert: Bool = true) {
        guard state == .recording, let session else { return }
        if !insert { session.isCancelled = true }
        finish(reason: reason)
        onNotice?(insert ? "Aufnahme gestoppt, \(reason)" : "Aufnahme gestoppt, \(reason). \(undeliveredNote)")
    }

    /// Bricht ein laufendes Diktat ab und verwirft es. Nur für Fälle, die der Nutzer selbst
    /// ausgelöst hat: Diktieren ausgeschaltet, Fenster-Kürzel, Wad beendet.
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
    /// Live-Modus: höchstens einmal pro Sekunde neuen Tons nach einer passenden Pause suchen,
    /// mit Vorschau zusätzlich alle 1,5 Sekunden einen Probelauf für den vorläufigen Text.
    /// Ausgelöst vom Eintreffen neuer Samples, nicht von einem eigenen Takt. Ist die Spracherkennung
    /// noch beschäftigt, fällt die Runde aus, damit fertiger Text nie auf einen Probelauf wartet.
    func audioArrived() {
        guard state == .recording, isLive, !isLiveCheckPending, let session else { return }
        let count = session.audio.count
        let wantsChunk = count >= nextLiveCheck
        let wantsDraft = isDrafting && count >= nextDraft
        guard wantsChunk || wantsDraft else { return }
        if wantsChunk { nextLiveCheck = count + Int(AudioBuffer.sampleRate) }
        if wantsDraft { nextDraft = count + Int(Self.draftInterval * AudioBuffer.sampleRate) }
        isLiveCheckPending = true
        let number = dictationNumber
        background { [weak self] in
            let text = wantsChunk ? session.transcribeReadyChunk() : nil
            // Gerade wurde ein Stück fertig: Der offene Rest ist frisch, ein Probelauf lohnt erst später.
            let draft = wantsDraft && text == nil ? session.transcribeDraft() : nil
            self?.main {
                self?.isLiveCheckPending = false
                guard !session.isCancelled else { return }
                if let text { self?.onText?(text, number) }
                if let draft { self?.onDraft?(draft, number) }
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
        let number = dictationNumber
        // Die Warteschlange arbeitet der Reihe nach: Ein noch laufendes Live-Stück ist vorher fertig.
        background { [weak self] in
            let text = session.transcribeRemainder()
            let fullText = session.fullText
            session.discard()
            self?.main {
                if let text, !session.isCancelled { self?.onText?(text, number) }
                if !fullText.isEmpty { self?.onDictationFinished?(fullText, !session.isCancelled, number) }
                // Läuft inzwischen schon die nächste Aufnahme, bleibt es bei „nimmt auf“.
                if self?.state == .processing { self?.state = .idle }
            }
        }
    }

    func stopMicrophone() {
        safetyTimer?.invalidate()
        safetyTimer = nil
        startedAt = nil
        if isHandsFree { handsFreeEndedAt = now() }
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
