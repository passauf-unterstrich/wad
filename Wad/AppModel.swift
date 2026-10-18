// AppModel.swift
// Verbindet Wads Teile: Taste, Aufnahme-Automat, Spracherkennung, Berechtigungen und Systemereignisse.
// Menü und Symbol lesen ihren Zustand nur von hier.

import SwiftUI

final class AppModel: ObservableObject {
    @Published var isEnabled = true {
        didSet { if !isEnabled { dictation.cancel(reason: "Diktieren ausgeschaltet") } }
    }
    @Published private(set) var dictationState = DictationController.State.idle
    @Published private(set) var hasMicrophone = Permissions.hasMicrophone
    @Published private(set) var hasAccessibility = Permissions.hasAccessibility
    /// Ob das Sprachmodell bereitsteht. `nil`, solange es noch lädt.
    @Published private(set) var isTranscriberReady: Bool?
    /// Text des letzten Diktats, nur im Arbeitsspeicher. Ab Etappe 6 wird daraus der Verlauf.
    @Published private(set) var lastTranscript: String?

    private let hotkey = HotkeyMonitor()
    private let recorder = MicrophoneRecorder()
    private let transcriber: WhisperTranscriber
    private let dictation: DictationController
    private var observers: [NSObjectProtocol] = []
    private var accessibilityTimer: Timer?

    init() {
        transcriber = WhisperTranscriber()
        dictation = DictationController(capture: recorder, transcriber: transcriber,
                                        isKeyPhysicallyDown: HotkeyMonitor.isRightOptionDown)
        transcriber.onLoaded = { [weak self] error in self?.isTranscriberReady = error == nil }
        dictation.onStateChange = { [weak self] state in self?.dictationState = state }
        dictation.onTranscript = { [weak self] text in self?.lastTranscript = text }
        recorder.onDeviceChange = { [weak self] in self?.dictation.cancel(reason: "Audiogerät gewechselt") }
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
            self?.dictation.cancel(reason: "Wad wird beendet")
            self?.transcriber.shutdown()
        })

        log.notice("Start, Mikrofon: \(self.hasMicrophone, privacy: .public), Bedienungshilfen: \(self.hasAccessibility, privacy: .public)")
        if hasAccessibility { hotkey.start() } else { waitForAccessibility() }
        askForMissingPermissions()
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
        guard hasMicrophone else { return }
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
