import Foundation

/// 道头读取能力的最小抽象：OffsetIndexBuilder 只依赖「按区间读道头」。
/// 抽成协议是为了让测试注入假 source，不必构造真实 SegyFile / 磁盘文件。
public protocol TraceHeaderSource {
    func readTraceHeaders(range: Range<Int>) -> [TraceHeader]
}

/// 全文件排序置换 + 每炮起始位置。两种排列（有符号 / 绝对值）共享炮边界，
/// 因此道头只读一次、产出两套 perm。
/// permSigned[k] = 有符号 offset 排序下第 k 个位置对应文件的真实道号。
/// permAbs[k]    = 绝对值 offset 排序下第 k 个位置对应文件的真实道号。
/// shotStarts[i] = 第 i 炮在 perm 中的起始下标（两套 perm 共享，与 build 输入的 shots 一一对应）。
public struct OffsetIndex: Sendable {
    public let permSigned: [Int]
    public let permAbs: [Int]
    public let shotStarts: [Int]
    public init(permSigned: [Int], permAbs: [Int], shotStarts: [Int]) {
        self.permSigned = permSigned; self.permAbs = permAbs; self.shotStarts = shotStarts
    }
}

public enum OffsetIndexBuilder {
    /// 对每个 shot 读该炮道头，产出两套排列（有符号 offset 升序、绝对值 offset 升序）。
    /// 有符号：排序键 (offset, 道号)，并列按道号稳定。
    /// 绝对值：排序键 (|offset|, offset, 道号)，|offset| 并列时负 offset 在前。
    /// 输入 shots 必须已按 firstTrace 升序（ShotIndex 的产物即如此）。
    public static func build(shots: [Shot], source: TraceHeaderSource) -> OffsetIndex {
        var permSigned: [Int] = []
        var permAbs: [Int] = []
        var starts: [Int] = []
        for shot in shots {
            starts.append(permSigned.count)
            let headers = source.readTraceHeaders(range: shot.firstTrace..<(shot.firstTrace + shot.count))
            let traces = headers.enumerated()
                .map { (trace: shot.firstTrace + $0.offset, offset: $0.element.offset) }
            let sortedSigned = traces.sorted { ($0.offset, $0.trace) < ($1.offset, $1.trace) }
            let sortedAbs = traces.sorted {
                (abs($0.offset), $0.offset, $0.trace) < (abs($1.offset), $1.offset, $1.trace)
            }
            permSigned.append(contentsOf: sortedSigned.map { $0.trace })
            permAbs.append(contentsOf: sortedAbs.map { $0.trace })
        }
        starts.append(permSigned.count)
        return OffsetIndex(permSigned: permSigned, permAbs: permAbs, shotStarts: starts)
    }
}

public enum OffsetIndexLookup {
    /// 按排列方式选对应 perm；byTrace 也回落 permSigned（该路径不会被调用）。
    private static func perm(_ idx: OffsetIndex, order: TraceOrder) -> [Int] {
        order == .byOffsetAbs ? idx.permAbs : idx.permSigned
    }

    public static func traceAt(_ idx: OffsetIndex, position: Int, order: TraceOrder) -> Int? {
        let p = perm(idx, order: order)
        guard p.indices.contains(position) else { return nil }
        return p[position]
    }

    public static func traces(_ idx: OffsetIndex, positions: Range<Int>, order: TraceOrder) -> [Int] {
        let p = perm(idx, order: order)
        return positions.map { p[$0] }
    }

    /// 第 shotIndex 炮在排序剖面里的位置区间；越界返回 nil。
    /// 依赖 shotStarts 末尾多存的「总道数」哨兵值（两套 perm 同长，共享 shotStarts）。
    public static func positionRange(_ idx: OffsetIndex, shotIndex: Int) -> Range<Int>? {
        guard idx.shotStarts.indices.contains(shotIndex),
              shotIndex + 1 < idx.shotStarts.count else { return nil }
        return idx.shotStarts[shotIndex]..<idx.shotStarts[shotIndex + 1]
    }
}
