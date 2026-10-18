// MenuBarIcon.swift
// Zeichnet Wads Menüleisten-Symbole (SPEC 1.2): Studio-Mikrofon mit KI-Funkeln (an), dasselbe
// durchgestrichen (aus), mit drei Punkten (verarbeitet), mit Ausrufezeichen (Hinweis) und den
// roten Aufnahme-Punkt. Alles als Vektor, scharf auf jedem Bildschirm.

import AppKit

enum MenuBarIcon {
    static let enabled = template(.sparkle, description: "Wad")
    static let disabled = template(.slashed, description: "Wad, Diktieren aus")
    static let processing = template(.dots, description: "Wad wandelt um")
    static let notice = template(.exclamation, description: "Wad hat einen Hinweis")

    /// Was neben bzw. über dem Mikrofon steht. Das Mikrofon selbst bleibt immer gleich.
    private enum Accent {
        case sparkle, slashed, dots, exclamation
    }

    /// Roter Punkt, auf derselben Fläche und genau dort zentriert, wo das Mikrofon steht,
    /// damit beim Drücken nichts springt. Ausdrücklich farbig, also kein „Template“.
    static let recording: NSImage = {
        let image = NSImage(size: canvas, flipped: true) { _ in
            let diameter: CGFloat = 11
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: NSRect(x: micCenter.x - diameter / 2, y: micCenter.y - diameter / 2,
                                        width: diameter, height: diameter)).fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Wad nimmt auf"
        return image
    }()

    /// Alle drei Zustände teilen dieselbe Fläche. Das Mikrofon steht genau in der Mitte,
    /// der Stern ragt nach rechts hinaus.
    private static let canvas = NSSize(width: 20, height: 18)
    /// Optische Mitte des Mikrofons (y nach unten), auf die auch der rote Punkt gesetzt wird.
    private static let micCenter = NSPoint(x: 10, y: 8.65)

    private static let lineWidth: CGFloat = 1.4

    /// Template-Bilder färbt macOS selbst passend zur Menüleiste weiß oder schwarz.
    private static func template(_ accent: Accent, description: String) -> NSImage {
        let image = NSImage(size: canvas, flipped: true) { _ in
            // Gezeichnet wird auf einem 18-pt-Raster (y nach unten), verkleinert auf 90 %,
            // damit Höhe und Linienstärke zu Apples eigenen Symbolen passen.
            let context = NSGraphicsContext.current!.cgContext
            context.translateBy(x: micCenter.x, y: 9)
            context.scaleBy(x: 0.9, y: 0.9)
            context.translateBy(x: -9, y: -9)
            NSColor.black.set()
            drawMicrophone()
            switch accent {
            case .sparkle: drawSparkle(center: accentCenter, radius: 3)
            case .slashed: drawSparkle(center: accentCenter, radius: 3); drawSlash()
            case .dots: drawDots()
            case .exclamation: drawExclamation()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description
        return image
    }

    /// Studio-Mikrofon, mittig auf x = 9 des Rasters: Kapsel mit zwei Rillen, Gabel, Stiel und Fuß.
    private static func drawMicrophone() {
        let head = NSRect(x: 6, y: 1, width: 6, height: 9.5)
        let capsule = NSBezierPath(roundedRect: head, xRadius: 3, yRadius: 3)
        capsule.lineWidth = lineWidth
        capsule.stroke()

        let grille = NSBezierPath()
        for y: CGFloat in [4.6, 7.0] {
            grille.move(to: NSPoint(x: 6, y: y))
            grille.line(to: NSPoint(x: 12, y: y))
        }
        grille.lineWidth = 1.0
        grille.stroke()

        let stand = NSBezierPath()
        stand.move(to: NSPoint(x: 3.75, y: 6))
        stand.appendArc(withCenter: NSPoint(x: 9, y: 7.5), radius: 5.25, startAngle: 180, endAngle: 0, clockwise: true)
        stand.line(to: NSPoint(x: 14.25, y: 6))
        stand.move(to: NSPoint(x: 9, y: 12.75))
        stand.line(to: NSPoint(x: 9, y: 16.25))
        stand.move(to: NSPoint(x: 5.5, y: 16.25))
        stand.line(to: NSPoint(x: 12.5, y: 16.25))
        stand.lineWidth = lineWidth
        stand.lineCapStyle = .round
        stand.stroke()
    }

    /// Vierzackiger Funkelstern, das gängige Zeichen für KI.
    private static func drawSparkle(center c: NSPoint, radius r: CGFloat) {
        let k = 0.18 * r
        let tips = [NSPoint(x: c.x, y: c.y - r), NSPoint(x: c.x + r, y: c.y),
                    NSPoint(x: c.x, y: c.y + r), NSPoint(x: c.x - r, y: c.y)]
        let inner = [NSPoint(x: c.x + k, y: c.y - k), NSPoint(x: c.x + k, y: c.y + k),
                     NSPoint(x: c.x - k, y: c.y + k), NSPoint(x: c.x - k, y: c.y - k)]
        let star = NSBezierPath()
        star.move(to: tips[0])
        for i in 0..<4 {
            star.curve(to: tips[(i + 1) % 4], controlPoint1: inner[i], controlPoint2: inner[i])
        }
        star.close()
        star.fill()
    }

    /// Wo der Stern sitzt; die anderen Zeichen nehmen denselben Platz ein.
    private static let accentCenter = NSPoint(x: 16.7, y: 3.2)

    /// Drei Punkte untereinander an der Stelle des Sterns: „Moment, ich arbeite“.
    private static func drawDots() {
        for dy: CGFloat in [-2.4, 0, 2.4] {
            let r: CGFloat = 0.85
            NSBezierPath(ovalIn: NSRect(x: accentCenter.x - r, y: accentCenter.y + 1 + dy - r,
                                        width: 2 * r, height: 2 * r)).fill()
        }
    }

    /// Ausrufezeichen an der Stelle des Sterns: „Schau ins Menü“.
    private static func drawExclamation() {
        let bar = NSBezierPath()
        bar.move(to: NSPoint(x: accentCenter.x, y: accentCenter.y - 2.6))
        bar.line(to: NSPoint(x: accentCenter.x, y: accentCenter.y + 1.6))
        bar.lineWidth = lineWidth + 0.2
        bar.lineCapStyle = .round
        bar.stroke()
        let r: CGFloat = 0.95
        NSBezierPath(ovalIn: NSRect(x: accentCenter.x - r, y: accentCenter.y + 4.1 - r,
                                    width: 2 * r, height: 2 * r)).fill()
    }

    /// Diagonaler Strich mit ausgestanzter Lücke drumherum, wie bei Apples „.slash“-Symbolen.
    private static func drawSlash() {
        let context = NSGraphicsContext.current!.cgContext
        let slash = NSBezierPath()
        slash.move(to: NSPoint(x: 3.5, y: 1.5))
        slash.line(to: NSPoint(x: 14.5, y: 16.5))
        slash.lineCapStyle = .round
        context.setBlendMode(.clear)
        slash.lineWidth = lineWidth + 2.2
        slash.stroke()
        context.setBlendMode(.normal)
        slash.lineWidth = lineWidth
        slash.stroke()
    }
}
