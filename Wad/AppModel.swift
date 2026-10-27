// AppModel.swift
// Verbindet Wads Teile: Taste, Aufnahme-Automat, Spracherkennung, Einfügen, Berechtigungen
// und Systemereignisse. Menü und Symbol lesen ihren Zustand nur von hier.

import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

/// Die vier Einfügemodi im Menü (SPEC 1.3). Der Rohwert ist, was Wad sich merkt.
enum InsertMode: String {
    /// Stücke werden an Sprechpausen eingefügt, während man weiterspricht.
    case whileDictating
    /// Alles wird nach dem Loslassen als Ganzes eingefügt.
    case afterDictating
    /// Nichts wird eingefügt, der Text bleibt in der Zwischenablage.
    case clipboard
    /// Wie `clipboard`, dazu eine Vorschau, die live mitläuft.
    case clipboardPreview

    var pastes: Bool { self == .whileDictating || self == .afterDictating }
    var isLive: Bool { self == .whileDictating || self == .clipboardPreview }
}

final class AppModel: ObservableObject {
    @Published var isEnabled = true {
        didSet {
            guard !isEnabled else { return }
            dictation.cancel(reason: "Diktieren ausgeschaltet")
            preview.close()
        }
    }
    /// Wohin der Text geht (SPEC 1.3). Gemerkt pro macOS-Benutzer, gilt ab dem nächsten Diktat.
    @Published var insertMode = UserDefaults.standard.string(forKey: AppModel.insertModeKey)
        .flatMap(InsertMode.init) ?? .whileDictating {
        didSet {
            UserDefaults.standard.set(insertMode.rawValue, forKey: Self.insertModeKey)
            applyInsertMode()
            if insertMode != .clipboardPreview { preview.close() }
        }
    }
    private static let insertModeKey = "Einfügen"
    /// Sprache fürs Modell (SPEC 1.5), als Kürzel wie „de“. „auto“ heißt sprachoffen.
    /// Gemerkt pro macOS-Benutzer, gilt ab dem nächsten Diktat.
    @Published var language = UserDefaults.standard.string(forKey: AppModel.languageKey)
        .flatMap { code in AppModel.languages.contains { $0.code == code } ? code : nil } ?? "de" {
        didSet {
            UserDefaults.standard.set(language, forKey: Self.languageKey)
            dictation.language = language == "auto" ? nil : language
        }
    }
    private static let languageKey = "Sprache"
    static let languages = [(code: "de", name: "Deutsch"), (code: "en", name: "Englisch"),
                            (code: "fr", name: "Französisch"), (code: "es", name: "Spanisch")]
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
    /// Höchstdauer fürs freie Diktieren in Minuten, gemerkt wie die anderen Schalter.
    @Published var handsFreeMinutes = UserDefaults.standard.object(forKey: AppModel.handsFreeKey) as? Int ?? 5 {
        didSet {
            UserDefaults.standard.set(handsFreeMinutes, forKey: Self.handsFreeKey)
            dictation.handsFreeLimit = TimeInterval(handsFreeMinutes * 60)
        }
    }
    private static let handsFreeKey = "Höchstdauer freies Diktieren"
    @Published private(set) var dictationState = DictationController.State.idle
    @Published private(set) var isHandsFreeRecording = false
    @Published private(set) var hasMicrophone = Permissions.hasMicrophone
    @Published private(set) var hasAccessibility = Permissions.hasAccessibility
    /// Ob das Sprachmodell bereitsteht. `nil`, solange es noch lädt.
    @Published private(set) var isTranscriberReady: Bool?
    /// Kurzer Hinweis oben im Menü, wenn etwas schiefging. Verschwindet nach einigen Sekunden.
    @Published private(set) var notice: String?
    /// Die beiden Verläufe, nur im Arbeitsspeicher (SPEC 2.4).
    @Published private(set) var dictations = History()
    @Published private(set) var clipboard = History()
    /// Automatisch nach Updates suchen (SPEC 1.9). Standard aus, Wad weist einmal darauf hin.
    @Published var checksForUpdates = false {
        didSet { updates.isEnabled = checksForUpdates }
    }
    /// Eine neuere Version, oben im Menü angeboten. Nicht gemerkt, die nächste Prüfung findet sie wieder.
    @Published private(set) var availableUpdate: Release?

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
    private let preview = PreviewPanel()
    private let updates = UpdateChecker()
    private let updateWindows = UpdateWindows()
    /// Ob nach diesem Start „Was ist neu“ kommt. Entschieden ganz am Anfang, bevor Wad Einstellungen anlegt.
    private let showsWhatsNew: Bool
    private static let lastSeenKey = "Zuletzt gestartete Version"
    /// Einstellungen, die nur eine frühere Version angelegt haben kann. Version 1.0.x merkte sich noch keine Versionsnummer.
    private static let earlierVersionKeys = ["Alte Version geprüft", "Anmeldeobjekt eingerichtet",
                                             "Kleinschreibung", "Höchstdauer freies Diktieren"]
    private let dictation: DictationController
    /// Die eine Warteschlange für alles, was die Spracherkennung tut: laden, prüfen, umwandeln.
    private let worker: DispatchQueue
    private var observers: [NSObjectProtocol] = []
    private var accessibilityTimer: Timer?
    private var noticeTimer: Timer?
    /// Hält Bildschirm und Mac wach, solange aufgenommen wird (siehe `keepAwake`).
    private var awakeActivity: NSObjectProtocol?
    /// Der Einfügemodus der laufenden oder zuletzt begonnenen Aufnahme. Ein Wechsel im Menü
    /// während eines Diktats ändert so nicht mittendrin, wohin dessen Text geht.
    private var deliveryMode = InsertMode.whileDictating

