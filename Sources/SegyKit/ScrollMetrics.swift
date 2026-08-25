import Foundation

/// 滚动条滑块几何：把「总量 / 可见跨度 / 起点」映射成轨道上的像素长度与偏移，并能反算回索引。
///
/// 放在 SegyKit 而非视图层，是因为这纯粹是算术、没有任何 SwiftUI 依赖，放这儿才测得到。
/// 不用 NSScrollView/NSScroller：本应用没有真实的可滚动内容，是按需渲染 589k 道的视口，
/// AppKit 那套 contentSize/documentView 模型对不上。
public struct ScrollMetrics: Equatable, Sendable {
    /// 是否有可滚动余量。跨度覆盖全部（含 span==0 的「全采样铺满」）时为 false，
    /// 此时滑块占满轨道并置灰。
    public let enabled: Bool
    /// 滑块像素长度。按 span/total 比例，但不短于 minKnob——
    /// 589k 道里看 1200 道，按比例算不足 1px，会变成抓不住的滑块。
    public let knobLength: Double
    /// 滑块相对轨道起点的像素偏移。
    public let knobOffset: Double
    /// 滑块能到达的最大偏移（= 轨道长 − 滑块长）。
    public let maxKnobOffset: Double
    /// first 的最大合法值（= total − span）。
    public let maxIndex: Int

    public init(track: Double, total: Int, span: Int, first: Int = 0, minKnob: Double = 24) {
        let scrollable = track > 0 && total > 0 && span > 0 && span < total
        enabled = scrollable
        maxIndex = scrollable ? total - span : 0
        // 比例长度夹在 [minKnob, track] 内：minKnob 可能比轨道本身还长（窗口极窄）。
        let proportional = track * Double(span) / Double(max(total, 1))
        knobLength = scrollable ? min(track, max(minKnob, proportional)) : max(track, 0)
        maxKnobOffset = max(0, track - knobLength)
        if scrollable && maxIndex > 0 {
            let f = Double(min(max(first, 0), maxIndex)) / Double(maxIndex)
            knobOffset = maxKnobOffset * f
        } else {
            knobOffset = 0
        }
    }

    /// 反算：滑块像素偏移 → 起点索引，夹在 [0, maxIndex]。
    /// 禁用时恒为 0，保证拖动一条禁用的滚动条不会改动视口。
    public func index(atKnobOffset offset: Double) -> Int {
        guard enabled, maxKnobOffset > 0, maxIndex > 0 else { return 0 }
        let f = min(max(offset / maxKnobOffset, 0), 1)
        return min(max(Int((f * Double(maxIndex)).rounded()), 0), maxIndex)
    }
}
