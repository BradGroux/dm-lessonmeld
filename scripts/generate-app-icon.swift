#!/usr/bin/env swift
import AppKit
import Foundation

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let packagingURL = rootURL.appendingPathComponent("Packaging", isDirectory: true)
let buildURL = rootURL.appendingPathComponent(".build/icon-work", isDirectory: true)
let iconsetURL = buildURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)

try FileManager.default.createDirectory(at: packagingURL, withIntermediateDirectories: true)
if FileManager.default.fileExists(atPath: iconsetURL.path) {
    try FileManager.default.removeItem(at: iconsetURL)
}
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

func roundedPath(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func fill(_ path: NSBezierPath, with fillColor: NSColor) {
    fillColor.setFill()
    path.fill()
}

func stroke(_ path: NSBezierPath, with strokeColor: NSColor, width: CGFloat) {
    strokeColor.setStroke()
    path.lineWidth = width
    path.stroke()
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let scale = size / 1024
    func s(_ value: CGFloat) -> CGFloat { value * scale }
    func r(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(x: s(x), y: s(y), width: s(width), height: s(height))
    }

    let canvas = CGRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    canvas.fill()

    let shell = roundedPath(r(72, 72, 880, 880), radius: s(220))
    NSGraphicsContext.current?.cgContext.saveGState()
    shell.addClip()
    NSGradient(colors: [color(0x15161b), color(0x241a35), color(0x111216)])?.draw(in: shell, angle: 135)

    fill(roundedPath(r(130, 165, 365, 220), radius: s(84)), with: color(0x7c3aed, alpha: 0.28))
    fill(roundedPath(r(560, 655, 250, 170), radius: s(76)), with: color(0x22d3ee, alpha: 0.18))
    fill(roundedPath(r(675, 170, 185, 185), radius: s(92)), with: color(0xff3b30, alpha: 0.18))

    let screen = roundedPath(r(190, 270, 644, 420), radius: s(58))
    fill(screen, with: color(0x22252d, alpha: 0.94))
    stroke(screen, with: color(0xffffff, alpha: 0.84), width: s(18))

    stroke(roundedPath(r(250, 595, 360, 1), radius: s(1)), with: color(0xffffff, alpha: 0.42), width: s(14))
    stroke(roundedPath(r(250, 515, 260, 1), radius: s(1)), with: color(0xffffff, alpha: 0.30), width: s(14))
    stroke(roundedPath(r(250, 440, 390, 1), radius: s(1)), with: color(0xffffff, alpha: 0.22), width: s(14))

    let cursor = NSBezierPath()
    cursor.move(to: NSPoint(x: s(600), y: s(552)))
    cursor.line(to: NSPoint(x: s(728), y: s(438)))
    cursor.line(to: NSPoint(x: s(650), y: s(424)))
    cursor.line(to: NSPoint(x: s(690), y: s(338)))
    cursor.line(to: NSPoint(x: s(642), y: s(318)))
    cursor.line(to: NSPoint(x: s(604), y: s(404)))
    cursor.line(to: NSPoint(x: s(542), y: s(350)))
    cursor.close()
    fill(cursor, with: color(0xffffff, alpha: 0.94))
    stroke(cursor, with: color(0x111216, alpha: 0.65), width: s(8))

    let webcam = roundedPath(r(640, 520, 135, 135), radius: s(68))
    fill(webcam, with: color(0xa855f7))
    stroke(webcam, with: color(0xffffff, alpha: 0.86), width: s(12))
    fill(roundedPath(r(682, 562, 50, 50), radius: s(25)), with: color(0xffffff, alpha: 0.88))

    let marker = NSBezierPath()
    marker.lineCapStyle = .round
    marker.lineJoinStyle = .round
    marker.move(to: NSPoint(x: s(275), y: s(365)))
    marker.curve(
        to: NSPoint(x: s(515), y: s(370)),
        controlPoint1: NSPoint(x: s(340), y: s(300)),
        controlPoint2: NSPoint(x: s(442), y: s(450))
    )
    stroke(marker, with: color(0xffd733), width: s(28))

    fill(roundedPath(r(684, 214, 142, 142), radius: s(71)), with: color(0xff3b30))
    stroke(roundedPath(r(684, 214, 142, 142), radius: s(71)), with: color(0xffffff, alpha: 0.84), width: s(12))
    fill(roundedPath(r(724, 254, 62, 62), radius: s(31)), with: color(0xffffff, alpha: 0.95))

    NSGraphicsContext.current?.cgContext.restoreGState()
    stroke(shell, with: color(0xffffff, alpha: 0.18), width: s(10))

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let data = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "IconGeneration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render PNG data."])
    }
    try data.write(to: url, options: .atomic)
}

let preview = drawIcon(size: 1024)
try writePNG(preview, to: packagingURL.appendingPathComponent("AppIcon.png"))

let entries: [(name: String, size: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for entry in entries {
    try writePNG(drawIcon(size: entry.size), to: iconsetURL.appendingPathComponent(entry.name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c",
    "icns",
    iconsetURL.path,
    "-o",
    packagingURL.appendingPathComponent("AppIcon.icns").path
]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: "IconGeneration", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed."])
}

print(packagingURL.appendingPathComponent("AppIcon.icns").path)
