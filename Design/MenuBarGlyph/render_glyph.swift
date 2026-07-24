import CoreGraphics
import Foundation

// Renders the Mac Headroom menu bar glyph: the app icon's four ascending
// round-topped bars, shortened, under a thin ceiling line. The gap between
// the tallest bar and the line is the "headroom." Output is an 18x18 point
// vector PDF for the asset catalog's MenuBarGlyph imageset, which marks it
// as a template image so the system tints it for menu bar appearance.
//
// Run: swift Design/MenuBarGlyph/render_glyph.swift <output-directory>

let canvas = 18.0

// Geometry as fractions of the canvas, top-down. Bars keep the app icon's
// 10.5% margins, 16% widths, and 5% gaps; heights are compressed to leave
// room for the ceiling line inside the square.
let barX = [0.105, 0.315, 0.525, 0.735]
let barHeights = [0.20, 0.32, 0.44, 0.57]
let barWidth = 0.16
let baseline = 0.88
let ceilingY = 0.09
let ceilingThickness = 0.055

func glyphPath() -> CGPath {
  let path = CGMutablePath()
  for (x, height) in zip(barX, barHeights) {
    let radius = barWidth / 2
    let top = baseline - height
    path.addEllipse(
      in: CGRect(
        x: x * canvas, y: top * canvas,
        width: barWidth * canvas, height: radius * 2 * canvas))
    path.addRect(
      CGRect(
        x: x * canvas, y: (top + radius) * canvas,
        width: barWidth * canvas, height: (baseline - top - radius) * canvas))
  }
  let lineHeight = ceilingThickness * canvas
  path.addRoundedRect(
    in: CGRect(
      x: barX[0] * canvas, y: ceilingY * canvas,
      width: (barX[3] + barWidth - barX[0]) * canvas, height: lineHeight),
    cornerWidth: lineHeight / 2, cornerHeight: lineHeight / 2)
  return path
}

let outputDirectory = URL(
  fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let url = outputDirectory.appendingPathComponent("MenuBarGlyph.pdf")
var mediaBox = CGRect(x: 0, y: 0, width: canvas, height: canvas)
guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
  fatalError("Failed to create PDF context at \(url.path)")
}
context.beginPDFPage(nil)
// Flip to top-down coordinates so the geometry reads like the design spec.
context.translateBy(x: 0, y: canvas)
context.scaleBy(x: 1, y: -1)
context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
context.addPath(glyphPath())
context.fillPath()
context.endPDFPage()
context.closePDF()
print("Rendered \(url.path)")
