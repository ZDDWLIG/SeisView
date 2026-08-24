import SwiftUI
import AppKit

/// 包裹自绘 NSImageView 的 SwiftUI 桥：把滚轮/捏合/光标事件转发到 DocumentModel。
struct SectionView: NSViewRepresentable {
    let model: DocumentModel
    let cursor: CursorStore
    let image: CGImage?
    /// 该 pane 对应文件的总道数（光标坐标换算用）。对比模式下各 pane 可不同。
    let totalTraces: Int

    func makeNSView(context: Context) -> SectionNSView {
        let v = SectionNSView()
        v.onScroll = { [weak model] d in
            MainActor.assumeIsolated { model?.pan(dTraces: d) }
        }
        v.onMagnify = { [weak model] f in
            MainActor.assumeIsolated { model?.zoom(timeFactor: f) }
        }
        v.onCursor = { [weak cursor] t in
            MainActor.assumeIsolated { cursor?.setTrace(t) }
        }
        v.onSelect = { [weak model] t in
            MainActor.assumeIsolated { model?.selectTrace(t) }
        }
        return v
    }

    func updateNSView(_ v: SectionNSView, context: Context) {
        v.image = image.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        v.imageScaling = .scaleAxesIndependently
        v.firstTrace = model.viewport.firstTrace
        v.imageWidth = image?.width ?? 0
        v.totalTraces = totalTraces
        v.refreshCursorIfInside()   // 平移后光标下的绝对道号已变化，就地重算
    }
}

/// 实际接收事件的 NSView。覆写 scrollWheel/magnify/mouseMoved 并把结果上报给回调。
/// AppKit 事件回调不一定被编译器视为 @MainActor，因此通过 MainActor.assumeIsolated
/// 把对 DocumentModel/CursorStore（@MainActor）的调用显式地放回主 actor（事件本身即在主线程）。
final class SectionNSView: NSImageView {
    var onScroll: ((Int) -> Void)?
    var onMagnify: ((Double) -> Void)?
    var onCursor: ((Int?) -> Void)?
    var onSelect: ((Int) -> Void)?

    // 更新于 updateNSView：用于把视图坐标换算成绝对道号。
    var firstTrace: Int = 0
    var imageWidth: Int = 0       // 渲染图像的像素宽 == 当前显示的道数
    var totalTraces: Int = 0

    private var pendingScroll: CGFloat = 0   // 累积触控板/滚轮的分数增量
    private var mouseInside = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        let ta = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(ta)
    }

    override func scrollWheel(with event: NSEvent) {
        // scrollingDeltaY > 0 → 向后平移（更大道号）；按 1 点 ≈ 1 道换算，累积到整道再动。
        pendingScroll += event.scrollingDeltaY
        let step = Int((pendingScroll / 1.0).rounded(.towardZero))
        if step != 0 {
            pendingScroll -= CGFloat(step)
            onScroll?(step)
        }
    }

    override func magnify(with event: NSEvent) {
        // 每次捏合事件的 magnification 很小，1 + m 作为乘法因子累积到 sampleSpan。
        onMagnify?(1.0 + event.magnification)
    }

    override func mouseDown(with event: NSEvent) {
        // 点击选中光标下的绝对道号，喂给 DocumentModel.selectTrace。
        if let t = trace(at: convert(event.locationInWindow, from: nil)) {
            onSelect?(t)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        reportCursor(at: event.locationInWindow)
    }

    override func mouseEntered(with event: NSEvent) {
        mouseInside = true
        reportCursor(at: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        mouseInside = false
        onCursor?(nil)
    }

    /// 平移后鼠标未移动，但 firstTrace 已变：若光标仍在视图内则按当前鼠标位置重算。
    func refreshCursorIfInside() {
        guard mouseInside, let w = window else { return }
        reportCursor(at: w.mouseLocationOutsideOfEventStream)
    }

    private func reportCursor(at windowPoint: NSPoint) {
        onCursor?(trace(at: convert(windowPoint, from: nil)))
    }

    /// 视图坐标 → 绝对道号（夹到 [0, totalTraces-1]）；视图/图像宽度非法时返回 nil。
    private func trace(at pt: NSPoint) -> Int? {
        guard bounds.width > 0, imageWidth > 0 else { return nil }
        let frac = max(0, min(1, pt.x / bounds.width))
        let raw = firstTrace + Int(frac * CGFloat(imageWidth))
        return min(max(0, raw), max(0, totalTraces - 1))
    }
}
