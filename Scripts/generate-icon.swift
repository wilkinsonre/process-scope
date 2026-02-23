#!/usr/bin/env swift
// generate-icon.swift — Generates ProcessScope app icon at all macOS sizes
// Usage: swift Scripts/generate-icon.swift
//
// Design: A 2x2 grid of tracking dials (gauge arcs) on a smooth dark gradient
// background with rounded-rect macOS icon shape. Clean, symbol-based, Apple-style.

import AppKit
import CoreGraphics

// MARK: - Icon Sizes

struct IconVariant {
    let size: Int      // Point size
    let scale: Int     // 1x or 2x
    var pixelSize: Int { size * scale }
    var filename: String { "icon_\(size)x\(size)@\(scale)x.png" }
}

let variants: [IconVariant] = [
    IconVariant(size: 16, scale: 1),
    IconVariant(size: 16, scale: 2),
    IconVariant(size: 32, scale: 1),
    IconVariant(size: 32, scale: 2),
    IconVariant(size: 128, scale: 1),
    IconVariant(size: 128, scale: 2),
    IconVariant(size: 256, scale: 1),
    IconVariant(size: 256, scale: 2),
    IconVariant(size: 512, scale: 1),
    IconVariant(size: 512, scale: 2),
]

// MARK: - Drawing

func drawIcon(pixelSize: Int) -> NSImage {
    let size = CGFloat(pixelSize)
    let image = NSImage(size: NSSize(width: size, height: size))

    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // --- Background: smooth dark gradient ---
    let cornerRadius = size * 0.22 // macOS icon corner radius ratio
    let bgPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors: [CGColor] = [
        CGColor(red: 0.11, green: 0.11, blue: 0.16, alpha: 1.0), // Deep charcoal-blue
        CGColor(red: 0.07, green: 0.07, blue: 0.11, alpha: 1.0), // Near-black
    ]
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors as CFArray, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: size / 2, y: size), end: CGPoint(x: size / 2, y: 0), options: [])
    }

    // --- Subtle inner glow ---
    let glowInset = size * 0.04
    let glowRect = rect.insetBy(dx: glowInset, dy: glowInset)
    let glowPath = CGPath(roundedRect: glowRect, cornerWidth: cornerRadius - glowInset, cornerHeight: cornerRadius - glowInset, transform: nil)
    ctx.addPath(glowPath)
    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.06))
    ctx.setLineWidth(size * 0.01)
    ctx.strokePath()

    // --- 2x2 Grid of Gauge Dials ---
    let padding = size * 0.18
    let spacing = size * 0.06
    let cellSize = (size - padding * 2 - spacing) / 2

    // Gauge parameters: each has a different fill level and accent color
    struct GaugeSpec {
        let fillRatio: CGFloat
        let color: CGColor
    }

    let gauges: [GaugeSpec] = [
        GaugeSpec(fillRatio: 0.72, color: CGColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 1.0)),  // Cyan (CPU)
        GaugeSpec(fillRatio: 0.45, color: CGColor(red: 0.38, green: 0.87, blue: 0.52, alpha: 1.0)),  // Green (Memory)
        GaugeSpec(fillRatio: 0.88, color: CGColor(red: 1.00, green: 0.62, blue: 0.25, alpha: 1.0)),  // Orange (Power)
        GaugeSpec(fillRatio: 0.30, color: CGColor(red: 0.69, green: 0.55, blue: 0.97, alpha: 1.0)),  // Purple (Network)
    ]

    let positions: [(CGFloat, CGFloat)] = [
        (padding, padding + cellSize + spacing),                    // Top-left (flipped Y)
        (padding + cellSize + spacing, padding + cellSize + spacing), // Top-right
        (padding, padding),                                          // Bottom-left
        (padding + cellSize + spacing, padding),                     // Bottom-right
    ]

    // Adaptive detail: drop needles/dots below 64px for cleaner small icons
    let showNeedles = size >= 64
    let showDots = size >= 48

    for (i, gauge) in gauges.enumerated() {
        let (cx, cy) = positions[i]
        let centerX = cx + cellSize / 2
        let centerY = cy + cellSize / 2
        let radius = cellSize * 0.38

        // Thicker arcs at small sizes for legibility
        let lineWidth: CGFloat
        if size < 48 {
            lineWidth = max(size * 0.055, 2.0)
        } else if size < 128 {
            lineWidth = max(size * 0.035, 2.0)
        } else {
            lineWidth = size * 0.028
        }

        // Arc geometry: 270 degree sweep, starting from bottom-left
        let startAngle = CGFloat.pi * 0.75   // 135 degrees (bottom-left)
        let endAngle = CGFloat.pi * 2.25      // 405 degrees (bottom-right, wrapping)
        let sweepAngle = endAngle - startAngle // 270 degrees total
        let fillEnd = startAngle + sweepAngle * gauge.fillRatio

        // Track (dim ring)
        ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: size < 48 ? 0.15 : 0.10))
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.addArc(center: CGPoint(x: centerX, y: centerY), radius: radius,
                   startAngle: startAngle, endAngle: endAngle, clockwise: false)
        ctx.strokePath()

        // Filled arc (accent color)
        ctx.setStrokeColor(gauge.color)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.addArc(center: CGPoint(x: centerX, y: centerY), radius: radius,
                   startAngle: startAngle, endAngle: fillEnd, clockwise: false)
        ctx.strokePath()

        // Center dot (hidden at tiny sizes)
        if showDots {
            let dotRadius = max(size * 0.012, 0.8)
            ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.7))
            ctx.fillEllipse(in: CGRect(
                x: centerX - dotRadius,
                y: centerY - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            ))
        }

        // Needle line from center to fill position (hidden at tiny sizes)
        if showNeedles {
            let needleLength = radius * 0.65
            let needleAngle = fillEnd
            let needleEndX = centerX + needleLength * cos(needleAngle)
            let needleEndY = centerY + needleLength * sin(needleAngle)
            ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.55))
            ctx.setLineWidth(max(size * 0.01, 0.5))
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: centerX, y: centerY))
            ctx.addLine(to: CGPoint(x: needleEndX, y: needleEndY))
            ctx.strokePath()
        }
    }

    image.unlockFocus()
    return image
}

