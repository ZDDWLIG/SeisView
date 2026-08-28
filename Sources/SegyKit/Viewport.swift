import Foundation

/// 视口状态：纯值类型，渲染是纯函数 (SegyFile, Viewport) → CGImage。
/// 放在 SegyKit 而非 SeisView，是为了让测试 harness 够得着这里的纯逻辑
/// （SeisView 是可执行 target，无法被 import）。
public struct Viewport: Equatable, Sendable {
    public var firstTrace: Int = 0
    public var traceSpan: Int = 1200  // 显示的道数（屏宽上限，绝不一次解码全文件）
    public var firstSample: Int = 0
    public var sampleSpan: Int = 0    // 0 = 全部
    public var gain: GainMode = .maxAbs
    public var palette: Palette = .grayscale
    /// 剖面横向排列方式。改它要整体重赋值 viewport（铁律）。
    public var traceOrder: TraceOrder = .byTrace
    /// 百分位增益「保留百分比」，单位 %，范围 [90, 100]。真值只有它一个：
    /// gain 的百分位载荷由它派生（见 setClipPercent），两者不会漂移。
    public var clipPercent: Double = 98
    /// 屏宽上限：任何情况下 traceSpan 都不超过它，绝不一次解码整炮/整文件。
    public static let maxTraceSpan = 1200
    public init() {}
}

/// 视口对应的实际解码窗口。
public struct DecodePlan: Equatable, Sendable {
    /// 要解码的道区间（已夹在文件范围内）。
    public let traceRange: Range<Int>
    /// 要解码的采样区间；nil = 整道（横向平移常态，可走整道大块读）。
    public let sampleRange: Range<Int>?
    /// 解码后每道的采样数。
    public let decodedNs: Int
    /// min/max 分箱的目标高度。
    public let binHeight: Int
}

extension Viewport {
    /// 缩放级别 zoom ∈ [0,1] → 可见跨度 span。zoom=0 全展（maxSpan），zoom=1 放大到 minSpan。
    /// 「全采样」约定 sampleSpan==0 不在这里处理（这是纯数学映射），由 time 层换算。
    public static func zoomSpan(zoom: Double, minSpan: Int, maxSpan: Int) -> Int {
        let z = min(max(zoom, 0), 1)
        let span = Double(maxSpan) + (Double(minSpan) - Double(maxSpan)) * z
        return min(max(Int(span.rounded(.down)), minSpan), maxSpan)
    }

    /// 逆映射：可见跨度 → 缩放级别，夹到 [0,1]。
    public static func spanZoom(span: Int, minSpan: Int, maxSpan: Int) -> Double {
        guard maxSpan > minSpan else { return 0 }
        let f = Double(maxSpan - span) / Double(maxSpan - minSpan)
        return min(max(f, 0), 1)
    }

    /// time 滑块缩放级：sampleSpan==0（全采样）或 ==ns 都视为全采样 → 0。
    public static func timeZoom(span: Int, ns: Int) -> Double {
        guard span > 0, span < ns else { return 0 }
        return spanZoom(span: span, minSpan: 1, maxSpan: ns)
    }

    /// 视口 → 实际解码窗口，含全部越界钳制。
    /// 纵向缩放（sampleSpan>0）时只解码该采样窗并按窗高分箱；
    /// sampleSpan==0 为全采样、分箱高固定 800。
    public func decodePlan(nTraces: Int, ns: Int) -> DecodePlan {
        let span = min(max(1, traceSpan), min(max(nTraces, 1), Self.maxTraceSpan))
        let lo = min(max(0, firstTrace), max(0, nTraces - span))
        if sampleSpan > 0 {
            let ss = min(sampleSpan, ns)
            let fs = min(max(0, firstSample), max(0, ns - ss))
            return DecodePlan(traceRange: lo..<(lo + span),
                              sampleRange: fs..<(fs + ss),
                              decodedNs: ss,
                              binHeight: ss)
        }
        return DecodePlan(traceRange: lo..<(lo + span),
                          sampleRange: nil,
                          decodedNs: ns,
                          binHeight: 800)
    }

    /// 百分比可调范围。低于 90% 会把有效信号也裁掉，高于 100% 无意义。
    public static let clipPercentRange: ClosedRange<Double> = 90...100

    /// 「保留 P%」→ 对称的低/高百分位：lo=(1−P)/2，hi=1−lo。
    /// P=98 → (0.01, 0.99)，正是历史默认值，所以默认行为不变。
    public static func percentileBounds(clipPercent: Double) -> (Float, Float) {
        let p = min(max(clipPercent, clipPercentRange.lowerBound), clipPercentRange.upperBound)
        let lo = (100 - p) / 200
        return (Float(lo), Float(1 - lo))
    }

    /// 设置保留百分比。仅当当前增益方式是百分位时才同步重算 gain 载荷；
    /// 其他增益方式下只记住数值，等切回百分位时再用（见 setGainKind）。
    public mutating func setClipPercent(_ p: Double) {
        clipPercent = min(max(p, Self.clipPercentRange.lowerBound), Self.clipPercentRange.upperBound)
        if gain.kind == .percentiles { gain = Self.percentileGain(clipPercent) }
    }

