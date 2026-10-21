// SystemEvents.swift
// Meldet Systemereignisse, bei denen eine laufende Aufnahme sofort enden muss (SPEC 2.2, Punkt 3).

import AppKit

enum SystemEvents {
    /// Ruft `handler` mit dem Grund als Satzteil auf, etwa „weil der Bildschirm gesperrt wurde“.
    /// Die Rückgabe muss gehalten werden, solange beobachtet wird.
    static func observeInterruptions(_ handler: @escaping (String) -> Void) -> [NSObjectProtocol] {
        let workspace = NSWorkspace.shared.notificationCenter
        let events: [(NSNotification.Name, String)] = [
            (NSWorkspace.willSleepNotification, "weil der Mac in den Ruhezustand ging"),
            (NSWorkspace.screensDidSleepNotification, "weil der Bildschirm ausging"),
            (NSWorkspace.sessionDidResignActiveNotification, "weil der Benutzer gewechselt wurde"),
        ]
        var observers = events.map { name, reason in
            workspace.addObserver(forName: name, object: nil, queue: .main) { _ in handler(reason) }
        }
        // Die Bildschirmsperre meldet macOS nur systemweit.
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { _ in handler("weil der Bildschirm gesperrt wurde") })
        return observers
    }
}
