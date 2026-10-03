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

    private static func clear(_ draw: () -> Void) {
        NSGraphicsContext.current?.compositingOperation = .clear
        draw()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }

    private static func stroke(_ points: [NSPoint], width: CGFloat, curve: (NSPoint, NSPoint)? = nil) {
        let path = NSBezierPath()
        path.move(to: points[0])
        if let curve, points.count == 2 {
            path.curve(to: points[1], controlPoint1: curve.0, controlPoint2: curve.1)
        } else {
            points.dropFirst().forEach { path.line(to: $0) }
        }
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private static func drawRooster() {
        NSColor.black.setFill()
        NSColor.black.setStroke()

        // Two rounded tail feathers.
        stroke([NSPoint(x: 4.6, y: 8.4), NSPoint(x: 1.0, y: 12.2)], width: 2.2,
               curve: (NSPoint(x: 2.8, y: 8.4), NSPoint(x: 1.2, y: 10.0)))
        stroke([NSPoint(x: 5.6, y: 9.4), NSPoint(x: 2.6, y: 15.4)], width: 2.2,
               curve: (NSPoint(x: 4.0, y: 10.6), NSPoint(x: 2.6, y: 12.8)))

        // One smooth body from the neck around the belly.
        let body = NSBezierPath()
        body.move(to: NSPoint(x: 9.0, y: 12.6))
        body.curve(to: NSPoint(x: 3.0, y: 7.6), controlPoint1: NSPoint(x: 6.8, y: 11.4), controlPoint2: NSPoint(x: 3.0, y: 10.6))
        body.curve(to: NSPoint(x: 8.0, y: 2.8), controlPoint1: NSPoint(x: 3.0, y: 4.6), controlPoint2: NSPoint(x: 5.4, y: 2.8))
        body.curve(to: NSPoint(x: 12.8, y: 7.6), controlPoint1: NSPoint(x: 10.8, y: 2.8), controlPoint2: NSPoint(x: 12.8, y: 4.8))
        body.curve(to: NSPoint(x: 12.4, y: 12.4), controlPoint1: NSPoint(x: 12.8, y: 9.6), controlPoint2: NSPoint(x: 12.2, y: 11.0))
        body.close()
        body.fill()

        // Round head with a three-bump comb.
        NSBezierPath(ovalIn: NSRect(x: 8.4, y: 11.0, width: 5.0, height: 5.0)).fill()
        for x in [9.4, 10.9, 12.4] {
            NSBezierPath(ovalIn: NSRect(x: x - 1.15, y: 15.2, width: 2.3, height: 2.3)).fill()
        }

        // Thick legs.
        stroke([NSPoint(x: 6.6, y: 3.6), NSPoint(x: 6.2, y: 0.9)], width: 1.5)
        stroke([NSPoint(x: 9.4, y: 3.6), NSPoint(x: 9.8, y: 0.9)], width: 1.5)

        // Eye and wing cut out of the silhouette.
        clear {
            NSBezierPath(ovalIn: NSRect(x: 11.0, y: 13.4, width: 1.3, height: 1.3)).fill()
            stroke([NSPoint(x: 5.4, y: 7.8), NSPoint(x: 10.2, y: 6.6)], width: 1.0,
                   curve: (NSPoint(x: 6.6, y: 5.4), NSPoint(x: 9.0, y: 5.2)))
        }

        // A large letter, held by the beak drawn over its corner.
        let letter = NSRect(x: 13.6, y: 7.6, width: 7.4, height: 5.8)
        clear { NSBezierPath(roundedRect: letter.insetBy(dx: -1.0, dy: -1.0), xRadius: 1.8, yRadius: 1.8).fill() }
        let envelope = NSBezierPath(roundedRect: letter, xRadius: 1.1, yRadius: 1.1)
        envelope.lineWidth = 1.4
        envelope.stroke()
        stroke([NSPoint(x: letter.minX + 0.9, y: letter.maxY - 0.9), NSPoint(x: letter.midX, y: letter.midY - 0.3),
                NSPoint(x: letter.maxX - 0.9, y: letter.maxY - 0.9)], width: 1.2)

        let beak = NSBezierPath()
        beak.move(to: NSPoint(x: 13.0, y: 14.6))
        beak.line(to: NSPoint(x: 15.8, y: 13.4))
        beak.line(to: NSPoint(x: 13.2, y: 12.4))
        beak.close()
        beak.lineJoinStyle = .round
        beak.lineWidth = 0.6
        beak.fill()
        beak.stroke()
    }

    private static func drawBadge(_ symbolName: String) {
        let area = NSRect(x: 16.0, y: 0.0, width: 6.0, height: 6.0)
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(ovalIn: area.insetBy(dx: -0.8, dy: -0.8)).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        let configuration = NSImage.SymbolConfiguration(pointSize: 6.0, weight: .bold)
        NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)?
            .draw(in: area)
    }
}
