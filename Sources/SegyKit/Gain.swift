import Foundation

public enum GainMode: Sendable, Equatable {
    case percentiles(Float, Float)   // 低/高百分位
    case agc(Int)                    // 滑动窗宽（采样）
    case perTrace                    // 每道 max 归一化
    case maxAbs                      // clip[0.5,99.5] + max_abs 训练口径
}

public enum Gain {
    static func percentile(_ arr: [Float], _ pct: Float) -> Float {
        guard !arr.isEmpty else { return 0 }
        let sorted = arr.sorted()
        let k = Int((Float(sorted.count - 1) * pct).rounded())
        return sorted[min(max(k, 0), sorted.count - 1)]
    }

    public static func apply(_ b: Binned, _ mode: GainMode) -> Binned {
        var mn = b.mn, mx = b.mx
        let lo: Float, hi: Float
        switch mode {
        case .percentiles(let l, let h):
            let all = mn + mx
            lo = percentile(all, l); hi = percentile(all, h)
        case .maxAbs:
            let all = mn + mx
            lo = percentile(all, 0.005); hi = percentile(all, 0.995)
        case .agc(let win):
            // 简化 AGC：每 bin 列在滑动窗内除以其局部 RMS 包络
            let half = win / 2
            var rms = [Float](repeating: 0, count: mx.count)
            for i in 0..<mx.count {
                let s = max(0, i - half), e = min(mx.count, i + half + 1)
                var acc: Float = 0
                for j in s..<e { acc += mx[j] * mx[j] }
                rms[i] = sqrt(acc / Float(e - s))
            }
            for i in 0..<mx.count {
                let r = max(rms[i], .leastNormalMagnitude)
                mn[i] /= r; mx[i] /= r
            }
            return Binned(w: b.w, h: b.h, mn: mn, mx: mx)
        case .perTrace:
            for t in 0..<b.w {
                var m: Float = 0
                for r in 0..<b.h { m = max(m, abs(mx[t * b.h + r]), abs(mn[t * b.h + r])) }
                let s = max(m, .leastNormalMagnitude)
                for r in 0..<b.h { mn[t * b.h + r] /= s; mx[t * b.h + r] /= s }
            }
            return Binned(w: b.w, h: b.h, mn: mn, mx: mx)
        }
        if hi == lo { return Binned(w: b.w, h: b.h, mn: mn, mx: mx) }
        for i in 0..<mn.count {
            mn[i] = max(-1, min(1, (mn[i] - lo) / (hi - lo) * 2 - 1))
            mx[i] = max(-1, min(1, (mx[i] - lo) / (hi - lo) * 2 - 1))
        }
        return Binned(w: b.w, h: b.h, mn: mn, mx: mx)
    }
}
