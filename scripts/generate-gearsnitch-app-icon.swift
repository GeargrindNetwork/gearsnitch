import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let fileManager = FileManager.default
let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
let sourcesURL = rootURL.appendingPathComponent("client-ios/GearSnitch/Resources/AppIconSources", isDirectory: true)
let iconSetURL = rootURL.appendingPathComponent("client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let masterPDFURL = sourcesURL.appendingPathComponent("gs-eye-iris-master.pdf")
let legacyMasterPDFURL = sourcesURL.appendingPathComponent("gs-monogram-luxe-master.pdf")
let masterPNGURL = iconSetURL.appendingPathComponent("icon-1024.png")

let outputSizes = [40, 58, 60, 76, 80, 87, 120, 152, 167, 180]
let staleFiles = ["icon-20.png", "icon-29.png"]
let canvasSize = 1024

let backgroundStart = NSColor(calibratedRed: 9.0 / 255.0, green: 9.0 / 255.0, blue: 11.0 / 255.0, alpha: 1.0)
let backgroundEnd = NSColor(calibratedRed: 24.0 / 255.0, green: 24.0 / 255.0, blue: 27.0 / 255.0, alpha: 1.0)
let cyan = NSColor(calibratedRed: 34.0 / 255.0, green: 211.0 / 255.0, blue: 238.0 / 255.0, alpha: 1.0)
let emerald = NSColor(calibratedRed: 16.0 / 255.0, green: 185.0 / 255.0, blue: 129.0 / 255.0, alpha: 1.0)
let glowCyan = NSColor(calibratedRed: 34.0 / 255.0, green: 211.0 / 255.0, blue: 238.0 / 255.0, alpha: 0.18)
let glowEmerald = NSColor(calibratedRed: 16.0 / 255.0, green: 185.0 / 255.0, blue: 129.0 / 255.0, alpha: 0.16)
let border = NSColor(calibratedWhite: 1.0, alpha: 0.08)
let textColor = NSColor(calibratedWhite: 0.97, alpha: 1.0)

extension CGPath {
    static func stroked(
        from source: CGPath,
        width: CGFloat,
        lineCap: CGLineCap = .round,
        lineJoin: CGLineJoin = .round
    ) -> CGPath {
        source.copy(
            strokingWithWidth: width,
            lineCap: lineCap,
            lineJoin: lineJoin,
            miterLimit: 10.0
        )
    }
}

func makeGradient(colors: [NSColor], locations: [CGFloat]) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors.map(\.cgColor) as CFArray,
        locations: locations
    )!
}

func makeRoundedSquarePath(in rect: CGRect) -> CGPath {
    let insetRect = rect.insetBy(dx: 56, dy: 56)
    return CGPath(
        roundedRect: insetRect,
        cornerWidth: 236,
        cornerHeight: 236,
        transform: nil
    )
}

func makeEyeCenterlinePath() -> CGPath {
    let path = CGMutablePath()
    let left = CGPoint(x: 176, y: 512)
    let right = CGPoint(x: 848, y: 512)

    path.move(to: left)
    path.addCurve(
        to: right,
        control1: CGPoint(x: 314, y: 724),
        control2: CGPoint(x: 710, y: 724)
    )
    path.addCurve(
        to: left,
        control1: CGPoint(x: 710, y: 300),
        control2: CGPoint(x: 314, y: 300)
    )

    return path
}

func makeEyeOutlinePath() -> CGPath {
    .stroked(from: makeEyeCenterlinePath(), width: 30)
}

func makeIrisRingPath() -> CGPath {
    let irisRect = CGRect(x: 348, y: 348, width: 328, height: 328)
    return CGPath.stroked(from: CGPath(ellipseIn: irisRect, transform: nil), width: 24)
}

func drawRadialGlow(
    in context: CGContext,
    center: CGPoint,
    radius: CGFloat,
    color: NSColor
) {
    let gradient = makeGradient(
        colors: [color, color.withAlphaComponent(0.0)],
        locations: [0.0, 1.0]
    )

    context.saveGState()
    context.drawRadialGradient(
        gradient,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: radius,
        options: [.drawsAfterEndLocation]
    )
    context.restoreGState()
}

func fillPathWithGradient(
    _ path: CGPath,
    context: CGContext,
    start: CGPoint,
    end: CGPoint
) {
    let gradient = makeGradient(colors: [cyan, emerald], locations: [0.0, 1.0])
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.drawLinearGradient(gradient, start: start, end: end, options: [])
    context.restoreGState()
}

