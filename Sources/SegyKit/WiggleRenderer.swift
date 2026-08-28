import CoreGraphics
import Foundation

/// 波形变面积渲染：输入按道排列的解码样本（nTraces × ns），目标宽高 (width, height)。
/// 每道独立归一化到自身 maxAbs（wiggle 标准做法），黑色填充、白底，时间向下（采样 0 在顶部）。
public enum WiggleRenderer {
    public static func makeImage(_ samples: [Float], ns: Int, nTraces: Int,
                                 width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, ns > 0, nTraces > 0 else { return nil }
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
        ctx.setLineWidth(1)

        let colW = CGFloat(max(1, width / nTraces))
        let stride = max(1, ns / height)
        let n = (ns + stride - 1) / stride
        let ampScale = CGFloat(max(1, colW / 2 - 1))

        for t in 0..<min(nTraces, width) {
            let base = t * ns
            var m: Float = 0
            for s in 0..<ns { m = max(m, abs(samples[base + s])) }
            if m <= 0 { continue }
            let cx = CGFloat(t) * colW + colW / 2
            let fill = CGMutablePath()
            let line = CGMutablePath()
            var started = false
            for row in 0..<n {
                let si = min(row * stride, ns - 1)
                let v = CGFloat(samples[base + si] / m)     // [-1,1]
                let x = cx + v * ampScale
                let y = CGFloat(height - 1) - CGFloat(row) * CGFloat(height - 1) / CGFloat(max(1, n - 1))
                if !started {
                    fill.move(to: CGPoint(x: cx, y: y))
                    line.move(to: CGPoint(x: x, y: y))
                    started = true
                } else {
                    line.addLine(to: CGPoint(x: x, y: y))
                }
                fill.addLine(to: CGPoint(x: x, y: y))
            }
            fill.addLine(to: CGPoint(x: cx, y: 0))   // 收回到底部零线
            fill.closeSubpath()
            ctx.addPath(fill); ctx.fillPath()
            ctx.addPath(line); ctx.strokePath()
        }
        return ctx.makeImage()
    }
}
