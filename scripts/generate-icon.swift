#!/usr/bin/env swift
//
// generate-icon.swift — LabForge（研铸）app icon generator
//
// Renders the LabForge .icns app icon entirely in code using only
// Foundation + AppKit + CoreGraphics (zero third-party dependencies).
//
// Usage:
//   swift scripts/generate-icon.swift [output.icns] [--preview /path/to/preview.png]
//
//   output.icns    Path of the .icns to write (default: dist/AppIcon.icns)
//   --preview      Also save the 1024x1024 PNG master to the given path.
//
// Design: strictly follows the Claude Editorial Design System (DESIGN.md) —
// a warm cream paper squircle (#FAF9F5 → #EFE9DE) with a 1px hairline
// border (#E6DFD8), a subtle warm drop shadow, and a razor-sharp terracotta
// coral (#CC785C → #A9583E) radial editorial spark emblem with a warm ink
// (#141413) crucible anvil and an amber (#E8A55A) micro-accent.
//

import AppKit
import CoreGraphics
import Foundation

// MARK: - CLI

let arguments = CommandLine.arguments

var outputPath = "dist/AppIcon.icns"
var previewPath: String? = nil

var index = 1
while index < arguments.count {
    let arg = arguments[index]
    switch arg {
    case "--preview":
        index += 1
        guard index < arguments.count else {
            filePrint("--preview requires a path argument")
            exit(2)
        }
        previewPath = arguments[index]
    case "--help", "-h":
        print("Usage: generate-icon.swift [output.icns] [--preview /path/to/preview.png]")
        exit(0)
    default:
        if arg.hasPrefix("--") {
            filePrint("Unknown flag: \(arg)")
            exit(2)
        }
        outputPath = arg
    }
    index += 1
}

func filePrint(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8) ?? Data())
}

// MARK: - Palette (DESIGN.md — Claude Editorial)

struct Palette {
    static let space = CGColorSpaceCreateDeviceRGB()
    private static func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
        CGColor(colorSpace: space, components: [r / 255.0, g / 255.0, b / 255.0, a])!
    }

    static let canvasTop        = rgba(0xFA, 0xF9, 0xF5)         // #FAF9F5
    static let canvasBottom     = rgba(0xEF, 0xE9, 0xDE)         // #EFE9DE
    static let hairline         = rgba(0xE6, 0xDF, 0xD8)         // #E6DFD8
    static let ink              = rgba(0x14, 0x14, 0x13)         // #141413
    static let coral            = rgba(0xCC, 0x78, 0x5C)         // #CC785C
    static let coralDeep        = rgba(0xA9, 0x58, 0x3E)         // #A9583E
    static let amber            = rgba(0xE8, 0xA5, 0x5A)         // #E8A55A
    static let shadow           = rgba(0x14, 0x14, 0x13, 0.10)   // warm whisper shadow
}

// MARK: - Geometry (1024pt design space)

// macOS Big Sur+ icon grid: 1024×1024 canvas, ~824pt rounded-rect body
// centered with ~100pt margins, continuous corner radius ≈ 18.5% of body.
let canvasSize: CGFloat = 1024
let bodyRect = CGRect(x: (canvasSize - 824) / 2, y: (canvasSize - 824) / 2, width: 824, height: 824)
let bodyRadius = bodyRect.width * 0.185

// MARK: - Master 1024 render

func makeMasterImage() -> NSImage {
    let image = NSImage(size: NSSize(width: canvasSize, height: canvasSize))
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let context = NSGraphicsContext.current?.cgContext else {
        filePrint("fatal: no graphics context")
        exit(1)
    }
    context.interpolationQuality = .high
    context.setShouldAntialias(true)

    drawSquircle(context: context)
    drawEmblem(context: context)
    return image
}