func drawBackground(in rect: CGRect, context: CGContext, clipPath: CGPath) {
    let backgroundGradient = makeGradient(
        colors: [backgroundStart, backgroundEnd],
        locations: [0.0, 1.0]
    )

    context.saveGState()
    context.addPath(clipPath)
    context.clip()
    context.drawLinearGradient(
        backgroundGradient,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )

    drawRadialGlow(
        in: context,
        center: CGPoint(x: rect.midX - 120, y: rect.midY + 110),
        radius: 280,
        color: glowCyan
    )
    drawRadialGlow(
        in: context,
        center: CGPoint(x: rect.midX + 150, y: rect.midY - 100),
        radius: 260,
        color: glowEmerald
    )
    context.restoreGState()

    context.saveGState()
    context.addPath(clipPath)
    context.setStrokeColor(border.cgColor)
    context.setLineWidth(3)
    context.strokePath()
    context.restoreGState()
}

func drawCenteredText(_ text: String, in rect: CGRect, context: CGContext) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 150, weight: .bold),
        .foregroundColor: textColor,
        .paragraphStyle: paragraph,
        .kern: -3.0,
    ]

    let attributed = NSAttributedString(string: text, attributes: attributes)
    let textSize = attributed.size()
    let textRect = CGRect(
        x: rect.midX - (textSize.width / 2.0),
        y: rect.midY - (textSize.height / 2.0) - 8.0,
        width: textSize.width,
        height: textSize.height
    )

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    attributed.draw(in: textRect)
    NSGraphicsContext.restoreGraphicsState()
}

func drawEyeMark(in rect: CGRect, context: CGContext) {
    let eyePath = makeEyeOutlinePath()
    let irisPath = makeIrisRingPath()

    context.saveGState()
    context.setShadow(offset: .zero, blur: 36, color: glowCyan.withAlphaComponent(0.35).cgColor)
    fillPathWithGradient(
        eyePath,
        context: context,
        start: CGPoint(x: rect.minX + 140, y: rect.midY + 100),
        end: CGPoint(x: rect.maxX - 140, y: rect.midY - 100)
    )
    context.restoreGState()

    context.saveGState()
    context.setShadow(offset: .zero, blur: 24, color: glowEmerald.withAlphaComponent(0.28).cgColor)
    fillPathWithGradient(
        irisPath,
        context: context,
        start: CGPoint(x: rect.minX + 220, y: rect.maxY - 220),
        end: CGPoint(x: rect.maxX - 220, y: rect.minY + 220)
    )
    context.restoreGState()

    drawCenteredText(
        "GS",
        in: CGRect(x: 372, y: 392, width: 280, height: 240),
        context: context
    )
}

func drawIcon(in rect: CGRect, context: CGContext) {
    context.setFillColor(NSColor.clear.cgColor)
    context.fill(rect)

    let roundedSquare = makeRoundedSquarePath(in: rect)
    drawBackground(in: rect, context: context, clipPath: roundedSquare)
    drawEyeMark(in: rect, context: context)
}

func writeMasterPDF() throws {
    var mediaBox = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)

    guard let consumer = CGDataConsumer(url: masterPDFURL as CFURL),
          let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        throw NSError(domain: "AppIconGenerator", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Unable to create PDF context."
        ])
    }

    pdfContext.beginPDFPage(nil)
    drawIcon(in: mediaBox, context: pdfContext)
    pdfContext.endPDFPage()
    pdfContext.closePDF()
}

func writeMasterPNG() throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let bitmapContext = CGContext(
        data: nil,
        width: canvasSize,
        height: canvasSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "AppIconGenerator", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Unable to create bitmap context."
        ])
    }

    let rect = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
    drawIcon(in: rect, context: bitmapContext)

    guard let cgImage = bitmapContext.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
            masterPNGURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
          ) else {
        throw NSError(domain: "AppIconGenerator", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "Unable to encode PNG."
        ])
    }

    CGImageDestinationAddImage(destination, cgImage, nil)

    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "AppIconGenerator", code: 4, userInfo: [
            NSLocalizedDescriptionKey: "Failed to finalize PNG output."
        ])
    }
}

func runProcess(_ launchPath: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
            ?? "Unknown process failure"
        throw NSError(domain: "AppIconGenerator", code: 5, userInfo: [
            NSLocalizedDescriptionKey: message
        ])
    }
}

func deriveIconSizes() throws {
    for size in outputSizes {
        let outputURL = iconSetURL.appendingPathComponent("icon-\(size).png")
        try runProcess(
            "/usr/bin/sips",
            [
                "-z", "\(size)", "\(size)",
                masterPNGURL.path,
                "--out", outputURL.path,
            ]
        )
    }
}

func removeLegacyArtifacts() throws {
    for file in staleFiles {
        let url = iconSetURL.appendingPathComponent(file)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    if fileManager.fileExists(atPath: legacyMasterPDFURL.path) {
        try fileManager.removeItem(at: legacyMasterPDFURL)
    }
}

do {
    try fileManager.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: iconSetURL, withIntermediateDirectories: true)

    try writeMasterPDF()
    try writeMasterPNG()
    try deriveIconSizes()
    try removeLegacyArtifacts()

    print("Generated GearSnitch iris-ring app icon master and AppIcon assets.")
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
