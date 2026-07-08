#!/usr/bin/env swift
// Generates the DMG background image (600x400)
import Foundation
import CoreGraphics
import ImageIO

let W: CGFloat = 600, H: CGFloat = 400
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: Int(W), height: Int(H),
                    bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!

ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)

func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}

// Background gradient
let bgGrad = CGGradient(colorsSpace: cs,
    colors: [c(0.10, 0.08, 0.20), c(0.06, 0.04, 0.14)] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(bgGrad, start: .zero, end: CGPoint(x: 0, y: H), options: [])

// Subtle top glow
let glow = CGGradient(colorsSpace: cs,
    colors: [c(0.54, 0.17, 0.89, 0.12), c(0.54, 0.17, 0.89, 0)] as CFArray,
    locations: [0, 1])!
ctx.drawRadialGradient(glow,
    startCenter: CGPoint(x: W / 2, y: 0), startRadius: 0,
    endCenter:   CGPoint(x: W / 2, y: 0), endRadius: 300, options: [])

// Arrow between app (x=160) and Applications (x=440), centered vertically
let arrowY: CGFloat = H / 2
let arrowX1: CGFloat = 235, arrowX2: CGFloat = 365
let arrowColor = c(1, 1, 1, 0.12)

ctx.setStrokeColor(arrowColor)
ctx.setLineWidth(2)
ctx.setLineDash(phase: 0, lengths: [6, 5])
ctx.move(to: CGPoint(x: arrowX1, y: arrowY))
ctx.addLine(to: CGPoint(x: arrowX2 - 14, y: arrowY))
ctx.strokePath()

// Arrowhead
ctx.setLineDash(phase: 0, lengths: [])
ctx.setFillColor(arrowColor)
ctx.beginPath()
ctx.move(to:    CGPoint(x: arrowX2,      y: arrowY))
ctx.addLine(to: CGPoint(x: arrowX2 - 16, y: arrowY - 8))
ctx.addLine(to: CGPoint(x: arrowX2 - 16, y: arrowY + 8))
ctx.closePath()
ctx.fillPath()

// Export
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-bg.png"
let image = ctx.makeImage()!
let url = URL(fileURLWithPath: outPath)
let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("DMG background saved -> \(outPath)")
