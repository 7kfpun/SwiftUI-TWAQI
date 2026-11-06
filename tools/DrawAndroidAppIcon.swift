//
//  DrawAndroidAppIcon.swift
//  tools
//
//  Draws the Android launcher icon (FOX-108) from the iOS icon's design: the
//  orange-to-purple sky, the cloud and the warning sign, laid out on the iOS
//  icon's 1024 grid. The sky, cloud and colours are DrawVisionAppIcon.swift's;
//  the sign and its mark are measured from the iOS icon itself
//  (ios/TWAQI/Assets.xcassets/AppIcon.appiconset/icon-1024.png), which has a
//  larger sign and a shorter mark than the visionOS layers.
//
//  It writes, for each Android module given:
//    res/drawable/ic_launcher_background.xml   the sky (a vector gradient)
//    res/drawable/ic_launcher_foreground.xml   the cloud and the sign
//    res/drawable/ic_launcher_monochrome.xml   one-colour silhouette (themed icons)
//  and the Play store icon, 512x512, full bleed and square (Play rounds it):
//    app/src/main/play/listings/<locale>/graphics/icon/1.png
//
//  Adaptive icon layers are 108dp; launchers show the middle 72dp through
//  their mask and keep the 66dp circle in the middle whole. The iOS 1024 grid
//  maps onto that 72dp square, so the icon looks as it does on iOS, and the
//  artwork (radius about 451 of 1024, i.e. 31.7dp) stays inside the 66dp circle.
//
//  Usage (from the repository root):
//    swiftc -O tools/DrawAndroidAppIcon.swift -o /tmp/draw-android-icon
//    /tmp/draw-android-icon android
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let android = URL(fileURLWithPath: CommandLine.arguments[1])
let modules = ["app", "wear"]
let playLocales = ["en-US", "zh-TW"]

// MARK: Geometry, on the iOS icon's 1024 grid with y running down (as in DrawVisionAppIcon.swift).

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

struct Gradient {
    let stops: [(CGFloat, UInt32)]
    let start: CGPoint
    let end: CGPoint

    var cgGradient: CGGradient {
        CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: stops.map { color($0.1) } as CFArray,
            locations: stops.map(\.0)
        )!
    }
}

let skyGradient = Gradient(
    stops: [(0, 0xFF7733), (0.5, 0xD6233A), (1, 0x73008C)],
    start: .zero, end: CGPoint(x: 1024, y: 1024)
)
let cloudGradient = Gradient(
    stops: [(0, 0xF9D6D1), (0.55, 0xFAE3E4), (1, 0xFCEEF0)],
    start: CGPoint(x: 0, y: 130), end: CGPoint(x: 0, y: 690)
)
let signGradient = Gradient(
    stops: [(0, 0xFFD503), (1, 0xFEC401)],
    start: CGPoint(x: 0, y: 425), end: CGPoint(x: 0, y: 847)
)
let markColor: UInt32 = 0x222222

let cloud: CGPath = {
    let path = CGMutablePath()
    path.addEllipse(in: CGRect(x: 548 - 195, y: 130, width: 390, height: 390))   // crown
    path.addEllipse(in: CGRect(x: 225, y: 298, width: 210, height: 210))         // left shoulder
    path.addEllipse(in: CGRect(x: 580, y: 330, width: 360, height: 360))         // right lobe, down to the base
    path.addEllipse(in: CGRect(x: 64, y: 415, width: 275, height: 275))          // base, rounded left end
    path.addRect(CGRect(x: 201, y: 415, width: 760 - 201, height: 275))          // base
    return path.normalized()   // one outline: the union of the pieces
}()

let sign: CGPath = {
    // Rounded triangle: each corner is an arc tangent to its two sides. Fitted to
    // icon-1024.png: sides sloping 0.61 across per 1 down, extent x 294...730, y 471...847.
    let top = CGPoint(x: 512, y: 425), left = CGPoint(x: 254, y: 847), right = CGPoint(x: 770, y: 847)
    let path = CGMutablePath()
    path.move(to: CGPoint(x: (left.x + right.x) / 2, y: left.y))
    path.addArc(tangent1End: right, tangent2End: top, radius: 50)
    path.addArc(tangent1End: top, tangent2End: left, radius: 50)
    path.addArc(tangent1End: left, tangent2End: right, radius: 50)
    path.closeSubpath()
    return path
}()

