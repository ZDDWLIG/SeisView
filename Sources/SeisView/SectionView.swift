import SwiftUI
import AppKit

/// 包裹自绘 NSImageView 的 SwiftUI 桥：把滚轮/捏合/光标事件转发到 DocumentModel。
struct SectionView: NSViewRepresentable {
    let model: DocumentModel
    let cursor: CursorStore
    let image: CGImage?
    /// 该 pane 对应文件的总道数（光标坐标换算用）。对比模式下各 pane 可不同。
    let totalTraces: Int
    /// 局部放大模式。作为值参数传入（而非读 model），保证 SwiftUI 检测到变化并触发 updateNSView。
    let zoomRectMode: Bool

    func makeNSView(context: Context) -> SectionNSView {
        let v = SectionNSView()
        v.onScroll = { [weak model] d in
            MainActor.assumeIsolated { model?.pan(dTraces: d) }
        }
        v.onScrollSamples = { [weak model] d in
            MainActor.assumeIsolated { model?.panSamples(dSamples: d) }
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
        v.onZoomRect = { [weak model] r in
            MainActor.assumeIsolated { model?.zoomToRect(normalized: r) }
        }
        return v
    }

    func updateNSView(_ v: SectionNSView, context: Context) {
        v.image = image.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        v.imageScaling = .scaleAxesIndependently
        v.firstTrace = model.viewport.firstTrace
        v.imageWidth = image?.width ?? 0
        v.totalTraces = totalTraces
        v.zoomRectMode = zoomRectMode
        v.refreshCursorIfInside()   // 平移后光标下的绝对道号已变化，就地重算
    }
}

/// 实际接收事件的 NSView。覆写 scrollWheel/magnify/mouseMoved 并把结果上报给回调。
/// AppKit 事件回调不一定被编译器视为 @MainActor，因此通过 MainActor.assumeIsolated
/// 把对 DocumentModel/CursorStore（@MainActor）的调用显式地放回主 actor（事件本身即在主线程）。
final class SectionNSView: NSImageView {
    var onScroll: ((Int) -> Void)?          // 道号方向平移
    var onScrollSamples: ((Int) -> Void)?   // 采样方向平移
    var onMagnify: ((Double) -> Void)?
    var onCursor: ((Int?) -> Void)?
    var onSelect: ((Int) -> Void)?
    /// 局部放大框选完成回调：参数为归一化矩形（x/y ∈ [0,1]，原点在左下）。
    var onZoomRect: ((CGRect) -> Void)?

    // 更新于 updateNSView：用于把视图坐标换算成绝对道号。
    var firstTrace: Int = 0
    var imageWidth: Int = 0       // 渲染图像的像素宽 == 当前显示的道数
    var totalTraces: Int = 0
    /// 局部放大模式：为 true 时双指点击（右键）拖动框选矩形，而不是左键选道。
    var zoomRectMode = false

    private var pendingScrollX: CGFloat = 0   // 累积横向滚动增量（道号方向）
    private var pendingScrollY: CGFloat = 0   // 累积纵向滚动增量（采样方向）
    private var mouseInside = false
    private var zoomDragStart: NSPoint?
    private var zoomDragCurrent: NSPoint?

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
        // 自然方向：横向滚动 → 道号平移，纵向滚动 → 采样平移；按 1 点 ≈ 1 道/采样累积到整数再动。
        pendingScrollX -= event.scrollingDeltaX
        pendingScrollY -= event.scrollingDeltaY
        let stepX = Int((pendingScrollX / 1.0).rounded(.towardZero))
        if stepX != 0 {
            pendingScrollX -= CGFloat(stepX)
            onScroll?(stepX)
        }
        let stepY = Int((pendingScrollY / 1.0).rounded(.towardZero))
        if stepY != 0 {
            pendingScrollY -= CGFloat(stepY)
            onScrollSamples?(stepY)
        }
    }

    override func magnify(with event: NSEvent) {
        // 每次捏合事件的 magnification 很小，1 + m 作为乘法因子累积到 sampleSpan。
        onMagnify?(1.0 + event.magnification)
    }

    override func mouseDown(with event: NSEvent) {
        // 左键单击：选中光标下的绝对道号（局部放大模式下左键不做框选）。
        if let t = trace(at: convert(event.locationInWindow, from: nil)) {
            onSelect?(t)
        }
    }

    /// 双指点击 = 右键（secondary click）。局部放大模式下用右键拖动框选矩形。
    override func rightMouseDown(with event: NSEvent) {
        guard zoomRectMode else { return }
        let p = convert(event.locationInWindow, from: nil)
        zoomDragStart = p
        zoomDragCurrent = p
        needsDisplay = true
    }

    override func rightMouseDragged(with event: NSEvent) {
        guard zoomDragStart != nil else { return }
        zoomDragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let start = zoomDragStart, let current = zoomDragCurrent else { return }
        zoomDragStart = nil
        zoomDragCurrent = nil
        needsDisplay = true
        onZoomRect?(normalizedRect(from: start, to: current))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let start = zoomDragStart, let current = zoomDragCurrent else { return }
        let r = pixelRect(from: start, to: current)
        NSColor.controlAccentColor.withAlphaComponent(0.2).setFill()
        NSBezierPath(rect: r).fill()
        NSColor.controlAccentColor.setStroke()
        NSBezierPath(rect: r).stroke()
    }

    private func normalizedRect(from a: NSPoint, to b: NSPoint) -> CGRect {
        let w = bounds.width, h = bounds.height
        guard w > 0, h > 0 else { return .zero }
        let x0 = max(0, min(a.x, b.x)), x1 = min(w, max(a.x, b.x))
        let y0 = max(0, min(a.y, b.y)), y1 = min(h, max(a.y, b.y))
        return CGRect(x: x0 / w, y: y0 / h, width: (x1 - x0) / w, height: (y1 - y0) / h)
    }

    private func pixelRect(from a: NSPoint, to b: NSPoint) -> NSRect {
        let x0 = min(a.x, b.x), x1 = max(a.x, b.x)
        let y0 = min(a.y, b.y), y1 = max(a.y, b.y)
        return NSRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
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
