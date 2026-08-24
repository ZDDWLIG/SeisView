public struct Binned: Sendable {
    public let w: Int; public let h: Int
    public let mn: [Float]; public let mx: [Float]
    public init(w: Int, h: Int, mn: [Float], mx: [Float]) {
        self.w = w; self.h = h; self.mn = mn; self.mx = mx
    }
}

public enum Decimator {
    public static func minMax(_ src: [Float], ns: Int, nTraces: Int, h: Int) -> Binned {
        let binSize = max(1, ns / h)
        let hh = min(h, ns)
        var mn = [Float](repeating: .greatestFiniteMagnitude, count: nTraces * hh)
        var mx = [Float](repeating: -.greatestFiniteMagnitude, count: nTraces * hh)
        src.withUnsafeBufferPointer { sb in
            let p = sb.baseAddress!
            for t in 0..<nTraces {
                for s in 0..<ns {
                    let r = min(s / binSize, hh - 1)
                    let v = p[t * ns + s]
                    let idx = t * hh + r
                    if v < mn[idx] { mn[idx] = v }
                    if v > mx[idx] { mx[idx] = v }
                }
            }
        }
        return Binned(w: nTraces, h: hh, mn: mn, mx: mx)
    }
}