let mark: CGPath = {
    // The exclamation mark: a bar tapering towards its foot, then the dot
    // (icon-1024.png: bar y 582...732, dot y 751...803).
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 483, y: 600))
    path.addLine(to: CGPoint(x: 541, y: 600))
    path.addLine(to: CGPoint(x: 531, y: 716))
    path.addLine(to: CGPoint(x: 493, y: 716))
    path.closeSubpath()
    path.addEllipse(in: CGRect(x: 483, y: 584, width: 58, height: 32))   // rounded top of the bar
    path.addEllipse(in: CGRect(x: 493, y: 700, width: 38, height: 32))   // rounded foot
    path.addEllipse(in: CGRect(x: 486, y: 751, width: 52, height: 52))   // dot
    return path.normalized()
}()

/// In one colour the sign would merge into the cloud, so the themed icon cuts
/// a gap around it, as the colours separate them in the full icon.
let monochromeGap: CGFloat = 24
let monochromeCloud = cloud.subtracting(
    sign.union(sign.copy(strokingWithWidth: monochromeGap * 2, lineCap: .round, lineJoin: .round, miterLimit: 10))
)
let monochromeSign = sign.subtracting(mark)

// MARK: Vector drawables (108dp canvas; the 1024 grid fills its middle 72dp).

let canvasDp: CGFloat = 108
let gridToCanvas = CGAffineTransform(translationX: 18, y: 18).scaledBy(x: 72.0 / 1024, y: 72.0 / 1024)

func number(_ value: CGFloat) -> String {
    var text = String(format: "%.3f", Double(value))
    while text.hasSuffix("0") { text.removeLast() }
    if text.hasSuffix(".") { text.removeLast() }
    return text == "-0" ? "0" : text
}

/// Themed icons draw the glyph alone on a tinted disc, where the system's own
/// glyphs sit smaller than full-colour art, so the silhouette is shrunk about the centre.
let monochromeScale: CGFloat = 0.8
let monochromeToCanvas = CGAffineTransform(translationX: 512, y: 512)
    .scaledBy(x: monochromeScale, y: monochromeScale)
    .translatedBy(x: -512, y: -512)
    .concatenating(gridToCanvas)

func point(_ p: CGPoint, _ transform: CGAffineTransform) -> String {
    let q = p.applying(transform)
    return "\(number(q.x)),\(number(q.y))"
}

func pathData(_ path: CGPath, _ transform: CGAffineTransform = gridToCanvas) -> String {
    var parts: [String] = []
    path.applyWithBlock { element in
        let e = element.pointee
        switch e.type {
        case .moveToPoint: parts.append("M\(point(e.points[0], transform))")
        case .addLineToPoint: parts.append("L\(point(e.points[0], transform))")
        case .addQuadCurveToPoint: parts.append("Q\(point(e.points[0], transform)) \(point(e.points[1], transform))")
        case .addCurveToPoint: parts.append("C\(point(e.points[0], transform)) \(point(e.points[1], transform)) \(point(e.points[2], transform))")
        case .closeSubpath: parts.append("Z")
        @unknown default: fatalError("Unknown path element")
        }
    }
    return parts.joined(separator: " ")
}

func hex(_ value: UInt32) -> String { String(format: "#FF%06X", value) }

func gradientFill(_ gradient: Gradient) -> String {
    let start = gradient.start.applying(gridToCanvas), end = gradient.end.applying(gridToCanvas)
    let items = gradient.stops
        .map { "                <item android:offset=\"\(number($0.0))\" android:color=\"\(hex($0.1))\" />" }
        .joined(separator: "\n")
    return """
            <aapt:attr name="android:fillColor">
                <gradient
                    android:type="linear"
                    android:startX="\(number(start.x))"
                    android:startY="\(number(start.y))"
                    android:endX="\(number(end.x))"
                    android:endY="\(number(end.y))">
    \(items)
                </gradient>
            </aapt:attr>
    """
}

enum Fill {
    /// evenOdd for shapes with holes cut by the boolean operations, whose winding isn't guaranteed.
    case solid(UInt32, evenOdd: Bool = false)
    case gradient(Gradient)
}

