// SystemEvents.swift
// Meldet Systemereignisse, bei denen eine laufende Aufnahme sofort enden muss (SPEC 2.2, Punkt 3).

import AppKit

enum SystemEvents {
    /// Ruft `handler` mit einem kurzen Grund auf. Die Rückgabe muss gehalten werden, solange beobachtet wird.
    static func observeInterruptions(_ handler: @escaping (String) -> Void) -> [NSObjectProtocol] {
        let workspace = NSWorkspace.shared.notificationCenter
        let events: [(NSNotification.Name, String)] = [
            (NSWorkspace.willSleepNotification, "Ruhezustand"),
            (NSWorkspace.screensDidSleepNotification, "Bildschirm aus"),
            (NSWorkspace.sessionDidResignActiveNotification, "Benutzerwechsel"),
        ]
        var observers = events.map { name, reason in
            workspace.addObserver(forName: name, object: nil, queue: .main) { _ in handler(reason) }
        }
        // Die Bildschirmsperre meldet macOS nur systemweit.
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { _ in handler("Bildschirmsperre") })
        return observers
    }
}
