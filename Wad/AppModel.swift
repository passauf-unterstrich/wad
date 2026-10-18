// AppModel.swift
// Zentraler Zustand von Wad: ob Diktieren an ist, ob die Taste gerade gehalten wird
// und ob die Bedienungshilfen-Berechtigung vorliegt. Menü und Symbol lesen nur von hier.

import SwiftUI
import os

/// Protokoll nur für Zustandswechsel, nie mit Inhalten. Lesbar mit: log show --predicate 'subsystem == "com.linushundt.Wad"'
let log = Logger(subsystem: "com.linushundt.Wad", category: "Zustand")

final class AppModel: ObservableObject {
    @Published var isEnabled = true {
        didSet { if !isEnabled { isKeyHeld = false } }
    }
    @Published private(set) var isKeyHeld = false
    @Published private(set) var hasAccessibility = Permissions.hasAccessibility

    private let hotkey = HotkeyMonitor()
    private var accessibilityObserver: NSObjectProtocol?
    private var accessibilityTimer: Timer?

    init() {
        hotkey.onChange = { [weak self] isPressed in self?.keyChanged(isPressed) }
        accessibilityObserver = Permissions.observeAccessibilityChanges { [weak self] in
            self?.refreshAccessibility()
        }
        log.notice("Start, Bedienungshilfen: \(self.hasAccessibility, privacy: .public)")
        if hasAccessibility {
            hotkey.start()
        } else {
            Permissions.requestAccessibility()
            waitForAccessibility()
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
            isKeyHeld = false
            waitForAccessibility()
        }
    }

    private func keyChanged(_ isPressed: Bool) {
        isKeyHeld = isEnabled && isPressed
    }
}
