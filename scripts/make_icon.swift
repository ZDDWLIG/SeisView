import Foundation
import CoreGraphics
import ImageIO

/// 生成 SeisView 的占位图标：深色底 + 几道地震 wiggle 波形。先画 1024 空间再按目标尺寸缩放。
func drawIcon(size: CGFloat) -> CGImage {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = size / 1024.0
    ctx.scaleBy(x: scale, y: scale)

    // 背景
    ctx.setFillColor(CGColor(red: 0.09, green: 0.13, blue: 0.19, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))

    // 几条垂直 wiggle 道，中心附近振荡
    let traceXs: [CGFloat] = [170, 340, 512, 684, 854]
    let colors: [CGColor] = [
        CGColor(red: 0.55, green: 0.62, blue: 0.70, alpha: 1),
        CGColor(red: 0.45, green: 0.72, blue: 0.85, alpha: 1),
        CGColor(red: 0.95, green: 0.62, blue: 0.35, alpha: 1),
        CGColor(red: 0.80, green: 0.70, blue: 0.90, alpha: 1),
        CGColor(red: 0.65, green: 0.82, blue: 0.75, alpha: 1),
    ]
    for (i, x) in traceXs.enumerated() {
        let amp: CGFloat = 55 + CGFloat(i % 3) * 25
        let freq: CGFloat = 0.011 + CGFloat(i) * 0.0022
        let phase: CGFloat = CGFloat(i) * 0.9
        let path = CGMutablePath()
        var first = true
        for y in stride(from: CGFloat(90), through: CGFloat(934), by: 10) {
            let a = sin(y * freq + phase) * amp
            let p = CGPoint(x: x + a, y: y)
            if first { path.move(to: p); first = false } else { path.addLine(to: p) }
        }
        ctx.setStrokeColor(colors[i % colors.count])
        ctx.setLineWidth(13)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.strokePath()
    }
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let outDir = URL(fileURLWithPath: "Resources/SeisView.iconset")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let specs: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, size) in specs {
    writePNG(drawIcon(size: size), to: outDir.appendingPathComponent(name))
}
print("iconset written to \(outDir.path)")