/// Lint warns about vector paths over 800 characters (slow to rasterise below
/// API 21); these draw once into the launcher's cache, so the long ones say so.
func pathElement(_ data: String, _ fill: Fill) -> String {
    let ignore = data.count > 800 ? "\n        tools:ignore=\"VectorPath\"" : ""
    switch fill {
    case .solid(let value, let evenOdd):
        let fillType = evenOdd ? "\n        android:fillType=\"evenOdd\"" : ""
        return """
            <path
                android:fillColor="\(hex(value))"\(fillType)
                android:pathData="\(data)"\(ignore) />
        """
    case .gradient(let gradient):
        return """
            <path
                android:pathData="\(data)"\(ignore)>
        \(gradientFill(gradient))
            </path>
        """
    }
}

func vector(_ comment: String, _ paths: [String]) -> String {
    let body = paths.joined(separator: "\n")
    let aapt = body.contains("aapt:") ? "\n    xmlns:aapt=\"http://schemas.android.com/aapt\"" : ""
    let tools = body.contains("tools:") ? "\n    xmlns:tools=\"http://schemas.android.com/tools\"" : ""
    return """
    <?xml version="1.0" encoding="utf-8"?>
    <!-- \(comment)
         Generated by tools/DrawAndroidAppIcon.swift (FOX-108); edit that, not this file. -->
    <vector xmlns:android="http://schemas.android.com/apk/res/android"\(aapt)\(tools)
        android:width="\(number(canvasDp))dp"
        android:height="\(number(canvasDp))dp"
        android:viewportWidth="\(number(canvasDp))"
        android:viewportHeight="\(number(canvasDp))">
    \(body)
    </vector>

    """
}

let background = vector(
    "Launcher icon background: the iOS icon's sky, corner to corner of the 72dp visible square.",
    [pathElement("M0,0 L108,0 L108,108 L0,108 Z", .gradient(skyGradient))]
)
let foreground = vector(
    "Launcher icon foreground: the iOS icon's cloud and warning sign, inside the 66dp safe zone.",
    [
        pathElement(pathData(cloud), .gradient(cloudGradient)),
        pathElement(pathData(sign), .gradient(signGradient)),
        pathElement(pathData(mark), .solid(markColor)),
    ]
)
let monochrome = vector(
    "Themed icon (Android 13+): the cloud and the sign in one colour, the mark cut out.",
    [pathElement(pathData(monochromeCloud, monochromeToCanvas) + " " + pathData(monochromeSign, monochromeToCanvas), .solid(0xFFFFFF, evenOdd: true))]
)

for module in modules {
    let drawable = android.appendingPathComponent("\(module)/src/main/res/drawable")
    try FileManager.default.createDirectory(at: drawable, withIntermediateDirectories: true)
    for (name, text) in [
        ("ic_launcher_background", background),
        ("ic_launcher_foreground", foreground),
        ("ic_launcher_monochrome", monochrome),
    ] {
        try text.write(to: drawable.appendingPathComponent("\(name).xml"), atomically: true, encoding: .utf8)
    }
}

// MARK: Play store icon: 512x512, full bleed, square, opaque.

func renderPlayIcon(size: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: CGFloat(size) / 1024, y: -CGFloat(size) / 1024)

    let options: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    func fill(_ path: CGPath?, _ gradient: Gradient) {
        context.saveGState()
        if let path {
            context.addPath(path)
            context.clip()
        }
        context.drawLinearGradient(gradient.cgGradient, start: gradient.start, end: gradient.end, options: options)
        context.restoreGState()
    }
    fill(nil, skyGradient)
    fill(cloud, cloudGradient)
    fill(sign, signGradient)
    context.setFillColor(color(markColor))
    context.addPath(mark)
    context.fillPath()
    return context.makeImage()!
}

let playIcon = renderPlayIcon(size: 512)
for locale in playLocales {
    let directory = android.appendingPathComponent("app/src/main/play/listings/\(locale)/graphics/icon")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("1.png")
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, playIcon, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(url.path)") }
}

print("Wrote the launcher icon layers for \(modules.joined(separator: ", ")) and the Play icon under \(android.path)")
