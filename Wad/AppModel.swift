// AppModel.swift
// Verbindet Wads Teile: Taste, Aufnahme-Automat, Spracherkennung, Einfügen, Berechtigungen
// und Systemereignisse. Menü und Symbol lesen ihren Zustand nur von hier.

import SwiftUI

final class AppModel: ObservableObject {
    @Published var isEnabled = true {
        didSet { if !isEnabled { dictation.cancel(reason: "Diktieren ausgeschaltet") } }
    }
    @Published var mode = DictationController.Mode.live {
        didSet { dictation.mode = mode }
    }
    /// Schreibt alles klein. Die einzige Einstellung, die Wad sich über einen Neustart hinweg merkt:
    /// ein einzelner Ja/Nein-Wert in macOS' Einstellungsablage, nie ein Text.
    @Published var isLowercase = UserDefaults.standard.bool(forKey: AppModel.lowercaseKey) {
        didSet { UserDefaults.standard.set(isLowercase, forKey: Self.lowercaseKey) }
    }
    private static let lowercaseKey = "Kleinschreibung"
    @Published private(set) var dictationState = DictationController.State.idle
    @Published private(set) var hasMicrophone = Permissions.hasMicrophone
    @Published private(set) var hasAccessibility = Permissions.hasAccessibility
    /// Ob das Sprachmodell bereitsteht. `nil`, solange es noch lädt.
    @Published private(set) var isTranscriberReady: Bool?
    /// Kurzer Hinweis oben im Menü, wenn etwas schiefging. Verschwindet nach einigen Sekunden.
    @Published private(set) var notice: String?
    /// Die beiden Verläufe, nur im Arbeitsspeicher (SPEC 2.4).
    @Published private(set) var dictations = History()
    @Published private(set) var clipboard = History()

    private let hotkey = HotkeyMonitor()
    private let recorder = MicrophoneRecorder()
    private let transcriber: WhisperTranscriber
    private let inserter = TextInserter()
    private let clipboardWatcher = ClipboardWatcher()
    private let dictation: DictationController
    /// Die eine Warteschlange für alles, was die Spracherkennung tut: laden, prüfen, umwandeln.
    private let worker: DispatchQueue
    private var observers: [NSObjectProtocol] = []
    private var accessibilityTimer: Timer?
    private var noticeTimer: Timer?

    init() {
        transcriber = WhisperTranscriber()
        let worker = DispatchQueue(label: "com.linushundt.Wad.transcription", qos: .userInitiated)
        self.worker = worker
        dictation = DictationController(capture: recorder, transcriber: transcriber,
                                        isKeyPhysicallyDown: HotkeyMonitor.isRightOptionDown,
                                        background: { worker.async(execute: $0) })
        dictation.onStateChange = { [weak self] state in self?.dictationState = state }
        dictation.onText = { [weak self] text in
            guard let self else { return }
            inserter.insert(styled(text))
        }
        dictation.onDictationFinished = { [weak self] text in
            guard let self else { return }
            dictations.add(styled(text))
        }
        clipboardWatcher.onCopy = { [weak self] text in self?.clipboard.add(text) }
        clipboardWatcher.start()
        worker.async { [weak self, transcriber] in
            let ready = (try? transcriber.load()) != nil
            DispatchQueue.main.async {
                self?.isTranscriberReady = ready
                if !ready { log.error("Spracherkennung nicht verfügbar") }
            }
        }
        dictation.onNotice = { [weak self] text in self?.show(notice: text) }
        recorder.onDeviceChange = { [weak self] in
            guard self?.dictationState == .recording else { return }
            self?.dictation.cancel(reason: "Audiogerät gewechselt")
            self?.show(notice: "Aufnahme beendet: Mikrofon wurde gewechselt")
        }
        hotkey.onChange = { [weak self] isPressed in self?.keyChanged(isPressed) }

        observers = SystemEvents.observeInterruptions { [weak self] reason in
            self?.dictation.cancel(reason: reason)
        }
        observers.append(Permissions.observeAccessibilityChanges { [weak self] in
            self?.refreshAccessibility()
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            dictation.cancel(reason: "Wad wird beendet")
            // Wartet eine laufende Umwandlung ab und gibt die Modelle dann frei.
            worker.sync { self.transcriber.unload() }
        })

        log.notice("Start, Mikrofon: \(self.hasMicrophone, privacy: .public), Bedienungshilfen: \(self.hasAccessibility, privacy: .public)")
        if hasAccessibility { hotkey.start() } else { waitForAccessibility() }
        askForMissingPermissions()
    }

    private func styled(_ text: String) -> String {
        isLowercase ? text.lowercased(with: .current) : text
    }

    /// Zeigt einen Hinweis oben im Menü und als Ausrufezeichen am Symbol, für acht Sekunden.
    private func show(notice text: String) {
        notice = text
        noticeTimer?.invalidate()
        noticeTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            self?.notice = nil
        }
    }

    /// Legt einen Eintrag aus einem Verlauf wieder in die Zwischenablage.
    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func clearDictations() {
        dictations.clear()
    }

    func clearClipboardHistory() {
        clipboard.clear()
    }

    /// Fragt nacheinander statt gleichzeitig, damit nie zwei Systemdialoge übereinander liegen.
    private func askForMissingPermissions() {
        Permissions.requestMicrophone { [weak self] granted in
            guard let self else { return }
            hasMicrophone = granted
            if !hasAccessibility { Permissions.requestAccessibility() }
        }
    }

    private func keyChanged(_ isPressed: Bool) {
        guard isPressed else {
            dictation.keyReleased()
            return
        }
        guard isEnabled else { return }
        // Das Mikrofon-Recht kann jederzeit in den Systemeinstellungen entzogen werden.
        hasMicrophone = Permissions.hasMicrophone
        guard hasMicrophone else {
            show(notice: "Wad darf das Mikrofon nicht benutzen")
            return
        }
        // Lädt das Modell noch, darf trotzdem diktiert werden: Die Umwandlung wartet einfach dahinter.
        guard isTranscriberReady != false else {
            show(notice: "Spracherkennung nicht verfügbar")
            return
        }
        notice = nil
        dictation.keyPressed()
    }

    /// Solange die Freigabe fehlt, prüft Wad jede Sekunde nach, weil macOS eine neue Freigabe
    /// nicht zuverlässig meldet. Die Abfrage endet, sobald die Freigabe da ist.
    private func waitForAccessibility() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshAccessibility()
        }
    }

    /// Reagiert nur, wenn sich die Freigabe gegenüber dem bekannten Stand geändert hat.
    private func refreshAccessibility() {
        let isTrusted = Permissions.hasAccessibility
        guard isTrusted != hasAccessibility else { return }
        log.notice("Bedienungshilfen geändert: \(isTrusted, privacy: .public)")
        hasAccessibility = isTrusted
        if isTrusted {
            accessibilityTimer?.invalidate()
            // Beobachtet: Tasten-Beobachter liefern erst in einem Prozess Ereignisse, der beim Start
            // schon freigegeben war. Deshalb startet Wad nach der Freigabe einmal selbst neu.
            Permissions.relaunch()
        } else {
            hotkey.stop()
            dictation.cancel(reason: "Bedienungshilfen entzogen")
            waitForAccessibility()
        }
    }
}
