import Foundation

/// 道头读取能力的最小抽象：OffsetIndexBuilder 只依赖「按区间读道头」。
/// 抽成协议是为了让测试注入假 source，不必构造真实 SegyFile / 磁盘文件。
public protocol TraceHeaderSource {
    func readTraceHeaders(range: Range<Int>) -> [TraceHeader]
}

/// 全文件排序置换 + 每炮起始位置。
/// perm[k] = 排序后第 k 个位置对应文件的真实道号。
/// shotStarts[i] = 第 i 炮在 perm 中的起始下标（与 build 输入的 shots 一一对应）。
public struct OffsetIndex: Sendable {
    public let perm: [Int]
    public let shotStarts: [Int]
    public init(perm: [Int], shotStarts: [Int]) {
        self.perm = perm; self.shotStarts = shotStarts
    }
}

public enum OffsetIndexBuilder {
    /// 对每个 shot 读该炮道头，炮内按 offset 升序（并列按道号稳定）排，产出置换 + 每炮起始位置。
    /// 输入 shots 必须已按 firstTrace 升序（ShotIndex 的产物即如此）。
    public static func build(shots: [Shot], source: TraceHeaderSource) -> OffsetIndex {
        var perm: [Int] = []
        var starts: [Int] = []
        for shot in shots {
            starts.append(perm.count)
            let headers = source.readTraceHeaders(range: shot.firstTrace..<(shot.firstTrace + shot.count))
            // 稳定排序：先按 offset，再按真实道号。
            let sorted = headers.enumerated()
                .map { (trace: shot.firstTrace + $0.offset, offset: $0.element.offset) }
                .sorted { ($0.offset, $0.trace) < ($1.offset, $1.trace) }
            perm.append(contentsOf: sorted.map { $0.trace })
        }
        starts.append(perm.count)
        return OffsetIndex(perm: perm, shotStarts: starts)
    }
}

public enum OffsetIndexLookup {
    public static func traceAt(_ idx: OffsetIndex, position: Int) -> Int? {
        guard idx.perm.indices.contains(position) else { return nil }
        return idx.perm[position]
    }

    public static func traces(_ idx: OffsetIndex, positions: Range<Int>) -> [Int] {
        positions.map { idx.perm[$0] }
    }

    /// 第 shotIndex 炮在排序剖面里的位置区间；越界返回 nil。
    /// 依赖 shotStarts 末尾多存的「总道数」哨兵值。
    public static func positionRange(_ idx: OffsetIndex, shotIndex: Int) -> Range<Int>? {
        guard idx.shotStarts.indices.contains(shotIndex),
              shotIndex + 1 < idx.shotStarts.count else { return nil }
        return idx.shotStarts[shotIndex]..<idx.shotStarts[shotIndex + 1]
    }
}
