// UpdateWindows.swift
// Die kleinen Fenster rund um Updates (SPEC 1.9): „Was ist neu“ nach einem Update, der einmalige Hinweis,
// dass man die Update-Prüfung einschalten kann, und der Hinweis auf eine neue Version. Immer nur eines zugleich.

import SwiftUI

final class UpdateWindows {
    private var panel: NSPanel?
    private var closeWatcher: CloseWatcher?

    /// Die Stichpunkte aus WasIstNeu.md, als schlichter Text.
    static var whatsNew: [String] {
        guard let url = Bundle.main.url(forResource: "WasIstNeu", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline)
            .filter { $0.hasPrefix("- ") }
            .map { UpdateRules.plainText(String($0.dropFirst(2))) }
    }

    func showWhatsNew(title: String, onClose: @escaping () -> Void = {}) {
        present(title: "Was ist neu", activate: true, onClose: onClose) { close in
            InfoView(title: title, lines: Self.whatsNew, close: close)
        }
    }

    /// Weist einmal darauf hin, dass man die Update-Prüfung einschalten kann. Eingeschaltet wird nur
    /// mit dem Knopf, Schließen heißt: bleibt aus.
    func showUpdateInfo(onClose: @escaping (_ turnOn: Bool) -> Void) {
        var turnOn = false
        present(title: "Updates", activate: true, onClose: { onClose(turnOn) }) { close in
            UpdateInfoView { on in
                turnOn = on
                close()
            }
        }
    }

    /// Der Hinweis auf eine neue Version. Kommt er von selbst, nimmt er der App, in der man gerade
    /// schreibt, nicht den Fokus. Wad lädt nichts selbst, „Zum Download“ öffnet nur die Seite im Browser.
    func showUpdate(_ release: Release, activate: Bool, onSkip: @escaping () -> Void) {
        present(title: "Update", activate: activate, onClose: {}) { close in
            UpdateView(release: release,
                       download: { NSWorkspace.shared.open(UpdateChecker.downloadPage); close() },
                       later: close,
                       skip: { onSkip(); close() })
        }
    }

    private func present<Content: View>(title: String, activate: Bool, onClose: @escaping () -> Void,
                                        content: (@escaping () -> Void) -> Content) {
        panel?.close()
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        let watcher = CloseWatcher(onClose: onClose)
        panel.delegate = watcher
        let hosting = NSHostingController(rootView: content { [weak panel] in panel?.close() })
        hosting.sizingOptions = .preferredContentSize
        panel.contentViewController = hosting
        panel.setContentSize(hosting.view.fittingSize)
        panel.center()
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        self.panel = panel
        closeWatcher = watcher
    }
}

/// Meldet das Schließen, egal ob per Knopf oder über das rote X.
private final class CloseWatcher: NSObject, NSWindowDelegate {
    private var onClose: (() -> Void)?
    init(onClose: @escaping () -> Void) { self.onClose = onClose }

    func windowWillClose(_ notification: Notification) {
        onClose?()
        onClose = nil
    }
}

private struct InfoView: View {
    let title: String
    let lines: [String]
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(verbatim: line).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Fertig", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

private struct UpdateInfoView: View {
    let finish: (_ turnOn: Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Immer auf dem neuesten Stand?").font(.headline)
            Text("Wad kann einmal am Tag nachsehen, ob es eine neue Version gibt. Das ist sinnvoll, damit du Verbesserungen und Fehlerbehebungen bekommst. Dabei fragt Wad bei GitHub nur nach der neuesten Versionsnummer. Diktate, Vokabeln oder Daten über dich werden nie gesendet. Du kannst das jederzeit im Menü unter „Updates“ ändern oder dort selbst nachsehen.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Nicht jetzt") { finish(false) }.keyboardShortcut(.cancelAction)
                Button("Einschalten") { finish(true) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

private struct UpdateView: View {
    let release: Release
    let download: () -> Void
    let later: () -> Void
    let skip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Wad \(release.version.description) ist da").font(.headline)
            // Schlichter Text: Links darin sind nicht anklickbar, nur „Zum Download“ führt ins Netz.
            // Lange Beschreibungen scrollen, damit das Fenster handlich bleibt.
            if release.notes.count > 500 {
                ScrollView { notes }.frame(height: 220)
            } else if !release.notes.isEmpty {
                notes
            }
            HStack {
                Button("Diese Version überspringen", action: skip)
                Spacer()
                Button("Später", action: later).keyboardShortcut(.cancelAction)
                Button("Zum Download", action: download).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var notes: some View {
        Text(verbatim: release.notes)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
