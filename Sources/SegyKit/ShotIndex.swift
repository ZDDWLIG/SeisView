import Foundation

/// 一个炮：FFID、首道序号与道数。
public struct Shot: Sendable, Equatable {
    public let ffid: Int; public let firstTrace: Int; public let count: Int
    public init(ffid: Int, firstTrace: Int, count: Int) {
        self.ffid = ffid; self.firstTrace = firstTrace; self.count = count
    }
}

/// 炮索引：抽样读道头 FFID，相邻抽样不同处用二分精确定位炮边界，再按 FFID 分段组装 Shot。
public enum ShotIndex {
    public static func build(reader: TraceReader, nTraces: Int, sampleStep: Int = 256) -> [Shot] {
        guard nTraces > 0 else { return [] }
        // 抽样 FFID
        var samples: [(trace: Int, ffid: Int)] = []
        var i = 0
        while i < nTraces {
            let h = reader.readTraceHeaders(range: i..<min(i + 1, nTraces))
            samples.append((i, h[0].ffid))
            i += sampleStep
        }
        if samples.last?.trace != nTraces - 1 {
            let h = reader.readTraceHeaders(range: (nTraces - 1)..<nTraces)
            samples.append((nTraces - 1, h[0].ffid))
        }
        // 相邻抽样 FFID 不同 → 二分定位边界
        var boundaries = [0]
        for k in 0..<(samples.count - 1) {
            let a = samples[k], b = samples[k + 1]
            if a.ffid == b.ffid { continue }
            var lo = a.trace, hi = b.trace
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                let h = reader.readTraceHeaders(range: mid..<mid + 1)
                if h[0].ffid == a.ffid { lo = mid } else { hi = mid }
            }
            boundaries.append(hi)
        }
        boundaries.append(nTraces)
        // 边界去重排序后组装 Shot（Set 会破坏顺序，改用排序去重）
        var uniq: [Int] = []
        for b in boundaries.sorted() where uniq.last != b { uniq.append(b) }
        var shots: [Shot] = []
        for k in 0..<(uniq.count - 1) {
            let first = uniq[k], next = uniq[k + 1]
            let h = reader.readTraceHeaders(range: first..<first + 1)
            shots.append(Shot(ffid: h[0].ffid, firstTrace: first, count: next - first))
        }
        return shots
    }
}
