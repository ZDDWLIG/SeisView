import CoreGraphics
import Foundation

public enum Palette: Sendable, Equatable, Hashable {
    case grayscale        // 灰度
    case redWhiteBlue     // 红白蓝（utils.py iop=4）
    case redWhiteBlack    // 红白黑（utils.py iop=2）
    case brownWhiteBlack  // 棕白黑（utils.py iop=1）
    case wiggle           // 波形变面积（非调色板，走独立渲染路径）
}

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
                // 取该 bin 的「支配幅度」（|max|≥|min| 取 max，否则取 min），
                // 保住 Decimator 计算出的 min/max 包络；否则全幅 bin 会被中点抹成灰色。
                let mxx = b.mx[x * h + y]
                let mnn = b.mn[x * h + y]
                let v = abs(mxx) >= abs(mnn) ? mxx : mnn
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

    public static func color(for p: Palette, t: Float) -> (UInt8, UInt8, UInt8) {
        switch p {
        case .grayscale:
            let g = UInt8(max(0, min(255, Int(t * 255))))
            return (g, g, g)
        case .wiggle:
            return (0, 0, 0)   // wiggle 不走 LUT；恒黑，仅保证 switch 穷尽
        case .redWhiteBlue, .redWhiteBlack, .brownWhiteBlack:
            let lut = luts[p]!
            let idx = min(255, max(0, Int(t * 255)))
            let c = lut[idx]
            return (c[0], c[1], c[2])
        }
    }

    // MARK: - 配色查找表（对照 utils.py 的 seismic(iop)）

    private static let luts: [Palette: [[UInt8]]] = [
        .redWhiteBlue: seismicLUT(iop: 4),
        .redWhiteBlack: seismicLUT(iop: 2),
        .brownWhiteBlack: seismicLUT(iop: 1),
    ]

    private static func linspace(_ a: Double, _ b: Double, _ n: Int) -> [Double] {
        guard n > 1 else { return [a] }
        return (0..<n).map { a + (b - a) * Double($0) / Double(n - 1) }
    }

    /// 生成 utils.py `seismic(iop)` 的 256×3 查找表（每行 [R,G,B] ∈ 0...255）。
    /// iop 语义：1=棕白黑、2=红白黑、4=红白蓝（3=蓝白红未使用）。
    private static func seismicLUT(iop: Int) -> [[UInt8]] {
        let N = 40, L = 40, sizeTotal = 128
        func ones(_ n: Int) -> [Double] { [Double](repeating: 1, count: n) }
        func zeros(_ n: Int) -> [Double] { [Double](repeating: 0, count: n) }

        let u1: [Double], u2: [Double], u3: [Double]
        switch iop {
        case 1:
            u1 = [Double](repeating: 0.5, count: N)
                + linspace(0.5, 1, sizeTotal - N)
                + linspace(1, 0, sizeTotal - N) + zeros(N)
            u2 = [Double](repeating: 0.25, count: N)
                + linspace(0.25, 1, sizeTotal - N)
                + linspace(1, 0, sizeTotal - N) + zeros(N)
            u3 = zeros(N) + linspace(0, 1, sizeTotal - N)
                + linspace(1, 0, sizeTotal - N) + zeros(N)
        case 2:
            u1 = ones(N) + ones(sizeTotal - N)
                + linspace(1, 0, sizeTotal - N) + zeros(N)
            u2 = zeros(N) + linspace(0, 1, sizeTotal - N)
                + linspace(1, 0, sizeTotal - N) + zeros(N)
            u3 = zeros(N) + linspace(0, 1, sizeTotal - N)
                + linspace(1, 0, sizeTotal - N) + zeros(N)
        case 3:
            u1 = zeros(N) + linspace(0, 1, sizeTotal - N - L / 2)
                + ones(L) + linspace(1, 0.5, sizeTotal - L / 2)
            u2 = zeros(N) + linspace(0, 1, sizeTotal - N - L / 2)
                + ones(L) + linspace(1, 0, sizeTotal - N - L / 2) + zeros(N)
            u3 = linspace(0.5, 1, sizeTotal - L / 2)
                + ones(L) + linspace(1, 0, sizeTotal - N - L / 2) + zeros(N)
        default: // 4
            u1 = ones(128) + linspace(1, 0, 128)
            u2 = linspace(0, 1, 128) + linspace(1, 0, 128)
            u3 = linspace(0, 1, 128) + ones(128)
        }

        return (0..<256).map { i in
            [UInt8(max(0, min(255, Int((u1[i] * 255).rounded())))),
             UInt8(max(0, min(255, Int((u2[i] * 255).rounded())))),
             UInt8(max(0, min(255, Int((u3[i] * 255).rounded()))))]
        }
    }
}
