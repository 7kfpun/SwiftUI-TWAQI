//
//  DrawVisionAppIcon.swift
//  tools
//
//  Draws the visionOS app icon's three parallax layers from the iOS icon's
//  design: the orange-to-purple sky at the back, the cloud in the middle, the
//  warning sign in front. Vector-drawn rather than cut from the iOS raster,
//  which has its rounded-square corners and the cloud/sign overlap baked in.
//
//  visionOS masks the stack to a circle and adds depth, shadow and specular
//  highlights itself, so the layers carry none of their own.
//
//  Usage:
//    swiftc -O tools/DrawVisionAppIcon.swift -o /tmp/draw-icon
//    /tmp/draw-icon TWAQIVision/Assets.xcassets/AppIcon.solidimagestack
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let stack = URL(fileURLWithPath: CommandLine.arguments[1])

/// The artwork is laid out on the iOS icon's 1024 grid, then shrunk about the
/// centre so nothing reaches the circle's edge.
let artworkScale: CGFloat = 0.84

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ stops: [(CGFloat, UInt32)]) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: stops.map { color($0.1) } as CFArray,
        locations: stops.map(\.0)
    )!
}

/// A transparent (or, for the back layer, opaque) canvas with y running down,
/// as on the iOS icon the coordinates were measured from.
func render(_ name: String, opaque: Bool, scaled: Bool, draw: (CGContext) -> Void) throws {
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue
    )!
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: 1, y: -1)
    if scaled {
        let centre = CGFloat(size) / 2
        context.translateBy(x: centre, y: centre)
        context.scaleBy(x: artworkScale, y: artworkScale)
        context.translateBy(x: -centre, y: -centre)
    }
    draw(context)

    let directory = stack.appendingPathComponent("\(name).solidimagestacklayer/Content.imageset")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("\(name).png")
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(url.path)") }

    try json(["images": [["filename": "\(name).png", "idiom": "vision", "scale": "2x"]], "info": info])
        .write(to: directory.appendingPathComponent("Contents.json"))
    try json(["info": info])
        .write(to: stack.appendingPathComponent("\(name).solidimagestacklayer/Contents.json"))
}

let info: [String: Any] = ["author": "xcode", "version": 1]

func json(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
}

// MARK: Back: the sky, full bleed and opaque.

try render("Back", opaque: true, scaled: false) { context in
    let sky = gradient([(0, 0xFF7733), (0.5, 0xD6233A), (1, 0x73008C)])
    context.drawLinearGradient(
        sky, start: .zero, end: CGPoint(x: size, y: size),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
}

// MARK: Middle: the cloud.

try render("Middle", opaque: false, scaled: true) { context in
    let cloud = CGMutablePath()
    cloud.addEllipse(in: CGRect(x: 548 - 195, y: 130, width: 390, height: 390))   // crown
    cloud.addEllipse(in: CGRect(x: 225, y: 298, width: 210, height: 210))         // left shoulder
    cloud.addEllipse(in: CGRect(x: 580, y: 330, width: 360, height: 360))         // right lobe, down to the base
    // Flat base, square-ended: a circle rounds off its left end, and it stops
    // at the right lobe's centre, where the lobe's bottom meets it tangentially.
    cloud.addEllipse(in: CGRect(x: 64, y: 415, width: 275, height: 275))
    cloud.addRect(CGRect(x: 201, y: 415, width: 760 - 201, height: 275))
    context.addPath(cloud)
    context.clip()
    let fill = gradient([(0, 0xF9D6D1), (0.55, 0xFAE3E4), (1, 0xFCEEF0)])
    context.drawLinearGradient(fill, start: CGPoint(x: 0, y: 130), end: CGPoint(x: 0, y: 690), options: [])
}

// MARK: Front: the warning sign.

try render("Front", opaque: false, scaled: true) { context in
    // Rounded triangle: each corner is an arc tangent to its two sides.
    let top = CGPoint(x: 512, y: 455), left = CGPoint(x: 292, y: 848), right = CGPoint(x: 732, y: 848)
    let triangle = CGMutablePath()
    triangle.move(to: CGPoint(x: (left.x + right.x) / 2, y: left.y))
    triangle.addArc(tangent1End: right, tangent2End: top, radius: 44)
    triangle.addArc(tangent1End: top, tangent2End: left, radius: 44)
    triangle.addArc(tangent1End: left, tangent2End: right, radius: 44)
    triangle.closeSubpath()

    context.saveGState()
    context.addPath(triangle)
    context.clip()
    let fill = gradient([(0, 0xFFD503), (1, 0xFEC401)])
    context.drawLinearGradient(fill, start: CGPoint(x: 0, y: top.y), end: CGPoint(x: 0, y: left.y), options: [])
    context.restoreGState()

    // The exclamation mark: a bar tapering towards its foot, then the dot.
    context.setFillColor(color(0x222222))
    let bar = CGMutablePath()
    bar.move(to: CGPoint(x: 482, y: 600))
    bar.addLine(to: CGPoint(x: 542, y: 600))
    bar.addLine(to: CGPoint(x: 530, y: 742))
    bar.addLine(to: CGPoint(x: 494, y: 742))
    bar.closeSubpath()
    context.addPath(bar)
    context.fillPath()
    context.fillEllipse(in: CGRect(x: 482, y: 584, width: 60, height: 32))   // rounded top of the bar
    context.fillEllipse(in: CGRect(x: 494, y: 726, width: 36, height: 32))   // rounded foot
    context.fillEllipse(in: CGRect(x: 484, y: 768, width: 56, height: 56))   // dot
}

// Front first: the order the layers stack in, nearest the viewer at the top.
try json([
    "info": info,
    "layers": [
        ["filename": "Front.solidimagestacklayer"],
        ["filename": "Middle.solidimagestacklayer"],
        ["filename": "Back.solidimagestacklayer"],
    ],
]).write(to: stack.appendingPathComponent("Contents.json"))

print("Wrote \(stack.path)")
