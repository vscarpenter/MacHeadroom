import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Renders the "Amber Headroom" app icon: a flat graphite background plus
// four amber bars of ascending height, with deliberate empty space above
// the tallest bar (the visual pun for "headroom"). Full-bleed square, no
// baked-in corner mask or shadow: Xcode/macOS apply the squircle mask and
// system depth at render time, per current Apple app icon guidance.
//
// Run: swift Design/AppIcon/render_icon.swift
// Produces AppIcon-1024.png (composite, for the traditional appiconset)
// plus layer-background-1024.png and layer-bars-1024.png (for an Icon
// Composer .icon assembly).

let canvasSize = 1024.0

func makeContext() -> CGContext {
  let colorSpace = CGColorSpaceCreateDeviceRGB()
  let context = CGContext(
    data: nil,
    width: Int(canvasSize),
    height: Int(canvasSize),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  // Work in top-down coordinates (y increases downward), matching how the
  // design spec describes positions ("12% up from the bottom edge").
  context.translateBy(x: 0, y: canvasSize)
  context.scaleBy(x: 1, y: -1)
  return context
}

func drawBackground(in context: CGContext) {
  let colorSpace = CGColorSpaceCreateDeviceRGB()
  let colors: [CGColor] = [
    CGColor(red: 0x57 / 255.0, green: 0x57 / 255.0, blue: 0x5E / 255.0, alpha: 1),
    CGColor(red: 0x2C / 255.0, green: 0x2C / 255.0, blue: 0x30 / 255.0, alpha: 1),
    CGColor(red: 0x13 / 255.0, green: 0x13 / 255.0, blue: 0x15 / 255.0, alpha: 1),
  ]
  let gradient = CGGradient(
    colorsSpace: colorSpace, colors: colors as CFArray, locations: [0, 0.55, 1])!
  let start = CGPoint(x: canvasSize * 0.15, y: canvasSize * 0.08)
  let end = CGPoint(x: canvasSize * 0.88, y: canvasSize * 0.95)
  context.saveGState()
  context.addRect(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
  context.clip()
  context.drawLinearGradient(
    gradient, start: start, end: end,
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
  context.restoreGState()
}

struct Bar {
  let x: Double
  let width: Double
  let topY: Double
  let bottomY: Double
}

// Geometry from the approved spec, all as percentages of the 1024 canvas:
// side margins 10.5%, four bars each 16% wide with 5% gaps, baseline 12%
// up from the bottom edge, heights 24/39/54/69% ascending left to right.
let bars: [Bar] = [
  Bar(x: 107.52, width: 163.84, topY: 655.36, bottomY: 901.12),
  Bar(x: 322.56, width: 163.84, topY: 501.76, bottomY: 901.12),
  Bar(x: 537.60, width: 163.84, topY: 348.16, bottomY: 901.12),
  Bar(x: 752.64, width: 163.84, topY: 194.56, bottomY: 901.12),
]

func barPath(_ bar: Bar) -> CGPath {
  let radius = bar.width / 2
  let path = CGMutablePath()
  let straightTop = bar.topY + radius
  path.addRect(CGRect(x: bar.x, y: straightTop, width: bar.width, height: bar.bottomY - straightTop))
  path.addEllipse(in: CGRect(x: bar.x, y: bar.topY, width: bar.width, height: radius * 2))
  return path
}

func drawBars(in context: CGContext) {
  let colorSpace = CGColorSpaceCreateDeviceRGB()
  let colors: [CGColor] = [
    CGColor(red: 0xFF / 255.0, green: 0xD2 / 255.0, blue: 0x7A / 255.0, alpha: 1),
    CGColor(red: 0xC9 / 255.0, green: 0x6A / 255.0, blue: 0x0A / 255.0, alpha: 1),
  ]
  let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0, 1])!
  for bar in bars {
    context.saveGState()
    context.addPath(barPath(bar))
    context.clip()
    let start = CGPoint(x: bar.x + bar.width / 2, y: bar.topY)
    let end = CGPoint(x: bar.x + bar.width / 2, y: bar.bottomY)
    context.drawLinearGradient(gradient, start: start, end: end, options: [])
    context.restoreGState()
  }
}

func save(_ context: CGContext, to path: String) {
  guard let image = context.makeImage() else {
    fatalError("Failed to create image for \(path)")
  }
  let url = URL(fileURLWithPath: path) as CFURL
  guard
    let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)
  else {
    fatalError("Failed to create image destination for \(path)")
  }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else {
    fatalError("Failed to write \(path)")
  }
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

let composite = makeContext()
drawBackground(in: composite)
drawBars(in: composite)
save(composite, to: outputDirectory.appendingPathComponent("AppIcon-1024.png").path)

let backgroundOnly = makeContext()
drawBackground(in: backgroundOnly)
save(backgroundOnly, to: outputDirectory.appendingPathComponent("layer-background-1024.png").path)

let barsOnly = makeContext()
drawBars(in: barsOnly)
save(barsOnly, to: outputDirectory.appendingPathComponent("layer-bars-1024.png").path)

print("Rendered AppIcon-1024.png, layer-background-1024.png, layer-bars-1024.png")
