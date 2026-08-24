import CoreGraphics
import Foundation

public enum Palette: Sendable { case grayscale, seismic }

public enum Rasterizer {
    public static func makeImage(_ b: Binned, palette: Palette) -> CGImage {
        let w = b.w, h = b.h
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        // 每个像素列取该列所有 bin 的 mx/mn 覆盖区间中值作为亮度
        for x in 0..<w {
            var colMax: Float = -.greatestFiniteMagnitude, colMin: Float = .greatestFiniteMagnitude
            for y in 0..<h {
                colMax = max(colMax, b.mx[x * h + y]); colMin = min(colMin, b.mn[x * h + y])
            }
            let amp = max(abs(colMax), abs(colMin))
            for y in 0..<h {
                let v = (b.mx[x * h + y] + b.mn[x * h + y]) * 0.5
                let t = amp > 0 ? (v / amp) * 0.5 + 0.5 : 0.5   // 归一到 [0,1]
                let (r, g, bl) = color(for: palette, t: t)
                let i = (y * w + x) * 4
                pixels[i] = r; pixels[i+1] = g; pixels[i+2] = bl; pixels[i+3] = 255
            }
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    static func color(for p: Palette, t: Float) -> (UInt8, UInt8, UInt8) {
        switch p {
        case .grayscale:
            let g = UInt8(max(0, min(255, Int(t * 255))))
            return (g, g, g)
        case .seismic:   // 蓝(-1)→白(0)→红(+1)
            let v = max(-1, min(1, t * 2 - 1))
            if v < 0 {
                let k = UInt8((1 + v) * 255)
                return (k, k, 255)
            } else {
                let k = UInt8((1 - v) * 255)
                return (255, k, k)
            }
        }
    }
}
