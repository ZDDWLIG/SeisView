import Foundation

public enum GainMode: Sendable, Equatable, Hashable {
    case percentiles(Float, Float)   // 低/高百分位
    case agc(Int)                    // 滑动窗宽（采样）
    case perTrace                    // 每道 max 归一化
    case maxAbs                      // clip[0.5,99.5] + max_abs 训练口径
}

/// GainMode 去掉载荷后的「种类」。工具栏 Picker 绑定它而不是 GainMode 本身：
/// GainMode 的载荷可调（百分位随滑块变、AGC 窗宽可变），一旦载荷偏离硬编码的
/// tag，Picker 的 selection 就匹配不上任何选项、控件会显示空白。
public enum GainKind: Sendable, Equatable, Hashable, CaseIterable {
    case percentiles, agc, perTrace, maxAbs
}

extension GainMode {
    /// 去掉载荷的种类，供 Picker 之类只关心「哪一种」的地方使用。
    public var kind: GainKind {
        switch self {
        case .percentiles: return .percentiles
        case .agc:         return .agc
        case .perTrace:    return .perTrace
        case .maxAbs:      return .maxAbs
        }
    }
}

public enum Gain {
    /// O(n) 直方图近似百分位：在 [min,max] 上开 4096 桶，累加计数到 pct 分位所在桶。
    /// 返回该桶下界（原 nearest-rank 语义，误差 ≤ 1 桶宽），对增益裁剪足够。
    static func percentile(_ arr: [Float], _ pct: Float) -> Float {
        guard !arr.isEmpty else { return 0 }
        var lo = arr[0], hi = arr[0]
        for v in arr {
            if v < lo { lo = v }
            if v > hi { hi = v }
        }
        guard hi > lo else { return lo }
        let buckets = 4096
        let inv = Double(buckets - 1) / Double(hi - lo)
        var counts = [Int](repeating: 0, count: buckets)
        for v in arr {
            let idx = Int(((Double(v) - Double(lo)) * inv).rounded(.down))
            counts[min(max(idx, 0), buckets - 1)] += 1
        }
        let target = Int((Float(arr.count - 1) * pct).rounded())
        var acc = 0
        for i in 0..<buckets {
            acc += counts[i]
            if acc > target {
                return Float(Double(lo) + Double(i) / inv)
            }
        }
        return hi
    }

    public static func apply(_ b: Binned, _ mode: GainMode) -> Binned {
        var mn = b.mn, mx = b.mx
        let lo: Float, hi: Float
        switch mode {
        case .percentiles(let l, let h):
            let all = mn + mx
            lo = percentile(all, l); hi = percentile(all, h)
        case .maxAbs:
            // 训练口径 §7.5：clip[0.5,99.5] 后按 max_abs 归一化，负/正对称。
            let all = mn + mx
            lo = percentile(all, 0.005); hi = percentile(all, 0.995)
            let scale = max(abs(lo), abs(hi))
            guard scale > 0 else { return Binned(w: b.w, h: b.h, mn: mn, mx: mx) }
            for i in 0..<mn.count {
                mn[i] = max(-1, min(1, mn[i] / scale))
                mx[i] = max(-1, min(1, mx[i] / scale))
            }
            return Binned(w: b.w, h: b.h, mn: mn, mx: mx)
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