    init() {
        let lastSeen = UserDefaults.standard.string(forKey: Self.lastSeenKey).flatMap(AppVersion.init)
        let hadEarlierVersion = Self.earlierVersionKeys.contains { UserDefaults.standard.object(forKey: $0) != nil }
        showsWhatsNew = UpdateRules.showsWhatsNew(current: UpdateChecker.current, lastSeen: lastSeen,
                                                  hadEarlierVersion: hadEarlierVersion)
        // Nach einem Update merkt Wad sich die Version erst, wenn „Was ist neu“ wirklich zu sehen war.
        if !showsWhatsNew { UserDefaults.standard.set(UpdateChecker.current.description, forKey: Self.lastSeenKey) }
        transcriber = WhisperTranscriber()
        windowManager = WindowManager(hotKeys: hotKeys)
        let worker = DispatchQueue(label: "com.linushundt.Wad.transcription", qos: .userInitiated)
        self.worker = worker
        dictation = DictationController(capture: recorder, transcriber: transcriber,
                                        isKeyPhysicallyDown: HotkeyMonitor.isRightOptionDown,
                                        background: { worker.async(execute: $0) })
        dictation.onStateChange = { [weak self] state in
            guard let self else { return }
            if state == .recording {
                // Freies Diktieren immer mit Vorschau, ohne die Einstellung zu ändern (SPEC 1.3).
                // `isHandsFree` steht schon fest, bevor der Zustand auf „Aufnahme“ wechselt.
                deliveryMode = dictation.isHandsFree ? .clipboardPreview : insertMode
                if deliveryMode == .clipboardPreview { preview.begin(dictation: dictation.dictationNumber) }
            }
            if state == .idle { preview.settle() }
            dictationState = state
            isHandsFreeRecording = state == .recording && dictation.isHandsFree
            keepAwake(state == .recording)
        }
        dictation.handsFreeLimit = TimeInterval(handsFreeMinutes * 60)
        applyInsertMode()
        dictation.language = language == "auto" ? nil : language
        dictation.vocabularyHint = { [weak self] in self?.vocabulary.vocabulary.hint }
        dictation.onText = { [weak self] text, number in
            guard let self else { return }
            if deliveryMode.pastes {
                inserter.insert(styled(text))
            } else {
                preview.append(styled(text), dictation: number)
            }
        }
        dictation.onDraft = { [weak self] draft, number in
            guard let self else { return }
            preview.showDraft(styled(draft), dictation: number)
        }
        dictation.onDictationFinished = { [weak self] text, isDelivered, number in
            guard let self else { return }
            let text = styled(text)
            dictations.add(text)
            let keeps = isDelivered && !deliveryMode.pastes
            if keeps { keepInClipboard(text) }
            preview.finish(text: text, isCopied: keeps, dictation: number)
        }
        preview.onCopy = { [weak self] text in self?.keepInClipboard(text) }
        clipboardWatcher.onCopy = { [weak self] text in self?.clipboard.add(text) }
        clipboardWatcher.start()
        worker.async { [weak self, transcriber] in
            let ready = (try? transcriber.load()) != nil
            DispatchQueue.main.async {
                self?.isTranscriberReady = ready
                if !ready { log.error("Spracherkennung nicht verfügbar") }
            }
        }
        // Endet eine Aufnahme anders als gewollt, soll man es auch hören, nicht nur sehen.
        dictation.onNotice = { [weak self] text in
            self?.show(notice: text)
            NSSound(named: "Basso")?.play()
        }
        recorder.onMicrophoneLost = { [weak self] in
            self?.dictation.stopUnexpectedly(reason: "weil kein Mikrofon mehr verfügbar ist")
        }
        inserter.onRestored = { [weak self] in self?.clipboardWatcher.skipCurrentChange() }
        hotkey.onChange = { [weak self] isPressed, isAlone in self?.keyChanged(isPressed, isAlone: isAlone) }
        hotKeys.register(KeyCombo(keyCode: UInt32(kVK_ANSI_W), modifiers: UInt32(controlKey | optionKey))) { [weak self] in
            self?.openCorrection()
        }
        isWindowManagerEnabled = windowManager.isEnabled
        enableLoginItemOnFirstLaunch()
        // Erst nach dem Start, damit die Menüleiste schon steht, wenn ein Dialog erscheint.
        // Die Update-Fenster erst danach, damit nie zwei Dialoge übereinander liegen.
        DispatchQueue.main.async { [weak self] in
            OldVersionCleanup.runIfNeeded()
            self?.introduceUpdates()
        }
        InstallerVolumeEject.runSoon()
        checksForUpdates = updates.isEnabled
        updates.isBusy = { [weak self] in self?.dictationState != .idle }
        updates.onFound = { [weak self] release, announce in
            guard let self else { return }
            availableUpdate = release
            if announce { showUpdate(activate: false) }
        }
        updates.start()
        // ⌥⇧-Kürzel lösen auch mit der rechten Option-Taste aus. Eine dabei gestartete Aufnahme
        // ist ein Versehen und wird verworfen, ohne etwas einzufügen (SPEC 1.8).
        windowManager.willPerform = { [weak self] in self?.dictation.cancel(reason: "Fenster-Kürzel") }

        observers = SystemEvents.observeInterruptions { [weak self] reason in
            self?.dictation.stopUnexpectedly(reason: reason, insert: false)
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
    /// Nach dem Speichern ersetzt Wad auch gleich das markierte falsche Wort im Text, aber nur diese
    /// eine Stelle. Dafür geht der Fokus zurück an die App, in der markiert war, und Wad fügt die
    /// richtige Schreibweise über die Markierung ein, wie ein Diktat, mit Rückgabe der Zwischenablage.
    func openCorrection() {
        let selection = SelectedText.current()
        let sourceApp = NSWorkspace.shared.frontmostApplication
        clipboardWatcher.skipCurrentChange()   // Wads kurze Kopie gehört nicht in den Verlauf
        correctionPanel.show(wrong: selection ?? "") { [weak self] entry, permanently in
            guard let self else { return }
            vocabulary.add(entry, permanently: permanently)
            guard selection != nil, let sourceApp, sourceApp != .current else { return }
            sourceApp.activate()
            // Kurz warten, bis die App wieder vorne ist und ihre Markierung zurück hat.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, NSWorkspace.shared.frontmostApplication == sourceApp else { return }
                inserter.insert(isLowercase ? entry.right.lowercased(with: .current) : entry.right)
            }
        }
    }

    /// Nacheinander und nie über einer Berechtigungsfrage: erst „Was ist neu“, dann beim allerersten Mal
    /// der Hinweis, dass man die Update-Prüfung einschalten kann. Fehlt eine Berechtigung, fragt macOS gerade danach, dann wartet beides bis zum
    /// nächsten Start (nach der Freigabe startet Wad ohnehin neu).
    private func introduceUpdates() {
        guard Permissions.hasMicrophone, Permissions.hasAccessibility else { return }
        guard showsWhatsNew else { return showUpdateInfo() }
        UserDefaults.standard.set(UpdateChecker.current.description, forKey: Self.lastSeenKey)
        updateWindows.showWhatsNew(title: "Wad wurde auf \(UpdateChecker.current) aktualisiert") { [weak self] in
            self?.showUpdateInfo()
        }
    }

    private func showUpdateInfo() {
        guard updates.needsInfo else { return }
        updateWindows.showUpdateInfo { [weak self] turnOn in
            guard let self else { return }
            updates.needsInfo = false
            if turnOn { checksForUpdates = true }
        }
    }

    /// Menü „Was ist neu …“.
    func openWhatsNew() {
        updateWindows.showWhatsNew(title: "Neu in Wad \(UpdateChecker.current)")
    }

    /// Der Hinweis auf die neue Version, aus dem Menü oder nach einer Prüfung.
    func showUpdate(activate: Bool = true) {
        guard let release = availableUpdate else { return }
        updateWindows.showUpdate(release, activate: activate) { [weak self] in
            self?.updates.skipped = release.version
            self?.availableUpdate = nil
        }
    }

    /// Menü „Nach Updates suchen …“. Man wartet gerade auf das Ergebnis, also kommt es sichtbar als
    /// kleines Systemfenster, nicht nur als Zeile im geschlossenen Menü. Eine neue Version öffnet ihr Fenster.
    func checkForUpdatesNow() {
        updates.checkNow { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let release?):
                availableUpdate = release
                showUpdate()
            case .success(nil):
                Self.tell("Keine Updates gefunden", "Wad \(UpdateChecker.current) ist die neueste Version.")
            case .failure:
                Self.tell("Keine Verbindung", "Wad konnte gerade nicht nachsehen. Versuch es später noch einmal.")
            }
        }
    }

    private static func tell(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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

    private func applyInsertMode() {
        dictation.mode = insertMode.isLive ? .live : .atEnd
        dictation.deliversDrafts = insertMode == .clipboardPreview
    }

    /// Modi „Nur in die Zwischenablage“ und „mit Vorschau“: Der Text bleibt dort, der alte Inhalt ist bewusst weg.
    /// Ein normaler Eintrag, nicht „vorübergehend“. In Wads eigenem Zwischenablage-Verlauf erscheint
    /// er nicht noch einmal, weil er schon unter „Letzte Diktate“ steht.
    private func keepInClipboard(_ text: String) {
        copyToClipboard(text)
        clipboardWatcher.skipCurrentChange()
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

    private func keyChanged(_ isPressed: Bool, isAlone: Bool) {
        guard isPressed else {
            dictation.keyReleased(isAlone: isAlone)
            return
        }
        // Ein Druck beendet freies Diktieren immer, auch wenn sonst gerade nichts starten dürfte.
        guard isHandsFreeRecording || canStartRecording() else { return }
        dictation.keyPressed(isAlone: isAlone)
    }

    /// Menü: freies Diktieren starten oder beenden.
    func toggleHandsFree() {
        if isHandsFreeRecording {
            dictation.stopHandsFree()
        } else if canStartRecording() {
            dictation.startHandsFree()
        }
    }

    /// Prüft alles, was vor einer Aufnahme stimmen muss, und sagt sonst klar, was fehlt.
    private func canStartRecording() -> Bool {
        guard isEnabled else { return false }
        // Das Mikrofon-Recht kann jederzeit in den Systemeinstellungen entzogen werden.
        hasMicrophone = Permissions.hasMicrophone
        guard hasMicrophone else {
            show(notice: "Wad darf das Mikrofon nicht benutzen")
            return false
        }
        // Lädt das Modell noch, darf trotzdem diktiert werden: Die Umwandlung wartet einfach dahinter.
        guard isTranscriberReady != false else {
            show(notice: "Spracherkennung nicht verfügbar")
            return false
        }
        notice = nil
        return true
    }

    /// Hält während einer Aufnahme Bildschirm und Mac wach. Wer nur spricht und eine Sondertaste hält,
    /// tippt und klickt nicht. Ohne diese Anmeldung ging der Bildschirm bei langen Diktaten nach der
    /// eingestellten Ruhezeit aus, und das hat die Aufnahme abgebrochen.
    private func keepAwake(_ awake: Bool) {
        if awake, awakeActivity == nil {
            awakeActivity = ProcessInfo.processInfo.beginActivity(
                options: [.idleDisplaySleepDisabled, .userInitiated], reason: "Wad nimmt ein Diktat auf")
        } else if !awake, let activity = awakeActivity {
            ProcessInfo.processInfo.endActivity(activity)
            awakeActivity = nil
        }
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
            dictation.stopUnexpectedly(reason: "weil die Bedienungshilfen-Freigabe entzogen wurde", insert: false)
            waitForAccessibility()
        }
    }
}