// MARK: - Export

let outputDir = "Resources/Assets.xcassets/AppIcon.appiconset"

// Generate all sizes
var contentsImages: [[String: String]] = []

for variant in variants {
    let image = drawIcon(pixelSize: variant.pixelSize)

    guard let tiffData = image.tiffRepresentation,
          let bitmapRep = NSBitmapImageRep(data: tiffData),
          let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        print("Failed to generate \(variant.filename)")
        continue
    }

    let outputPath = "\(outputDir)/\(variant.filename)"
    do {
        try pngData.write(to: URL(fileURLWithPath: outputPath))
        print("Generated: \(outputPath) (\(variant.pixelSize)x\(variant.pixelSize)px)")
    } catch {
        print("Error writing \(outputPath): \(error)")
    }

    contentsImages.append([
        "filename": variant.filename,
        "idiom": "mac",
        "scale": "\(variant.scale)x",
        "size": "\(variant.size)x\(variant.size)",
    ])
}

// Write Contents.json
let contentsJSON: [String: Any] = [
    "images": contentsImages,
    "info": [
        "author": "xcode",
        "version": 1,
    ] as [String: Any],
]

do {
    let jsonData = try JSONSerialization.data(withJSONObject: contentsJSON, options: [.prettyPrinted, .sortedKeys])
    let contentsPath = "\(outputDir)/Contents.json"
    try jsonData.write(to: URL(fileURLWithPath: contentsPath))
    print("Updated: \(contentsPath)")
} catch {
    print("Error writing Contents.json: \(error)")
}

print("\nDone! App icon generated at all required sizes.")
