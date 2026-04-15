#!/usr/bin/env swift
// generate-icon.swift — generates BrowserPicker app icon PNG files
// Usage: swift scripts/generate-icon.swift
// Output: BrowserPicker/Assets.xcassets/AppIcon.appiconset/

import AppKit
import Foundation

// MARK: - Drawing

func drawIcon(_ s: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

        // ── 1. Background gradient (blue top-left → indigo bottom-right) ──
        let cs = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(
            colorSpace: cs,
            colorComponents: [0.10, 0.28, 0.92, 1,   // blue (top-left)
                               0.36, 0.10, 0.82, 1],  // indigo (bottom-right)
            locations: [0, 1], count: 2)!
        ctx.drawLinearGradient(gradient,
            start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

        // ── 2. Picker panel (white frosted card, centered) ──
        let pw = s * 0.68, ph = s * 0.60, pr = s * 0.055
        let px = (s - pw) / 2
        let py = (s - ph) / 2

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.022),
                      blur: s * 0.075,
                      color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.42))
        let cardPath = CGPath(
            roundedRect: CGRect(x: px, y: py, width: pw, height: ph),
            cornerWidth: pr, cornerHeight: pr, transform: nil)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.93))
        ctx.addPath(cardPath)
        ctx.fillPath()
        ctx.restoreGState()

        // ── 3. Three browser rows inside the panel ──
        // Each row: coloured circle + text placeholder line
        // Row layout: top = row0, middle = row1 (selected), bottom = row2
        let rowH    = ph / 3.6
        let iconR   = rowH * 0.26        // circle radius
        let iconD   = iconR * 2
        let iconX   = px + pw * 0.115    // circle left edge

        // Row centre-Y values (Quartz: y=0 is bottom)
        let row0Y = py + ph - rowH * 1.05 + rowH * 0.5 - iconR
        let row1Y = py + ph * 0.5 - iconR
        let row2Y = py + rowH * 0.55 - iconR

        let rows: [(rowY: CGFloat, r: CGFloat, g: CGFloat, b: CGFloat, selected: Bool)] = [
            (row0Y, 0.18, 0.62, 1.00, false),   // blue  – Chrome-ish
            (row1Y, 0.95, 0.44, 0.16, true),    // orange – Firefox-ish (selected)
            (row2Y, 0.50, 0.82, 0.47, false),   // green  – Edge/Brave-ish
        ]

        for row in rows {
            // Selection highlight behind the row
            if row.selected {
                let hlRect = CGRect(
                    x: px + pw * 0.04,
                    y: row.rowY - rowH * 0.08,
                    width: pw * 0.92,
                    height: iconD + rowH * 0.16)
                let hlPath = CGPath(
                    roundedRect: hlRect,
                    cornerWidth: s * 0.022, cornerHeight: s * 0.022, transform: nil)
                ctx.setFillColor(CGColor(red: 0.36, green: 0.10, blue: 0.82, alpha: 0.13))
                ctx.addPath(hlPath)
                ctx.fillPath()
            }

            // Browser circle
            let circleRect = CGRect(x: iconX, y: row.rowY, width: iconD, height: iconD)
            ctx.setFillColor(CGColor(red: row.r, green: row.g, blue: row.b, alpha: 1.0))
            ctx.fillEllipse(in: circleRect)

            // Short white "tick" on the selected circle
            if row.selected {
                let tickW = iconD * 0.55
                let tickH = iconD * 0.11
                ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
                ctx.fill(CGRect(
                    x: iconX + (iconD - tickW) / 2,
                    y: row.rowY + (iconD - tickH) / 2,
                    width: tickW, height: tickH))
            }

            // Name placeholder bar
            let textX   = iconX + iconD + pw * 0.065
            let barW    = pw * (row.selected ? 0.42 : 0.34)
            let barH    = s * 0.013
            let barY    = row.rowY + iconR - barH / 2
            ctx.setFillColor(
                CGColor(red: 0.2, green: 0.2, blue: 0.2,
                        alpha: row.selected ? 0.55 : 0.25))
            let barPath = CGPath(
                roundedRect: CGRect(x: textX, y: barY, width: barW, height: barH),
                cornerWidth: barH / 2, cornerHeight: barH / 2, transform: nil)
            ctx.addPath(barPath)
            ctx.fillPath()
        }

        // Thin dividers between rows
        let divAlpha: CGFloat = 0.08
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: divAlpha))
        for divY in [row0Y - rowH * 0.28, row1Y - rowH * 0.28] {
            ctx.fill(CGRect(x: px + pw * 0.04, y: divY, width: pw * 0.92, height: max(1, s * 0.005)))
        }

        return true
    }
}

// MARK: - Save PNG

func savePNG(_ image: NSImage, to path: String) throws {
    let w = Int(image.size.width)
    let h = Int(image.size.height)

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else {
        throw NSError(domain: "Icon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "NSBitmapImageRep init failed"])
    }
    rep.size = NSSize(width: w, height: h)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "Icon", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
    }
    try data.write(to: URL(fileURLWithPath: path))
}

// MARK: - Main

let projectRoot = URL(fileURLWithPath: #file)
    .deletingLastPathComponent()
    .deletingLastPathComponent().path
let outDir = "\(projectRoot)/BrowserPicker/Assets.xcassets/AppIcon.appiconset"
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let specs: [(Int, Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

for (base, scale) in specs {
    let renderSize = CGFloat(base * scale)
    let img = drawIcon(renderSize)
    let filename = scale == 1
        ? "icon_\(base)x\(base).png"
        : "icon_\(base)x\(base)@2x.png"
    do {
        try savePNG(img, to: "\(outDir)/\(filename)")
        print("  ✓ \(filename)  (\(Int(renderSize))px)")
    } catch {
        print("  ✗ \(filename): \(error.localizedDescription)")
    }
}

print("\nIcons written to:\n  \(outDir)")
