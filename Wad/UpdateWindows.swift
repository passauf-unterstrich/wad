// UpdateWindows.swift
// Die kleinen Fenster rund um Updates (SPEC 1.9): „Was ist neu“ nach einem Update, der einmalige Hinweis,
// dass man die Update-Prüfung einschalten kann, und der Hinweis auf eine neue Version. Immer nur eines zugleich.

import SwiftUI

final class UpdateWindows {
    private var panel: NSPanel?
    private var closeWatcher: CloseWatcher?
    /// Schlüssel des Fenstertitels, damit er beim Wechsel der Menüsprache mitgeht.
    private var titleKey: String?

    /// WasIstNeu in der gewählten Menüsprache.
    static var whatsNew: (intro: String?, items: [String]) {
        guard let url = Bundle.main.url(forResource: "WasIstNeu.\(L10n.shared.language.rawValue)", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return (nil, []) }
        return UpdateRules.whatsNew(text)
    }

    /// - Parameter title: ein Abschluss statt eines fertigen Textes, weil das Fenster beim Wechsel der Menüsprache mitgeht.
    func showWhatsNew(title: @escaping () -> String, onClose: @escaping () -> Void = {}) {
        present(titleKey: "whatsNew.window", activate: true, onClose: onClose) { close in
            InfoView(title: title, close: close)
        }
    }

    /// Die Menüsprache hat gewechselt. Den Inhalt zeichnet SwiftUI von selbst neu, nur den Titel nicht.
    func refreshTitle() {
        if let titleKey { panel?.title = L10n.t(titleKey) }
    }

    /// Weist einmal darauf hin, dass man die Update-Prüfung einschalten kann. Eingeschaltet wird nur
    /// mit dem Knopf, Schließen heißt: bleibt aus.
    func showUpdateInfo(onClose: @escaping (_ turnOn: Bool) -> Void) {
        var turnOn = false
        present(titleKey: "update.consent.window", activate: true, onClose: { onClose(turnOn) }) { close in
            UpdateInfoView { on in
                turnOn = on
                close()
            }
        }
    }

    /// Der Hinweis auf eine neue Version. Kommt er von selbst, nimmt er der App, in der man gerade
    /// schreibt, nicht den Fokus. Wad lädt nichts selbst, „Zum Download“ öffnet nur die Seite im Browser.
    func showUpdate(_ release: Release, activate: Bool, onSkip: @escaping () -> Void) {
        present(titleKey: "update.window", activate: activate, onClose: {}) { close in
            UpdateView(release: release,
                       download: { NSWorkspace.shared.open(UpdateChecker.downloadPage); close() },
                       later: close,
                       skip: { onSkip(); close() })
        }
    }

    private func present<Content: View>(titleKey: String, activate: Bool, onClose: @escaping () -> Void,
                                        content: (@escaping () -> Void) -> Content) {
        panel?.close()
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = L10n.t(titleKey)
        self.titleKey = titleKey
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
    let title: () -> String
    let close: () -> Void
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let whatsNew = UpdateWindows.whatsNew
        VStack(alignment: .leading, spacing: 14) {
            Text(title()).font(.headline)
            if let intro = whatsNew.intro { Text(verbatim: intro) }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(whatsNew.items, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(verbatim: line).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack {
                Spacer()
                Button(L10n.t("whatsNew.done"), action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

private struct UpdateInfoView: View {
    let finish: (_ turnOn: Bool) -> Void
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("update.consent.title")).font(.headline)
            Text(L10n.t("update.consent.text"))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(L10n.t("common.notNow")) { finish(false) }.keyboardShortcut(.cancelAction)
                Button(L10n.t("update.consent.turnOn")) { finish(true) }.keyboardShortcut(.defaultAction)
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
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("update.available", release.version.description)).font(.headline)
            // Schlichter Text: Links darin sind nicht anklickbar, nur der Download-Knopf führt ins Netz.
            // Lange Beschreibungen scrollen, damit das Fenster handlich bleibt.
            if release.notes.count > 500 {
                ScrollView { notes }.frame(height: 220)
            } else if !release.notes.isEmpty {
                notes
            }
            HStack {
                Button(L10n.t("update.skip"), action: skip)
                Spacer()
                Button(L10n.t("common.later"), action: later).keyboardShortcut(.cancelAction)
                Button(L10n.t("update.download"), action: download).keyboardShortcut(.defaultAction)
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