    /// 切换增益方式，载荷用当前记住的参数重建（百分位用 clipPercent）。
    public mutating func setGainKind(_ k: GainKind) {
        switch k {
        case .percentiles: gain = Self.percentileGain(clipPercent)
        case .agc:         gain = .agc(100)
        case .perTrace:    gain = .perTrace
        case .maxAbs:      gain = .maxAbs
        }
    }

    private static func percentileGain(_ p: Double) -> GainMode {
        let (lo, hi) = percentileBounds(clipPercent: p)
        return .percentiles(lo, hi)
    }

    /// 中心锚横向缩放：保持当前视口中心那道不变，贴边时夹住。
    public mutating func zoomTraces(to newSpan: Int, total: Int) {
        let span = min(max(newSpan, 1), min(max(total, 1), Self.maxTraceSpan))
        let oldSpan = max(traceSpan, 1)
        let center = min(firstTrace + oldSpan / 2, max(total - 1, 0))
        traceSpan = span
        firstTrace = min(max(center - span / 2, 0), max(total - span, 0))
    }

    /// 相对缩放（横向）：span ← span × factor，中心锚。factor<1 放大（span 变小），
    /// factor>1 缩小（span 变大），factor==1 不动。连续乘算、贴边夹住。
    public mutating func zoomTraces(factor: Double, total: Int) {
        let cur = max(traceSpan, 1)
        zoomTraces(to: max(1, Int((Double(cur) * factor).rounded())), total: total)
    }

    /// 相对缩放（纵向）：全采样（sampleSpan==0）时以 ns 为基准连续乘算。
    /// factor<1 进入窗口化放大，factor>1 缩到 >=ns 时回到全采样。
    public mutating func zoomSamples(factor: Double, ns: Int) {
        if factor > 1 && sampleSpan == 0 { return }          // 全采样不能再缩小
        let cur = sampleSpan > 0 ? sampleSpan : ns
        let target = Int((Double(cur) * factor).rounded())
        if target >= ns {
            zoomSamples(to: 0, ns: ns)                        // 缩到满 → 全采样
        } else {
            zoomSamples(to: max(1, target), ns: ns)
        }
    }

    /// 中心锚纵向缩放：newSpan<=0 表示全采样。窗口化时保持中心采样点不动。
    public mutating func zoomSamples(to newSpan: Int, ns: Int) {
        if newSpan <= 0 {
            sampleSpan = 0; firstSample = 0; return
        }
        let span = min(max(newSpan, 1), max(ns, 1))
        let oldSpan = sampleSpan > 0 ? sampleSpan : ns
        let center = min(firstSample + oldSpan / 2, max(ns - 1, 0))
        sampleSpan = span
        firstSample = min(max(center - span / 2, 0), max(ns - span, 0))
    }

    /// 沿道号方向平移窗口；dTraces > 0 向后（更大道号），被限制在文件范围内。
    public mutating func pan(dTraces: Int, total: Int) {
        firstTrace = max(0, min(firstTrace + dTraces, max(0, total - max(traceSpan, 1))))
    }

    /// 回到刚打开文件时的显示窗口：位置与缩放归默认，
    /// 但**保留**显示参数（增益 / 百分比 / 调色板）——用户调好的口径不该被一键清掉。
    public mutating func resetView() {
        let d = Viewport()
        firstTrace = d.firstTrace
        traceSpan = d.traceSpan
        firstSample = d.firstSample
        sampleSpan = d.sampleSpan
    }

    /// 纵向可滚余量：全采样（sampleSpan == 0）时为 0，即没有可滚动的空间。
    public func maxFirstSample(ns: Int) -> Int {
        sampleSpan > 0 ? max(0, ns - min(sampleSpan, ns)) : 0
    }

    /// 沿采样轴平移窗口；dSamples > 0 向下（更大采样号），被限制在 [0, ns−sampleSpan]。
    public mutating func panSamples(dSamples: Int, ns: Int) {
        firstSample = max(0, min(firstSample + dSamples, maxFirstSample(ns: ns)))
    }

    /// 把 firstSample 夹回当前 sampleSpan 下的合法范围。缩放会改变可滚余量，
    /// 原本合法的 firstSample 可能越界，必须在改完 sampleSpan 后调用。
    public mutating func clampSamples(ns: Int) {
        firstSample = max(0, min(firstSample, maxFirstSample(ns: ns)))
    }

    /// 沿采样轴缩放（改变 sampleSpan）；timeFactor > 1 放大，< 1 缩小。
    public mutating func zoom(timeFactor: Double, ns: Int) {
        sampleSpan = max(10, min(ns, Int(Double(sampleSpan > 0 ? sampleSpan : ns) * timeFactor)))
        clampSamples(ns: ns)
    }
}
