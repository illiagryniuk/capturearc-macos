#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

private let canvas: CGFloat = 1_024

private let cyan = NSColor(srgbRed: 0.13, green: 0.82, blue: 0.93, alpha: 1)
private let indigo = NSColor(srgbRed: 0.39, green: 0.40, blue: 0.95, alpha: 1)
private let violet = NSColor(srgbRed: 0.49, green: 0.23, blue: 0.93, alpha: 1)

private func roundedPath(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

private func linearGradient(
    _ colors: [NSColor],
    locations: [CGFloat]
) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: colors.map(\.cgColor) as CFArray,
        locations: locations
    )!
}

private func drawGradientStroke(
    _ path: NSBezierPath,
    in context: CGContext,
    width: CGFloat,
    colors: [NSColor],
    locations: [CGFloat],
    from start: CGPoint,
    to end: CGPoint,
    alpha: CGFloat = 1
) {
    context.saveGState()
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addPath(path.cgPath)
    context.replacePathWithStrokedPath()
    context.clip()
    context.setAlpha(alpha)
    context.drawLinearGradient(
        linearGradient(colors, locations: locations),
        start: start,
        end: end,
        options: []
    )
    context.restoreGState()
}

private func drawIcon(in context: CGContext) {
    let backgroundRect = CGRect(x: 38, y: 38, width: 948, height: 948)
    let background = roundedPath(backgroundRect, radius: 218)

    context.saveGState()
    background.addClip()
    context.drawLinearGradient(
        linearGradient(
            [
                NSColor(srgbRed: 0.10, green: 0.12, blue: 0.22, alpha: 1),
                NSColor(srgbRed: 0.035, green: 0.045, blue: 0.10, alpha: 1),
                NSColor(srgbRed: 0.08, green: 0.035, blue: 0.16, alpha: 1)
            ],
            locations: [0, 0.58, 1]
        ),
        start: CGPoint(x: 120, y: 920),
        end: CGPoint(x: 900, y: 100),
        options: []
    )

    let ambient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [
            cyan.withAlphaComponent(0.22).cgColor,
            indigo.withAlphaComponent(0.08).cgColor,
            NSColor.clear.cgColor
        ] as CFArray,
        locations: [0, 0.42, 1]
    )!
    context.drawRadialGradient(
        ambient,
        startCenter: CGPoint(x: 360, y: 690),
        startRadius: 0,
        endCenter: CGPoint(x: 360, y: 690),
        endRadius: 560,
        options: []
    )
    context.restoreGState()

    background.lineWidth = 5
    NSColor.white.withAlphaComponent(0.13).setStroke()
    background.stroke()

    let flightPath = NSBezierPath()
    flightPath.move(to: CGPoint(x: 688, y: 438))
    flightPath.curve(
        to: CGPoint(x: 560, y: 716),
        controlPoint1: CGPoint(x: 720, y: 548),
        controlPoint2: CGPoint(x: 650, y: 662)
    )
    drawGradientStroke(
        flightPath,
        in: context,
        width: 54,
        colors: [cyan, indigo, violet],
        locations: [0, 0.5, 1],
        from: CGPoint(x: 730, y: 420),
        to: CGPoint(x: 520, y: 740),
        alpha: 0.18
    )
    drawGradientStroke(
        flightPath,
        in: context,
        width: 18,
        colors: [cyan, indigo, violet],
        locations: [0, 0.52, 1],
        from: CGPoint(x: 730, y: 420),
        to: CGPoint(x: 520, y: 740),
        alpha: 0.98
    )

    context.saveGState()
    context.translateBy(x: 700, y: 350)
    context.rotate(by: 8 * .pi / 180)

    let cardRect = CGRect(x: -174, y: -128, width: 348, height: 256)
    let card = roundedPath(cardRect, radius: 50)
    context.setShadow(
        offset: CGSize(width: 0, height: -20),
        blur: 34,
        color: NSColor.black.withAlphaComponent(0.48).cgColor
    )
    NSColor(srgbRed: 0.86, green: 0.89, blue: 1, alpha: 1).setFill()
    card.fill()
    context.setShadow(offset: .zero, blur: 0, color: nil)

    context.saveGState()
    card.addClip()
    context.drawLinearGradient(
        linearGradient(
            [
                NSColor.white,
                NSColor(srgbRed: 0.80, green: 0.84, blue: 0.98, alpha: 1)
            ],
            locations: [0, 1]
        ),
        start: CGPoint(x: -120, y: 120),
        end: CGPoint(x: 150, y: -100),
        options: []
    )
    context.restoreGState()

    card.lineWidth = 5
    NSColor.white.withAlphaComponent(0.72).setStroke()
    card.stroke()

    let previewRect = CGRect(x: -138, y: -90, width: 276, height: 176)
    let preview = roundedPath(previewRect, radius: 30)
    NSColor(srgbRed: 0.08, green: 0.10, blue: 0.18, alpha: 1).setFill()
    preview.fill()

    let previewWash = roundedPath(
        CGRect(x: -116, y: -30, width: 232, height: 86),
        radius: 22
    )
    context.saveGState()
    previewWash.addClip()
    context.drawLinearGradient(
        linearGradient(
            [cyan.withAlphaComponent(0.72), violet.withAlphaComponent(0.82)],
            locations: [0, 1]
        ),
        start: CGPoint(x: -116, y: 20),
        end: CGPoint(x: 116, y: 20),
        options: []
    )
    context.restoreGState()

    for (index, x) in [-104, -72, -40].enumerated() {
        let dot = NSBezierPath(ovalIn: CGRect(x: x, y: 60, width: 14, height: 14))
        [cyan, indigo, violet][index].setFill()
        dot.fill()
    }

    let detailLine = roundedPath(
        CGRect(x: -112, y: -68, width: 142, height: 12),
        radius: 6
    )
    NSColor.white.withAlphaComponent(0.68).setFill()
    detailLine.fill()

    let shortLine = roundedPath(
        CGRect(x: 42, y: -68, width: 72, height: 12),
        radius: 6
    )
    cyan.withAlphaComponent(0.92).setFill()
    shortLine.fill()
    context.restoreGState()

    let notch = NSBezierPath()
    notch.move(to: CGPoint(x: 330, y: 986))
    notch.line(to: CGPoint(x: 330, y: 796))
    notch.curve(
        to: CGPoint(x: 422, y: 700),
        controlPoint1: CGPoint(x: 330, y: 736),
        controlPoint2: CGPoint(x: 366, y: 700)
    )
    notch.line(to: CGPoint(x: 602, y: 700))
    notch.curve(
        to: CGPoint(x: 694, y: 796),
        controlPoint1: CGPoint(x: 658, y: 700),
        controlPoint2: CGPoint(x: 694, y: 736)
    )
    notch.line(to: CGPoint(x: 694, y: 986))
    notch.close()
    NSColor(srgbRed: 0.015, green: 0.018, blue: 0.035, alpha: 1).setFill()
    notch.fill()

    let rim = NSBezierPath()
    rim.move(to: CGPoint(x: 310, y: 958))
    rim.line(to: CGPoint(x: 310, y: 790))
    rim.curve(
        to: CGPoint(x: 414, y: 680),
        controlPoint1: CGPoint(x: 310, y: 722),
        controlPoint2: CGPoint(x: 350, y: 680)
    )
    rim.line(to: CGPoint(x: 610, y: 680))
    rim.curve(
        to: CGPoint(x: 714, y: 790),
        controlPoint1: CGPoint(x: 674, y: 680),
        controlPoint2: CGPoint(x: 714, y: 722)
    )
    rim.line(to: CGPoint(x: 714, y: 958))

    drawGradientStroke(
        rim,
        in: context,
        width: 58,
        colors: [cyan, indigo, violet],
        locations: [0, 0.52, 1],
        from: CGPoint(x: 300, y: 720),
        to: CGPoint(x: 724, y: 720),
        alpha: 0.18
    )
    drawGradientStroke(
        rim,
        in: context,
        width: 23,
        colors: [cyan, indigo, violet],
        locations: [0, 0.52, 1],
        from: CGPoint(x: 300, y: 720),
        to: CGPoint(x: 724, y: 720)
    )

    let entrySpark = NSBezierPath(ovalIn: CGRect(x: 536, y: 690, width: 48, height: 48))
    context.setShadow(offset: .zero, blur: 20, color: cyan.withAlphaComponent(0.9).cgColor)
    NSColor.white.withAlphaComponent(0.96).setFill()
    entrySpark.fill()
    context.setShadow(offset: .zero, blur: 0, color: nil)
}

private func renderIcon(pixelSize: Int) throws -> Data {
    let size = CGFloat(pixelSize)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ),
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    bitmap.size = CGSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics

    let context = graphics.cgContext
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    context.scaleBy(x: size / canvas, y: size / canvas)
    drawIcon(in: context)
    graphics.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data
}

private let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
private let iconset = root.appendingPathComponent("Resources/AppIcon.iconset", isDirectory: true)
private let brand = root.appendingPathComponent("Resources/Brand", isDirectory: true)

try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: brand, withIntermediateDirectories: true)

let outputs: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (pixelSize, filename) in outputs {
    try renderIcon(pixelSize: pixelSize).write(to: iconset.appendingPathComponent(filename))
}

try renderIcon(pixelSize: 1_024).write(
    to: brand.appendingPathComponent("CaptureArc-AppStore-1024.png")
)

print("Generated CaptureArc icon assets in \(iconset.path)")