/// Warm cream paper squircle with subtle warm drop shadow, vertical paper
/// gradient (#FAF9F5 → #EFE9DE) and a crisp 1pt-equivalent hairline border.
func drawSquircle(context: CGContext) {
    // Soft warm drop shadow behind the body (whisper-subtle, per DESIGN.md).
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -14),
        blur: 36,
        color: Palette.shadow
    )
    let shadowPath = CGPath(roundedRect: bodyRect, cornerWidth: bodyRadius, cornerHeight: bodyRadius, transform: nil)
    context.addPath(shadowPath)
    context.setFillColor(Palette.canvasTop)
    context.fillPath()
    context.restoreGState()

    // Paper gradient body (top #FAF9F5 → bottom #EFE9DE).
    let bodyPath = CGPath(roundedRect: bodyRect, cornerWidth: bodyRadius, cornerHeight: bodyRadius, transform: nil)
    context.saveGState()
    context.addPath(bodyPath)
    context.clip()
    if let gradient = CGGradient(colorsSpace: Palette.space,
                                 colors: [Palette.canvasTop, Palette.canvasBottom] as CFArray,
                                 locations: [0, 1]) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: bodyRect.midX, y: bodyRect.maxY),
            end: CGPoint(x: bodyRect.midX, y: bodyRect.minY),
            options: []
        )
    }
    context.restoreGState()

    // Crisp 1px-equivalent warm hairline inner border.
    context.saveGState()
    let borderRect = bodyRect.insetBy(dx: 1, dy: 1)
    let borderPath = CGPath(roundedRect: borderRect,
                            cornerWidth: bodyRadius - 1,
                            cornerHeight: bodyRadius - 1,
                            transform: nil)
    context.addPath(borderPath)
    context.setStrokeColor(Palette.hairline)
    context.setLineWidth(2) // 2pt at 1024 ≈ 1px-equivalent at typical display sizes
    context.strokePath()
    context.restoreGState()
}

/// All emblem coordinates are bottom-up in the 1024-point design space.
func drawEmblem(context: CGContext) {
    let flask = CGMutablePath()
    flask.move(to: CGPoint(x: 458, y: 510))
    flask.addLine(to: CGPoint(x: 566, y: 510))
    flask.addLine(to: CGPoint(x: 566, y: 429))
    flask.addLine(to: CGPoint(x: 674, y: 305))
    flask.addCurve(to: CGPoint(x: 639, y: 236),
                   control1: CGPoint(x: 700, y: 272), control2: CGPoint(x: 676, y: 236))
    flask.addLine(to: CGPoint(x: 385, y: 236))
    flask.addCurve(to: CGPoint(x: 350, y: 305),
                   control1: CGPoint(x: 348, y: 236), control2: CGPoint(x: 324, y: 272))
    flask.addLine(to: CGPoint(x: 458, y: 429))
    flask.closeSubpath()

    context.addPath(flask)
    context.setFillColor(Palette.ink)
    context.fillPath()
    context.addPath(CGPath(roundedRect: CGRect(x: 432, y: 489, width: 160, height: 28),
                           cornerWidth: 12, cornerHeight: 12, transform: nil))
    context.fillPath()

    let liquid = CGMutablePath()
    liquid.move(to: CGPoint(x: 414, y: 337))
    liquid.addCurve(to: CGPoint(x: 610, y: 337),
                    control1: CGPoint(x: 475, y: 321), control2: CGPoint(x: 554, y: 354))
    liquid.addLine(to: CGPoint(x: 651, y: 286))
    liquid.addQuadCurve(to: CGPoint(x: 634, y: 265), control: CGPoint(x: 660, y: 265))
    liquid.addLine(to: CGPoint(x: 390, y: 265))
    liquid.addQuadCurve(to: CGPoint(x: 373, y: 286), control: CGPoint(x: 364, y: 265))
    liquid.closeSubpath()
    context.addPath(liquid)
    context.setFillColor(Palette.coral)
    context.fillPath()

    let center = CGPoint(x: 512, y: 655)
    context.saveGState()
    context.addPath(sparkPath(center: center, lengths: [133, 93, 137, 92, 133, 96, 114, 92], halfWidth: 24))
    context.clip()
    if let gradient = CGGradient(colorsSpace: Palette.space,
                                 colors: [Palette.coral, Palette.coralDeep] as CFArray,
                                 locations: nil) {
        context.drawLinearGradient(gradient, start: CGPoint(x: center.x, y: 792),
                                   end: CGPoint(x: center.x, y: 541), options: [])
    }
    context.restoreGState()

    context.addPath(sparkPath(center: CGPoint(x: 691, y: 765), lengths: [38, 43, 38, 43], halfWidth: 12))
    context.setFillColor(Palette.amber)
    context.fillPath()
}

