#!/usr/bin/env swift

import AppKit
import Foundation

let fileManager = FileManager.default
let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let sourceURL = rootURL.appendingPathComponent("release/AppStore/source-captures", isDirectory: true)
let outputURL = rootURL.appendingPathComponent("release/AppStore/screenshots", isDirectory: true)

try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)

guard
    let shelf = NSImage(contentsOf: sourceURL.appendingPathComponent("shelf-expanded.png")),
    let settings = NSImage(contentsOf: sourceURL.appendingPathComponent("settings.png")),
    let rim = NSImage(contentsOf: sourceURL.appendingPathComponent("notch-rim.png")),
    let icon = NSImage(contentsOf: rootURL.appendingPathComponent("Resources/Brand/CaptureArc-AppStore-1024.png"))
else {
    fputs("Missing source captures. Run the live CaptureArc QA capture first.\n", stderr)
    exit(1)
}

let canvasSize = NSSize(width: 2880, height: 1800)
let white = NSColor(calibratedWhite: 0.97, alpha: 1)
let secondary = NSColor(calibratedRed: 0.72, green: 0.76, blue: 0.86, alpha: 1)
let cyan = NSColor(calibratedRed: 0.16, green: 0.84, blue: 1.0, alpha: 1)
let violet = NSColor(calibratedRed: 0.55, green: 0.27, blue: 1.0, alpha: 1)

func drawBackground() {
    NSGradient(colors: [
        NSColor(calibratedRed: 0.025, green: 0.035, blue: 0.085, alpha: 1),
        NSColor(calibratedRed: 0.055, green: 0.035, blue: 0.115, alpha: 1),
        NSColor(calibratedRed: 0.018, green: 0.025, blue: 0.055, alpha: 1)
    ])!.draw(in: NSRect(origin: .zero, size: canvasSize), angle: -18)

    let glow = NSGradient(colorsAndLocations:
        (NSColor(calibratedRed: 0.10, green: 0.72, blue: 1, alpha: 0.22), 0),
        (NSColor(calibratedRed: 0.30, green: 0.23, blue: 0.95, alpha: 0.08), 0.55),
        (NSColor.clear, 1)
    )!
    glow.draw(fromCenter: NSPoint(x: 250, y: 1650), radius: 0, toCenter: NSPoint(x: 250, y: 1650), radius: 980, options: [])

    let secondGlow = NSGradient(colorsAndLocations:
        (NSColor(calibratedRed: 0.48, green: 0.18, blue: 1, alpha: 0.18), 0),
        (NSColor.clear, 1)
    )!
    secondGlow.draw(fromCenter: NSPoint(x: 2800, y: 160), radius: 0, toCenter: NSPoint(x: 2800, y: 160), radius: 900, options: [])
}

func drawText(
    _ text: String,
    in rect: NSRect,
    size: CGFloat,
    color: NSColor,
    weight: NSFont.Weight = .regular,
    alignment: NSTextAlignment = .left,
    lineSpacing: CGFloat = 4
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineSpacing = lineSpacing
    paragraph.lineBreakMode = .byWordWrapping
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
}

func aspectFit(_ size: NSSize, in bounds: NSRect) -> NSRect {
    let scale = min(bounds.width / size.width, bounds.height / size.height)
    let output = NSSize(width: size.width * scale, height: size.height * scale)
    return NSRect(
        x: bounds.midX - output.width / 2,
        y: bounds.midY - output.height / 2,
        width: output.width,
        height: output.height
    )
}

func drawRoundedImage(_ image: NSImage, in bounds: NSRect, radius: CGFloat, border: Bool = true) {
    let rect = aspectFit(image.size, in: bounds)
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.72)
    shadow.shadowBlurRadius = 52
    shadow.shadowOffset = NSSize(width: 0, height: -22)
    shadow.set()
    NSColor(calibratedWhite: 0.02, alpha: 1).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    if border {
        NSGradient(colors: [cyan.withAlphaComponent(0.75), violet.withAlphaComponent(0.8)])!
            .draw(in: path, angle: 0)
        let inset = rect.insetBy(dx: 3, dy: 3)
        let inner = NSBezierPath(roundedRect: inset, xRadius: max(0, radius - 3), yRadius: max(0, radius - 3))
        NSColor(calibratedRed: 0.03, green: 0.04, blue: 0.09, alpha: 1).setFill()
        inner.fill()
        NSGraphicsContext.saveGraphicsState()
        inner.addClip()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }
}

func drawBrandHeader() {
    let iconRect = NSRect(x: 155, y: 1578, width: 90, height: 90)
    let path = NSBezierPath(roundedRect: iconRect, xRadius: 22, yRadius: 22)
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    icon.draw(in: iconRect)
    NSGraphicsContext.restoreGraphicsState()
    drawText("CaptureArc", in: NSRect(x: 270, y: 1596, width: 500, height: 60), size: 42, color: white, weight: .semibold)
}

func drawAccentLine(x: CGFloat, y: CGFloat, width: CGFloat) {
    let path = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: 12), xRadius: 6, yRadius: 6)
    NSGradient(colors: [cyan, violet])!.draw(in: path, angle: 0)
}

