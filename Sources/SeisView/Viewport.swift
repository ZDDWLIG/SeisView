import Foundation
import SegyKit

public struct Viewport: Equatable {
    public var firstTrace: Int = 0
    public var traceSpan: Int = 1200  // 显示的道数（屏宽上限，绝不一次解码全文件）
    public var firstSample: Int = 0
    public var sampleSpan: Int = 0    // 0 = 全部
    public var gain: GainMode = .percentiles(0.01, 0.99)
    public var palette: Palette = .grayscale
    public init() {}
}

extension Viewport {
    /// 沿道号方向平移窗口；dTraces > 0 向后（更大道号），被限制在文件范围内。
    public mutating func pan(dTraces: Int, total: Int) {
        firstTrace = max(0, min(firstTrace + dTraces, max(0, total - max(traceSpan, 1))))
    }

    /// 沿采样轴缩放（改变 sampleSpan）；timeFactor > 1 放大，< 1 缩小。
    /// 注意：render() 目前未使用 sampleSpan（传 sampleRange: nil），
    /// 缩放只更新状态与状态栏，垂直方向的渲染接线留待后续。
    public mutating func zoom(timeFactor: Double, ns: Int) {
        sampleSpan = max(10, min(ns, Int(Double(sampleSpan > 0 ? sampleSpan : ns) * timeFactor)))
    }
}
