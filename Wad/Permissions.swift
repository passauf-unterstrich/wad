// Permissions.swift
// Prüft und erfragt Wads zwei Berechtigungen, Mikrofon und Bedienungshilfen (SPEC 2.7),
// und öffnet die jeweils passende Systemeinstellung.

import AppKit
import ApplicationServices
import AVFoundation

enum Permissions {
    static var hasMicrophone: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }

    /// Fragt einmalig nach dem Mikrofon. Hat der Nutzer schon entschieden, kommt sofort die Antwort.
    static func requestMicrophone(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    static func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Zeigt den Systemdialog, der zur Freigabe in den Bedienungshilfen führt. Macht nichts, wenn sie schon erteilt ist.
    static func requestAccessibility() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Startet Wad als neuen Prozess und beendet den alten, sobald der neue läuft.
    /// Schlägt der Start fehl, bleibt der alte Prozess bestehen.
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard error == nil else {
                log.error("Neustart fehlgeschlagen: \(error!.localizedDescription, privacy: .public)")
                return
            }
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
        }
    }

    /// Ruft `handler` auf, sobald sich Bedienungshilfen-Rechte im System ändern.
    /// macOS meldet das über eine systemweite, nicht offiziell dokumentierte Mitteilung. Der neue Wert
    /// steht erst kurz danach fest, deshalb wird mit einer halben Sekunde Verzögerung nachgeprüft.
    static func observeAccessibilityChanges(_ handler: @escaping () -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: handler)
        }
    }
}