func drawChip(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat) {
    let rect = NSRect(x: x, y: y, width: width, height: 92)
    let path = NSBezierPath(roundedRect: rect, xRadius: 46, yRadius: 46)
    NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.22, alpha: 0.96).setFill()
    path.fill()
    NSColor(calibratedRed: 0.29, green: 0.34, blue: 0.55, alpha: 0.7).setStroke()
    path.lineWidth = 2
    path.stroke()
    drawText(text, in: rect.insetBy(dx: 28, dy: 21), size: 34, color: white, weight: .medium, alignment: .center)
}

func drawStep(_ number: String, title: String, body: String, y: CGFloat) {
    let circleRect = NSRect(x: 180, y: y + 40, width: 82, height: 82)
    let circle = NSBezierPath(ovalIn: circleRect)
    NSGradient(colors: [cyan, violet])!.draw(in: circle, angle: -20)
    drawText(number, in: NSRect(x: 180, y: y + 58, width: 82, height: 52), size: 36, color: .white, weight: .bold, alignment: .center)
    drawText(title, in: NSRect(x: 300, y: y + 70, width: 820, height: 62), size: 42, color: white, weight: .semibold)
    drawText(body, in: NSRect(x: 300, y: y - 10, width: 820, height: 82), size: 30, color: secondary, lineSpacing: 7)
}

func render(name: String, draw: () -> Void) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasSize.width),
        pixelsHigh: Int(canvasSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { throw CocoaError(.fileWriteUnknown) }

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        throw CocoaError(.fileWriteUnknown)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    drawBackground()
    draw()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: outputURL.appendingPathComponent(name), options: .atomic)
}

try render(name: "01-screenshot-shelf.png") {
    drawBrandHeader()
    drawText("Your screenshots,\nright at the notch.", in: NSRect(x: 155, y: 1010, width: 920, height: 420), size: 104, color: white, weight: .bold, lineSpacing: -2)
    drawAccentLine(x: 160, y: 960, width: 310)
    drawText("A native shelf keeps every new capture one hover away.", in: NSRect(x: 160, y: 720, width: 790, height: 190), size: 43, color: secondary, lineSpacing: 10)
    drawRoundedImage(shelf, in: NSRect(x: 1080, y: 180, width: 1660, height: 1190), radius: 56)
}

try render(name: "02-compact-until-needed.png") {
    drawBrandHeader()
    drawText("Quiet when you’re working.\nReady when you need it.", in: NSRect(x: 330, y: 1270, width: 2220, height: 280), size: 92, color: white, weight: .bold, alignment: .center, lineSpacing: 2)
    drawRoundedImage(rim, in: NSRect(x: 1010, y: 1110, width: 860, height: 175), radius: 38, border: false)
    drawText("A subtle color rim hugs the notch—without leaving an empty shelf on screen.", in: NSRect(x: 515, y: 970, width: 1850, height: 100), size: 39, color: secondary, alignment: .center)
    drawRoundedImage(shelf, in: NSRect(x: 670, y: 90, width: 1540, height: 900), radius: 48)
}

try render(name: "03-private-by-design.png") {
    drawBrandHeader()
    drawText("Private by design.", in: NSRect(x: 160, y: 1230, width: 1120, height: 160), size: 100, color: white, weight: .bold)
    drawAccentLine(x: 165, y: 1180, width: 260)
    drawText("CaptureArc watches only the folder you approve. Your files stay on your Mac.", in: NSRect(x: 165, y: 950, width: 1000, height: 190), size: 43, color: secondary, lineSpacing: 10)
    drawChip("No screen recording", x: 165, y: 760, width: 650)
    drawChip("No account", x: 165, y: 640, width: 420)
    drawChip("No cloud upload", x: 165, y: 520, width: 540)
    drawRoundedImage(settings, in: NSRect(x: 1380, y: 100, width: 1300, height: 1460), radius: 58)
}

try render(name: "04-drag-share-clean-up.png") {
    drawBrandHeader()
    drawText("From snap to done, faster.", in: NSRect(x: 310, y: 1370, width: 2260, height: 140), size: 94, color: white, weight: .bold, alignment: .center)
    drawText("Drag into any app, use the native share sheet, or clean up when you’re finished.", in: NSRect(x: 450, y: 1270, width: 1980, height: 82), size: 38, color: secondary, alignment: .center)
    drawRoundedImage(shelf, in: NSRect(x: 490, y: 225, width: 1900, height: 990), radius: 58)
    drawChip("Drag", x: 660, y: 80, width: 330)
    drawChip("Share", x: 1030, y: 80, width: 350)
    drawChip("Copy", x: 1420, y: 80, width: 330)
    drawChip("Trash", x: 1790, y: 80, width: 360)
}

try render(name: "05-setup-in-a-minute.png") {
    drawBrandHeader()
    drawText("Set up in a minute.", in: NSRect(x: 165, y: 1330, width: 1040, height: 150), size: 96, color: white, weight: .bold)
    drawAccentLine(x: 170, y: 1280, width: 270)
    drawStep("1", title: "Authorize one folder", body: "Choose exactly where CaptureArc may look.", y: 950)
    drawStep("2", title: "Point macOS there", body: "Use Shift–Command–5 → Options → Save to.", y: 690)
    drawStep("3", title: "Take a screenshot", body: "CaptureArc handles the rest automatically.", y: 430)
    drawRoundedImage(settings, in: NSRect(x: 1430, y: 100, width: 1280, height: 1480), radius: 58)
}

print("Generated five 2880×1800 App Store screenshots in \(outputURL.path)")
