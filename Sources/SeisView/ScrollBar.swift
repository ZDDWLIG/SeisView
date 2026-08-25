import SwiftUI
import SegyKit

/// 自绘滚动条。几何计算全在 `SegyKit.ScrollMetrics`（纯函数、可测），这里只负责画和收手势。
///
/// 为什么不用 NSScrollView/NSScroller：本应用没有真实的可滚动内容，剖面是按当前视口
/// 按需解码渲染的（589k 道绝不整文件铺开），AppKit 的 contentSize/documentView 模型对不上。
struct ScrollBar: View {
    enum Orientation { case horizontal, vertical }

    let orientation: Orientation
    /// 总量：水平为总道数，垂直为总采样数。
    let total: Int
    /// 可见跨度：水平为 traceSpan，垂直为 sampleSpan（0 = 全采样铺满 → 禁用）。
    let span: Int
    /// 当前起点：水平为 firstTrace，垂直为 firstSample。
    let first: Int
    /// 拖动滑块 → 绝对定位。
    let onScrollTo: (Int) -> Void
    /// 点击轨道空白 → 翻页（−1 上一屏 / +1 下一屏）。
    let onPage: (Int) -> Void

    static let thickness: CGFloat = 12
    private static let minKnob: CGFloat = 24

    /// 拖动起点处的滑块偏移。用「起点 + 累计位移」而不是「当前偏移 + 增量」，
    /// 避免回调改动 first 后 knobOffset 变化造成的自反馈抖动。
    @State private var dragStartOffset: Double?

    var body: some View {
        GeometryReader { geo in
            let track = orientation == .horizontal ? geo.size.width : geo.size.height
            let m = ScrollMetrics(track: Double(track), total: total, span: span,
                                  first: first, minKnob: Double(Self.minKnob))
            ZStack(alignment: .topLeading) {
                Color(nsColor: .underPageBackgroundColor)
                    .contentShape(Rectangle())
                    .gesture(trackGesture(m))
                knob(m)
            }
        }
        .frame(
            width: orientation == .vertical ? Self.thickness : nil,
            height: orientation == .horizontal ? Self.thickness : nil
        )
        .overlay(alignment: orientation == .horizontal ? .top : .leading) { Divider() }
    }

    @ViewBuilder
    private func knob(_ m: ScrollMetrics) -> some View {
        let inset: CGFloat = 2
        RoundedRectangle(cornerRadius: (Self.thickness - inset * 2) / 2)
            .fill(Color(nsColor: m.enabled ? .tertiaryLabelColor : .quaternaryLabelColor))
            .frame(
                width: orientation == .horizontal ? CGFloat(m.knobLength) : Self.thickness - inset * 2,
                height: orientation == .vertical ? CGFloat(m.knobLength) : Self.thickness - inset * 2
            )
            .offset(
                x: orientation == .horizontal ? CGFloat(m.knobOffset) : inset,
                y: orientation == .vertical ? CGFloat(m.knobOffset) : inset
            )
            .gesture(knobGesture(m))
            .allowsHitTesting(m.enabled)
    }

    /// 拖滑块：绝对定位。禁用时不响应（ScrollMetrics.index 在禁用时恒返回 0，双重保险）。
    private func knobGesture(_ m: ScrollMetrics) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                guard m.enabled else { return }
                let start = dragStartOffset ?? m.knobOffset
                if dragStartOffset == nil { dragStartOffset = m.knobOffset }
                let delta = orientation == .horizontal ? g.translation.width : g.translation.height
                onScrollTo(m.index(atKnobOffset: start + Double(delta)))
            }
            .onEnded { _ in dragStartOffset = nil }
    }

    /// 点轨道空白：按下位置在滑块前/后决定上一屏/下一屏。位移过大视为拖拽，不翻页。
    private func trackGesture(_ m: ScrollMetrics) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { g in
                guard m.enabled else { return }
                let moved = orientation == .horizontal ? g.translation.width : g.translation.height
                guard abs(moved) < 3 else { return }
                let pos = orientation == .horizontal ? g.startLocation.x : g.startLocation.y
                onPage(Double(pos) < m.knobOffset ? -1 : 1)
            }
    }
}

/// 给剖面内容加上右侧竖条 + 底部横条，右下角留一个与滚动条同宽的空白补角。
/// 单文件与对比模式共用（对比模式本就共享同一个 viewport，天然联动）。
struct ScrolledSection<Content: View>: View {
    @ObservedObject var model: DocumentModel
    /// 水平方向总道数。对比模式下以第一个文件为准（与状态栏口径一致）。
    let totalTraces: Int
    /// 垂直方向总采样数。
    let totalSamples: Int
    @ViewBuilder var content: Content

    var body: some View {
        let vp = model.viewport
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                content
                ScrollBar(orientation: .vertical,
                          total: totalSamples,
                          span: vp.sampleSpan,
                          first: vp.firstSample,
                          onScrollTo: { model.scrollToSample($0) },
                          onPage: { model.panSamples(dSamples: $0 * max(vp.sampleSpan, 1)) })
            }
            HStack(spacing: 0) {
                ScrollBar(orientation: .horizontal,
                          total: totalTraces,
                          span: vp.traceSpan,
                          first: vp.firstTrace,
                          onScrollTo: { model.scrollToTrace($0) },
                          onPage: { model.pan(dTraces: $0 * max(vp.traceSpan, 1)) })
                // 补角：两条滚动条交汇处，避免横条被竖条挤短造成的错位
                Color(nsColor: .underPageBackgroundColor)
                    .frame(width: ScrollBar.thickness, height: ScrollBar.thickness)
            }
        }
    }
}
