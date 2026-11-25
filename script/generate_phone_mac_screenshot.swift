#!/usr/bin/env swift
import AppKit
import Foundation

guard CommandLine.arguments.count == 3,
      let screenshot = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    fputs("usage: generate_phone_mac_screenshot.swift native-card-capture.png output.png\n", stderr)
    exit(1)
}
let width = 2880, height = 1800
let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let graphics = NSGraphicsContext(cgContext: context, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
NSGradient(starting: NSColor(srgbRed: 0.03, green: 0.06, blue: 0.12, alpha: 1),
           ending: NSColor(srgbRed: 0.08, green: 0.03, blue: 0.15, alpha: 1))!
    .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -20)
func text(_ value: String, y: CGFloat, size: CGFloat, color: NSColor, weight: NSFont.Weight) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    (value as NSString).draw(in: NSRect(x: 120, y: y, width: 2640, height: 130), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style])
}
text("From iPhone. Ready on Mac.", y: 1640, size: 96, color: .white, weight: .semibold)
text("Photos and text as cards. Drag, drop, or paste.", y: 1500, size: 46,
     color: NSColor(srgbRed: 0.72, green: 0.8, blue: 0.92, alpha: 1), weight: .regular)
let scale = min(2500 / screenshot.size.width, 1300 / screenshot.size.height)
let size = NSSize(width: screenshot.size.width * scale, height: screenshot.size.height * scale)
screenshot.draw(in: NSRect(x: (2880 - size.width) / 2, y: 140, width: size.width, height: size.height))
text("CaptureArc for Mac + the separate CaptureArc Sender app for iPhone", y: 5, size: 28,
     color: NSColor(srgbRed: 0.68, green: 0.73, blue: 0.85, alpha: 1), weight: .regular)
graphics.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
