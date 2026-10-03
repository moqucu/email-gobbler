import AppKit

/// The menu bar icon: a rooster carrying a letter in its beak, drawn as a
/// template image so macOS tints it for light and dark menu bars. An optional
/// SF Symbol badge in the lower right shows a state other than idle.
enum MenuBarIcon {
    static let size = NSSize(width: 22, height: 18)

    static func image(badge symbolName: String?) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            drawRooster()
            if let symbolName { drawBadge(symbolName) }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Email Gobbler"
        return image
    }

    private static func drawRooster() {
        NSColor.black.setFill()
        NSColor.black.setStroke()

        let body = NSBezierPath()
        body.move(to: NSPoint(x: 4.2, y: 8.6))
        body.curve(to: NSPoint(x: 11.6, y: 3.2), controlPoint1: NSPoint(x: 3.4, y: 4.6), controlPoint2: NSPoint(x: 7.4, y: 2.6))
        body.curve(to: NSPoint(x: 13.4, y: 9.4), controlPoint1: NSPoint(x: 14.2, y: 3.8), controlPoint2: NSPoint(x: 14.4, y: 7.2))
        body.line(to: NSPoint(x: 13.6, y: 12.4))
        body.line(to: NSPoint(x: 10.6, y: 12.0))
        body.line(to: NSPoint(x: 10.0, y: 8.8))
        body.close()
        body.fill()

        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 5.6, y: 8.2))
        tail.curve(to: NSPoint(x: 1.0, y: 15.2), controlPoint1: NSPoint(x: 3.0, y: 9.0), controlPoint2: NSPoint(x: 1.0, y: 12.0))
        tail.curve(to: NSPoint(x: 3.8, y: 11.6), controlPoint1: NSPoint(x: 2.2, y: 13.4), controlPoint2: NSPoint(x: 3.0, y: 12.2))
        tail.curve(to: NSPoint(x: 3.4, y: 16.2), controlPoint1: NSPoint(x: 3.2, y: 13.4), controlPoint2: NSPoint(x: 3.0, y: 15.0))
        tail.curve(to: NSPoint(x: 6.6, y: 9.6), controlPoint1: NSPoint(x: 4.6, y: 13.4), controlPoint2: NSPoint(x: 5.4, y: 11.0))
        tail.close()
        tail.fill()

        NSBezierPath(ovalIn: NSRect(x: 10.4, y: 11.0, width: 4.4, height: 4.4)).fill()
        for center in [NSPoint(x: 11.2, y: 15.6), NSPoint(x: 12.5, y: 16.3), NSPoint(x: 13.8, y: 15.6)] {
            NSBezierPath(ovalIn: NSRect(x: center.x - 0.95, y: center.y - 0.95, width: 1.9, height: 1.9)).fill()
        }
        NSBezierPath(ovalIn: NSRect(x: 13.2, y: 9.4, width: 1.4, height: 2.0)).fill()

        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(ovalIn: NSRect(x: 12.6, y: 13.0, width: 1.0, height: 1.0)).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver

        for (from, to) in [(NSPoint(x: 7.2, y: 3.6), NSPoint(x: 6.6, y: 0.6)), (NSPoint(x: 9.6, y: 3.4), NSPoint(x: 10.2, y: 0.6))] {
            let leg = NSBezierPath()
            leg.move(to: from)
            leg.line(to: to)
            leg.lineWidth = 1.1
            leg.lineCapStyle = .round
            leg.stroke()
        }

        let letter = NSRect(x: 15.4, y: 8.2, width: 6.0, height: 4.2)
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(rect: letter.insetBy(dx: -0.6, dy: -0.6)).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        let envelope = NSBezierPath(rect: letter)
        envelope.lineWidth = 1.0
        envelope.stroke()
        let flap = NSBezierPath()
        flap.move(to: NSPoint(x: letter.minX, y: letter.maxY))
        flap.line(to: NSPoint(x: letter.midX, y: letter.midY - 0.2))
        flap.line(to: NSPoint(x: letter.maxX, y: letter.maxY))
        flap.lineWidth = 0.9
        flap.stroke()
        // The beak overlaps the letter's corner so the rooster holds it.
        let beak = NSBezierPath()
        beak.move(to: NSPoint(x: 14.2, y: 14.0))
        beak.line(to: NSPoint(x: 17.4, y: 12.6))
        beak.line(to: NSPoint(x: 14.4, y: 11.8))
        beak.close()
        beak.fill()
    }

    private static func drawBadge(_ symbolName: String) {
        let area = NSRect(x: 15.0, y: 0.0, width: 7.0, height: 7.0)
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(ovalIn: area.insetBy(dx: -0.8, dy: -0.8)).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        let configuration = NSImage.SymbolConfiguration(pointSize: 6.5, weight: .bold)
        NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)?
            .draw(in: area)
    }
}