/// Concave wedges give each ray a broad root and a tapered tip.
func sparkPath(center: CGPoint, lengths: [CGFloat], halfWidth: CGFloat) -> CGPath {
    let path = CGMutablePath()
    for (index, length) in lengths.enumerated() {
        let angle = CGFloat(index) * 2 * .pi / CGFloat(lengths.count)
        func point(_ distance: CGFloat, _ offset: CGFloat) -> CGPoint {
            CGPoint(x: center.x + cos(angle) * distance - sin(angle) * offset,
                    y: center.y + sin(angle) * distance + cos(angle) * offset)
        }
        path.move(to: point(-halfWidth, -halfWidth))
        path.addQuadCurve(to: point(length, 0), control: point(length * 0.55, -halfWidth))
        path.addQuadCurve(to: point(-halfWidth, halfWidth), control: point(length * 0.55, halfWidth))
        path.closeSubpath()
    }
    return path
}

// MARK: - PNG export

func writePNG(from image: NSImage, to path: String, pixelSize: Int) -> Bool {
    let target = NSSize(width: pixelSize, height: pixelSize)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: pixelSize,
                               pixelsHigh: pixelSize,
                               bitsPerSample: 8,
                               samplesPerPixel: 4,
                               hasAlpha: true,
                               isPlanar: false,
                               colorSpaceName: .deviceRGB,
                               bytesPerRow: 0,
                               bitsPerPixel: 0)
    guard let rep else {
        filePrint("failed to allocate bitmap for \(path)")
        return false
    }

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current = context
    context?.cgContext.interpolationQuality = .high
    image.draw(in: CGRect(origin: .zero, size: target),
               from: .zero,
               operation: .copy,
               fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        filePrint("failed to encode PNG for \(path)")
        return false
    }
    let dir = (path as NSString).deletingLastPathComponent
    if !dir.isEmpty {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        return true
    } catch {
        filePrint("failed to write \(path): \(error)")
        return false
    }
}

// MARK: - Main

func generateIcon(outputPath: String, previewPath: String?) throws {
    let master = makeMasterImage()
    let fm = FileManager.default
    let output = URL(fileURLWithPath: outputPath)
    try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

    let tempDir = fm.temporaryDirectory.appendingPathComponent("labforge-icon-\(UUID())")
    let iconset = tempDir.appendingPathComponent("AppIcon.iconset")
    defer { try? fm.removeItem(at: tempDir) }
    try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let suffix = scale == 2 ? "@2x" : ""
            let path = iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png").path
            guard writePNG(from: master, to: path, pixelSize: size * scale) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
    }

    let stagedIcon = tempDir.appendingPathComponent("AppIcon.icns")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", "-o", stagedIcon.path, iconset.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "iconutil exited with \(process.terminationStatus)"])
    }
    let iconData = try Data(contentsOf: stagedIcon)
    guard !iconData.isEmpty else { throw CocoaError(.fileWriteUnknown) }
    try iconData.write(to: output, options: .atomic)
    print("App icon written: \(outputPath) (\(iconData.count) bytes, 10 iconset sizes)")

    if let previewPath {
        guard writePNG(from: master, to: previewPath, pixelSize: 1024) else {
            throw CocoaError(.fileWriteUnknown)
        }
        print("Preview written: \(previewPath)")
    }
}

do {
    try generateIcon(outputPath: outputPath, previewPath: previewPath)
} catch {
    filePrint(error.localizedDescription)
    exit(1)
}
