import AppKit
import SwiftUI

/// Shared visual tokens for the capture shelf. The shelf intentionally keeps a
/// dark spatial character while relying on native materials and semantic text
/// colors for contrast and accessibility.
enum NotchShelfTheme {
    static let collapsedCornerRadius: CGFloat = 18
    static let expandedCornerRadius: CGFloat = 26
    static let cardCornerRadius: CGFloat = 12
    static let evenOddFill = FillStyle(eoFill: true, antialiased: true)

    static let accentColors: [Color] = [
        Color(red: 0.13, green: 0.82, blue: 0.93),
        Color(red: 0.39, green: 0.40, blue: 0.95),
        Color(red: 0.49, green: 0.23, blue: 0.93)
    ]

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: accentColors,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static var spatialTint: LinearGradient {
        LinearGradient(
            colors: [
                Color.black.opacity(0.56),
                Color.black.opacity(0.78),
                Color.black.opacity(0.66)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func accentWash(opacity: Double) -> LinearGradient {
        LinearGradient(
            colors: accentColors.map { $0.opacity(opacity) },
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static let selectionBorderColor = NSColor.systemCyan
}

/// A material surface with an even-odd cutout that leaves the physical camera
/// housing untouched. The cutout starts just above the panel so no rounded top
/// edge can accidentally paint across the camera area; only its bottom corners
/// are rounded to follow the shape of modern MacBook notches.
struct NotchShelfSurfaceShape: Shape {
    var cutoutSize: CGSize
    var outerCornerRadius: CGFloat
    var hasPhysicalNotch: Bool

    func path(in rect: CGRect) -> Path {
        let radius = min(
            max(0, outerCornerRadius),
            min(rect.width, rect.height) / 2
        )
        var path = Path(
            roundedRect: rect,
            cornerRadius: radius,
            style: .continuous
        )

        guard hasPhysicalNotch,
              cutoutSize.width > 0,
              cutoutSize.height > 0 else {
            return path
        }

        let cutout = Self.cutoutRect(in: rect, cutoutSize: cutoutSize)
        let bottomRadius = min(13, min(cutout.width / 2, cutout.height / 2))

        path.move(to: CGPoint(x: cutout.minX, y: cutout.minY))
        path.addLine(to: CGPoint(x: cutout.maxX, y: cutout.minY))
        path.addLine(to: CGPoint(x: cutout.maxX, y: cutout.maxY - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: cutout.maxX - bottomRadius, y: cutout.maxY),
            control: CGPoint(x: cutout.maxX, y: cutout.maxY)
        )
        path.addLine(to: CGPoint(x: cutout.minX + bottomRadius, y: cutout.maxY))
        path.addQuadCurve(
            to: CGPoint(x: cutout.minX, y: cutout.maxY - bottomRadius),
            control: CGPoint(x: cutout.minX, y: cutout.maxY)
        )
        path.closeSubpath()
        return path
    }

    static func cutoutRect(in bounds: CGRect, cutoutSize: CGSize) -> CGRect {
        let width = min(max(0, cutoutSize.width), bounds.width)
        let height = min(max(0, cutoutSize.height), bounds.height)
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.minY - 1,
            width: width,
            height: height + 1
        )
    }
}

/// The idle affordance is intentionally only a stroked path. Its surrounding
/// window remains large enough for reliable hover and click interaction, while
/// every pixel away from this rim stays transparent.
struct NotchShelfIdleRimShape: Shape {
    var cutoutSize: CGSize
    var hasPhysicalNotch: Bool

    func path(in rect: CGRect) -> Path {
        guard hasPhysicalNotch,
              cutoutSize.width > 0,
              cutoutSize.height > 0 else {
            return fallbackPath(in: rect)
        }

        let rim = Self.rimRect(in: rect, cutoutSize: cutoutSize)
        let bottomRadius = min(13, min(rim.width / 2, rim.height / 2))
        var path = Path()
        path.move(to: CGPoint(x: rim.minX, y: rim.minY))
        path.addLine(to: CGPoint(x: rim.minX, y: rim.maxY - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: rim.minX + bottomRadius, y: rim.maxY),
            control: CGPoint(x: rim.minX, y: rim.maxY)
        )
        path.addLine(to: CGPoint(x: rim.maxX - bottomRadius, y: rim.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rim.maxX, y: rim.maxY - bottomRadius),
            control: CGPoint(x: rim.maxX, y: rim.maxY)
        )
        path.addLine(to: CGPoint(x: rim.maxX, y: rim.minY))
        return path
    }

    static func rimRect(in bounds: CGRect, cutoutSize: CGSize) -> CGRect {
        let cutout = NotchShelfSurfaceShape.cutoutRect(
            in: bounds,
            cutoutSize: cutoutSize
        )
        let top = bounds.minY + 0.75
        return CGRect(
            x: cutout.minX,
            y: top,
            width: cutout.width,
            height: max(0, cutout.maxY - top)
        )
    }

    private func fallbackPath(in rect: CGRect) -> Path {
        let width = min(72, max(0, rect.width - 24))
        let y = rect.minY + 2
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - width / 2, y: y))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX + width / 2, y: y),
            control: CGPoint(x: rect.midX, y: y + 3)
        )
        return path
    }
}
