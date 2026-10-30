// WindowLayout.swift
// Die Fenster-Aktionen des Fenstermanagers (SPEC 1.8) als reine Rechnung: Wo soll ein Fenster
// hin, wenn der Bildschirm so groß ist? Keine Bedienungshilfen, keine Oberfläche, deshalb getestet.
// Koordinaten wie bei den Bedienungshilfen: Ursprung oben links, y wächst nach unten.

import CoreGraphics

enum WindowAction: String, CaseIterable, Codable {
    case maximize, left, right, top, bottom, topLeft, topRight, bottomRight, bottomLeft, center

    var title: String {
        switch self {
        case .maximize: L10n.t("window.maximize")
        case .left: L10n.t("window.left")
        case .right: L10n.t("window.right")
        case .top: L10n.t("window.top")
        case .bottom: L10n.t("window.bottom")
        case .topLeft: L10n.t("window.topLeft")
        case .topRight: L10n.t("window.topRight")
        case .bottomRight: L10n.t("window.bottomRight")
        case .bottomLeft: L10n.t("window.bottomLeft")
        case .center: L10n.t("window.center")
        }
    }

    /// Hälften wechseln bei wiederholtem Drücken die Größe, alles andere nicht.
    var cycles: Bool {
        [.left, .right, .top, .bottom].contains(self)
    }
}

enum WindowLayout {
    /// Reihenfolge beim mehrfachen Drücken desselben Kürzels, wie bei Spectacle.
    static let fractions: [CGFloat] = [1.0 / 2, 2.0 / 3, 1.0 / 3]

    /// Zielrahmen eines Fensters.
    /// - Parameters:
    ///   - visible: nutzbare Fläche des Bildschirms, ohne Menüleiste und Dock.
    ///   - current: jetziger Rahmen, nur fürs Zentrieren gebraucht.
    ///   - step: wie oft dasselbe Kürzel hintereinander gedrückt wurde, ab 0.
    static func frame(for action: WindowAction, in visible: CGRect, current: CGRect, step: Int = 0) -> CGRect {
        let fraction = fractions[step % fractions.count]
        let v = visible
        switch action {
        case .maximize:
            return v
        case .left:
            return CGRect(x: v.minX, y: v.minY, width: v.width * fraction, height: v.height)
        case .right:
            return CGRect(x: v.maxX - v.width * fraction, y: v.minY, width: v.width * fraction, height: v.height)
        case .top:
            return CGRect(x: v.minX, y: v.minY, width: v.width, height: v.height * fraction)
        case .bottom:
            return CGRect(x: v.minX, y: v.maxY - v.height * fraction, width: v.width, height: v.height * fraction)
        case .topLeft:
            return CGRect(x: v.minX, y: v.minY, width: v.width / 2, height: v.height / 2)
        case .topRight:
            return CGRect(x: v.midX, y: v.minY, width: v.width / 2, height: v.height / 2)
        case .bottomRight:
            return CGRect(x: v.midX, y: v.midY, width: v.width / 2, height: v.height / 2)
        case .bottomLeft:
            return CGRect(x: v.minX, y: v.midY, width: v.width / 2, height: v.height / 2)
        case .center:
            let size = CGSize(width: min(current.width, v.width), height: min(current.height, v.height))
            return CGRect(x: v.midX - size.width / 2, y: v.midY - size.height / 2,
                          width: size.width, height: size.height).integral
        }
    }

    /// Lässt eine App ihr Fenster nicht so klein werden, schiebt Wad es zurück auf den Bildschirm,
    /// statt es über den Rand ragen zu lassen. Die vom Ziel gewünschte Kante bleibt dabei stehen.
    static func keepOnScreen(_ frame: CGRect, in visible: CGRect) -> CGRect {
        var result = frame
        if result.maxX > visible.maxX { result.origin.x = visible.maxX - result.width }
        if result.maxY > visible.maxY { result.origin.y = visible.maxY - result.height }
        result.origin.x = max(result.origin.x, visible.minX)
        result.origin.y = max(result.origin.y, visible.minY)
        return result
    }
}
