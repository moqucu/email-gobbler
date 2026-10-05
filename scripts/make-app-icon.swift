// Draws the EmailGobbler app icon layers for App/Resources/AppIcon.icon.
// Run: swift scripts/make-app-icon.swift App/Resources/AppIcon.icon/Assets
import AppKit

let canvas = NSSize(width: 1024, height: 1024)
let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(displayP3Red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func layer(_ name: String, _ draw: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!.retagging(with: .displayP3)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
}

func fill(_ path: NSBezierPath, _ top: NSColor, _ bottom: NSColor, angle: CGFloat = -90) {
    NSGradient(starting: top, ending: bottom)!.draw(in: path, angle: angle)
}

func feather(base: NSPoint, tip: NSPoint, width: CGFloat) -> NSBezierPath {
    let dx = tip.x - base.x, dy = tip.y - base.y
    let length = hypot(dx, dy)
    let nx = -dy / length * width, ny = dx / length * width
    let path = NSBezierPath()
    path.move(to: NSPoint(x: base.x - nx * 0.4, y: base.y - ny * 0.4))
    path.curve(to: tip, controlPoint1: NSPoint(x: base.x + dx * 0.45 - nx, y: base.y + dy * 0.45 - ny),
               controlPoint2: NSPoint(x: tip.x - nx * 0.5, y: tip.y - ny * 0.5))
    path.curve(to: NSPoint(x: base.x + nx * 0.4, y: base.y + ny * 0.4),
               controlPoint1: NSPoint(x: tip.x + nx * 0.6, y: tip.y + ny * 0.6),
               controlPoint2: NSPoint(x: base.x + dx * 0.5 + nx, y: base.y + dy * 0.5 + ny))
    path.close()
    return path
}

// Back layer: tail feathers fanning up and to the left.
layer("tail.png") {
    let base = NSPoint(x: 420, y: 470)
    fill(feather(base: base, tip: NSPoint(x: 150, y: 600), width: 70), color(0x2C6FB5), color(0x1B3F7A), angle: 180)
    fill(feather(base: base, tip: NSPoint(x: 175, y: 790), width: 78), color(0x1FA38F), color(0x0F6B67), angle: 150)
    fill(feather(base: base, tip: NSPoint(x: 300, y: 880), width: 72), color(0x58C26E), color(0x23854A), angle: 120)
}

// Middle layer: the rooster.
layer("rooster.png") {
    for (from, to) in [(NSPoint(x: 470, y: 290), NSPoint(x: 445, y: 165)), (NSPoint(x: 575, y: 290), NSPoint(x: 600, y: 165))] {
        let leg = NSBezierPath()
        leg.move(to: from)
        leg.line(to: to)
        leg.move(to: to)
        leg.line(to: NSPoint(x: to.x - 45, y: to.y - 25))
        leg.move(to: to)
        leg.line(to: NSPoint(x: to.x + 45, y: to.y - 25))
        leg.lineWidth = 26
        leg.lineCapStyle = .round
        leg.lineJoinStyle = .round
        color(0xF0962E).setStroke()
        leg.stroke()
    }

    let body = NSBezierPath()
    body.move(to: NSPoint(x: 330, y: 470))
    body.curve(to: NSPoint(x: 560, y: 255), controlPoint1: NSPoint(x: 300, y: 330), controlPoint2: NSPoint(x: 420, y: 250))
    body.curve(to: NSPoint(x: 735, y: 440), controlPoint1: NSPoint(x: 680, y: 260), controlPoint2: NSPoint(x: 745, y: 340))
    body.curve(to: NSPoint(x: 705, y: 660), controlPoint1: NSPoint(x: 730, y: 520), controlPoint2: NSPoint(x: 700, y: 590))
    body.line(to: NSPoint(x: 575, y: 640))
    body.curve(to: NSPoint(x: 330, y: 470), controlPoint1: NSPoint(x: 560, y: 520), controlPoint2: NSPoint(x: 430, y: 520))
    body.close()
    fill(body, color(0xE0703A), color(0xA8361F))

    let wing = NSBezierPath()
    wing.move(to: NSPoint(x: 420, y: 455))
    wing.curve(to: NSPoint(x: 640, y: 420), controlPoint1: NSPoint(x: 470, y: 520), controlPoint2: NSPoint(x: 600, y: 520))
    wing.curve(to: NSPoint(x: 470, y: 330), controlPoint1: NSPoint(x: 640, y: 350), controlPoint2: NSPoint(x: 560, y: 310))
    wing.curve(to: NSPoint(x: 420, y: 455), controlPoint1: NSPoint(x: 420, y: 345), controlPoint2: NSPoint(x: 400, y: 410))
    wing.close()
    fill(wing, color(0xB8462A), color(0x7E2716))

    let head = NSBezierPath(ovalIn: NSRect(x: 560, y: 600, width: 190, height: 190))
    fill(head, color(0xE8823F), color(0xC4532A))

    color(0xE5332A).setFill()
    for (x, y, r) in [(600.0, 795.0, 44.0), (655.0, 822.0, 50.0), (712.0, 795.0, 42.0)] {
        NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
    }
    fill(NSBezierPath(ovalIn: NSRect(x: 690, y: 560, width: 58, height: 90)), color(0xF04A3A), color(0xC7251E))

    let eye = NSBezierPath(ovalIn: NSRect(x: 645, y: 690, width: 50, height: 50))
    NSColor.white.setFill()
    eye.fill()
    color(0x1F1A17).setFill()
    NSBezierPath(ovalIn: NSRect(x: 666, y: 702, width: 24, height: 26)).fill()
}

// Front layer: the letter held in the golden beak.
layer("letter.png") {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: 860, yBy: 590)
    transform.rotate(byDegrees: -14)
    transform.concat()
    let card = NSRect(x: -130, y: -95, width: 260, height: 180)
    fill(NSBezierPath(roundedRect: card, xRadius: 22, yRadius: 22), color(0xFFFFFF), color(0xE7EDF5))
    let flap = NSBezierPath()
    flap.move(to: NSPoint(x: card.minX + 14, y: card.maxY - 12))
    flap.line(to: NSPoint(x: 0, y: -5))
    flap.line(to: NSPoint(x: card.maxX - 14, y: card.maxY - 12))
    flap.lineWidth = 18
    flap.lineJoinStyle = .round
    flap.lineCapStyle = .round
    color(0x3F86D6).setStroke()
    flap.stroke()
    color(0xE5332A).setFill()
    NSBezierPath(roundedRect: NSRect(x: 72, y: 22, width: 38, height: 44), xRadius: 6, yRadius: 6).fill()
    NSGraphicsContext.restoreGraphicsState()

    let beak = NSBezierPath()
    beak.move(to: NSPoint(x: 735, y: 735))
    beak.line(to: NSPoint(x: 860, y: 690))
    beak.line(to: NSPoint(x: 738, y: 655))
    beak.close()
    fill(beak, color(0xFFC94A), color(0xEE9A1C))
}
print("Wrote tail.png, rooster.png, letter.png to \(output.path)")
