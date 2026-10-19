// AppModel.swift
// Verbindet Wads Teile: Taste, Aufnahme-Automat, Spracherkennung, Einfügen, Berechtigungen
// und Systemereignisse. Menü und Symbol lesen ihren Zustand nur von hier.

import Carbon.HIToolbox
import ServiceManagement
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
    /// Fenstermanager an oder aus. Gemerkt wird das vom Fenstermanager selbst.
    @Published var isWindowManagerEnabled = false {
        didSet { windowManager.isEnabled = isWindowManagerEnabled }
    }
    /// Startet Wad bei der Anmeldung, über Apples eigene Anmeldeobjekte (Systemeinstellungen → Allgemein).
    @Published var launchesAtLogin = SMAppService.mainApp.status == .enabled {
        didSet { updateLoginItem() }
    }
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
    private let vocabulary = VocabularyStore()
    private let correctionPanel = CorrectionPanel()
    private let hotKeys = HotKeyCenter()
    let windowManager: WindowManager
    private let shortcutsPanel = ShortcutsPanel()
    private let dictation: DictationController
    /// Die eine Warteschlange für alles, was die Spracherkennung tut: laden, prüfen, umwandeln.
    private let worker: DispatchQueue
    private var observers: [NSObjectProtocol] = []
    private var accessibilityTimer: Timer?
    private var noticeTimer: Timer?

    init() {
        transcriber = WhisperTranscriber()
        windowManager = WindowManager(hotKeys: hotKeys)
        let worker = DispatchQueue(label: "com.linushundt.Wad.transcription", qos: .userInitiated)
        self.worker = worker
        dictation = DictationController(capture: recorder, transcriber: transcriber,
                                        isKeyPhysicallyDown: HotkeyMonitor.isRightOptionDown,
                                        background: { worker.async(execute: $0) })
        dictation.onStateChange = { [weak self] state in self?.dictationState = state }
        dictation.vocabularyHint = { [weak self] in self?.vocabulary.vocabulary.hint }
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
        hotKeys.register(KeyCombo(keyCode: UInt32(kVK_ANSI_W), modifiers: UInt32(controlKey | optionKey))) { [weak self] in
            self?.openCorrection()
        }
        isWindowManagerEnabled = windowManager.isEnabled
        enableLoginItemOnFirstLaunch()
        // Erst nach dem Start, damit die Menüleiste schon steht, wenn ein Dialog erscheint.
        DispatchQueue.main.async { OldVersionCleanup.runIfNeeded() }
        // ⌥⇧-Kürzel lösen auch mit der rechten Option-Taste aus. Eine dabei gestartete Aufnahme
        // ist ein Versehen und wird verworfen, ohne etwas einzufügen (SPEC 1.8).
        windowManager.willPerform = { [weak self] in self?.dictation.cancel(reason: "Fenster-Kürzel") }

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

    /// Erst die Vokabeln, dann die Kleinschreibung: So gewinnt die Kleinschreibung immer.
    private func styled(_ text: String) -> String {
        let corrected = vocabulary.vocabulary.apply(to: text)
        return isLowercase ? corrected.lowercased(with: .current) : corrected
    }

    /// Öffnet das Korrektur-Fenster mit dem markierten Text der vorderen App.
    func openCorrection() {
        let selection = SelectedText.current()
        clipboardWatcher.skipCurrentChange()   // Wads kurze Kopie gehört nicht in den Verlauf
        correctionPanel.show(wrong: selection ?? "") { [weak self] entry, permanently in
            self?.vocabulary.add(entry, permanently: permanently)
        }
    }

    func openShortcutsPanel() {
        shortcutsPanel.show(manager: windowManager)
    }

    /// Standard: Wad startet bei der Anmeldung (Linus' Entscheidung vom 19.10.2026). Eingerichtet wird
    /// das genau einmal, und nur, wenn Wad im Programme-Ordner liegt. Aus der DMG oder einem
    /// Testordner heraus würde macOS sich sonst den falschen Ort merken. Wer es abschaltet, bleibt dabei.
    private func enableLoginItemOnFirstLaunch() {
        let key = "Anmeldeobjekt eingerichtet"
        guard !UserDefaults.standard.bool(forKey: key),
              Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        UserDefaults.standard.set(true, forKey: key)
        launchesAtLogin = true
    }

    /// Meldet Wad bei macOS als Anmeldeobjekt an oder ab. macOS startet Wad dann selbst nach der
    /// Anmeldung, genau einmal, wie jede andere App in dieser Liste. Kein eigener Hilfsprozess.
    private func updateLoginItem() {
        let service = SMAppService.mainApp
        do {
            if launchesAtLogin, service.status != .enabled {
                try service.register()
            } else if !launchesAtLogin, service.status == .enabled {
                try service.unregister()
            }
        } catch {
            log.error("Anmeldeobjekt: \(error.localizedDescription, privacy: .public)")
            show(notice: "Start bei Anmeldung ließ sich nicht ändern")
        }
        if service.status == .requiresApproval {
            show(notice: "Bitte Wad in den Anmeldeobjekten erlauben")
            SMAppService.openSystemSettingsLoginItems()
        }
        let enabled = service.status == .enabled
        if launchesAtLogin != enabled { launchesAtLogin = enabled }
    }

    /// Zeigt die Vokabelliste im Finder, markiert, damit man sie sofort öffnen oder weitergeben kann.
    func revealVocabularyFile() {
        vocabulary.createFileIfNeeded()
        NSWorkspace.shared.activateFileViewerSelecting([vocabulary.fileURL])
    }

    /// Legt einen fertigen Auftrag für ChatGPT, Claude & Co. in die Zwischenablage.
    func copyVocabularyPrompt() {
        copyToClipboard(Self.vocabularyPrompt)
        show(notice: "Vorlage kopiert, jetzt in deine KI einfügen")
    }

    private static let vocabularyPrompt = """
    Ich diktiere mit der App Wad. Sie erkennt Fachbegriffe und Namen besser, wenn sie eine \
    Vokabelliste hat. Erstelle mir bitte eine Liste mit den 40 wichtigsten Begriffen, die ich \
    beim Diktieren brauche.

    Über mich: [hier kurz beschreiben, z. B. Beruf, Hobbys, Namen von Familie und Freunden]

    Regeln für die Liste:
    - eine Zeile pro Begriff, genau in der richtigen Schreibweise
    - keine Nummerierung, keine Erklärungen, keine Überschrift
    - wird ein Begriff beim Diktieren oft falsch geschrieben, die Zeile so: Falsch -> Richtig
    """

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
