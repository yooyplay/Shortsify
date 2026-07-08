#!/usr/bin/env swift
// Generates a 1024x1024 Shortsify app icon PNG
import Foundation
import CoreGraphics
import ImageIO

let s: CGFloat = 1024
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: Int(s), height: Int(s),
                    bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!

// y=0 at top
ctx.translateBy(x: 0, y: s)
ctx.scaleBy(x: 1, y: -1)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}

// ── Background (rounded square) ───────────────────────────────────────────────
let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                    cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
ctx.addPath(bgPath); ctx.clip()

// Diagonal gradient: deep indigo → violet → pink
let gradColors = [color(0.22, 0.12, 0.60),   // #381999 indigo
                  color(0.54, 0.17, 0.89),    // #8a2be2 violet
                  color(0.93, 0.22, 0.54)] as CFArray // #ec3889 pink
let locs: [CGFloat] = [0, 0.52, 1]
let gradient = CGGradient(colorsSpace: cs, colors: gradColors, locations: locs)!
ctx.drawLinearGradient(gradient,
    start: CGPoint(x: 0, y: 0), end: CGPoint(x: s, y: s), options: [])

// Subtle radial highlight (top-left bloom)
let bloom = CGGradient(colorsSpace: cs,
    colors: [color(1, 1, 1, 0.18), color(1, 1, 1, 0)] as CFArray,
    locations: [0, 1])!
ctx.drawRadialGradient(bloom,
    startCenter: CGPoint(x: s * 0.18, y: s * 0.18), startRadius: 0,
    endCenter:   CGPoint(x: s * 0.18, y: s * 0.18), endRadius: s * 0.55,
    options: [])

ctx.resetClip()

// ── Phone body ────────────────────────────────────────────────────────────────
let pw: CGFloat = 300, ph: CGFloat = 510
let px = (s - pw) / 2, py = (s - ph) / 2
let phoneRect = CGRect(x: px, y: py, width: pw, height: ph)
let phonePath = CGPath(roundedRect: phoneRect, cornerWidth: 38, cornerHeight: 38, transform: nil)

// Drop shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 16), blur: 52, color: color(0, 0, 0, 0.55))
ctx.setFillColor(color(1, 1, 1))
ctx.addPath(phonePath); ctx.fillPath()
ctx.restoreGState()

// ── Phone screen ──────────────────────────────────────────────────────────────
let inset: CGFloat = 13
let scrRect = CGRect(x: px + inset, y: py + inset, width: pw - inset*2, height: ph - inset*2)
let scrPath = CGPath(roundedRect: scrRect, cornerWidth: 27, cornerHeight: 27, transform: nil)

// Screen gradient (dark purple)
ctx.addPath(scrPath); ctx.clip()
let scrGrad = CGGradient(colorsSpace: cs,
    colors: [color(0.07, 0.04, 0.18), color(0.12, 0.06, 0.28)] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(scrGrad,
    start: CGPoint(x: 0, y: py + inset),
    end:   CGPoint(x: 0, y: py + ph - inset), options: [])
ctx.resetClip()

// ── Film perforations (sides of screen) ───────────────────────────────────────
let perfW: CGFloat = 11, perfH: CGFloat = 16
let perfStep: CGFloat = 29
let perfCount = 7
let totalPH = CGFloat(perfCount - 1) * perfStep + perfH
let perfStartY = s / 2 - totalPH / 2

ctx.setFillColor(color(1, 1, 1, 0.18))
for i in 0..<perfCount {
    let y = perfStartY + CGFloat(i) * perfStep
    // left
    ctx.fill(CGRect(x: px + inset + 5, y: y, width: perfW, height: perfH))
    // right
    ctx.fill(CGRect(x: px + pw - inset - 5 - perfW, y: y, width: perfW, height: perfH))
}

// ── Play button ───────────────────────────────────────────────────────────────
let cx = s / 2, cy = s / 2 + 6
let ts: CGFloat = 88

// Glow behind play button
ctx.saveGState()
let glowGrad = CGGradient(colorsSpace: cs,
    colors: [color(1, 1, 1, 0.30), color(1, 1, 1, 0)] as CFArray,
    locations: [0, 1])!
ctx.drawRadialGradient(glowGrad,
    startCenter: CGPoint(x: cx + 4, y: cy), startRadius: 0,
    endCenter:   CGPoint(x: cx + 4, y: cy), endRadius: ts * 1.1, options: [])
ctx.restoreGState()

// Triangle
ctx.beginPath()
ctx.move(to:     CGPoint(x: cx - ts * 0.40, y: cy - ts * 0.55))
ctx.addLine(to:  CGPoint(x: cx + ts * 0.65, y: cy))
ctx.addLine(to:  CGPoint(x: cx - ts * 0.40, y: cy + ts * 0.55))
ctx.closePath()
ctx.setFillColor(color(1, 1, 1, 0.97))
ctx.fillPath()

// ── Camera notch (top of phone) ───────────────────────────────────────────────
let notchW: CGFloat = 60, notchH: CGFloat = 10
let notchX = s / 2 - notchW / 2
let notchY = py + inset + 10
let notchPath = CGPath(roundedRect: CGRect(x: notchX, y: notchY, width: notchW, height: notchH),
                        cornerWidth: 5, cornerHeight: 5, transform: nil)
ctx.setFillColor(color(1, 1, 1, 0.15))
ctx.addPath(notchPath); ctx.fillPath()

// Home indicator bar (bottom)
let barW: CGFloat = 80, barH: CGFloat = 6
ctx.fill(CGRect(x: s/2 - barW/2, y: py + ph - inset - 16, width: barW, height: barH))

// ── Export ────────────────────────────────────────────────────────────────────
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let image = ctx.makeImage()!
let url = URL(fileURLWithPath: outPath)
let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("✅ Icon saved → \(outPath)")
