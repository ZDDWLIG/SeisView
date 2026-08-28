import SwiftUI
import AppKit
import SegyKit

/// 包裹自绘 NSImageView 的 SwiftUI 桥：把滚轮/捏合/光标事件转发到 DocumentModel。
struct SectionView: NSViewRepresentable {
    let model: DocumentModel
    let cursor: CursorStore
    let image: CGImage?
    /// 该 pane 对应文件的总道数（光标坐标换算用）。对比模式下各 pane 可不同。
    let totalTraces: Int
    /// 该 pane 对应文件的总采样数（velocity y 坐标换算用）。
    let totalSamples: Int
    /// 局部放大模式。作为值参数传入（而非读 model），保证 SwiftUI 检测到变化并触发 updateNSView。
    let zoomRectMode: Bool
    /// 频谱局部框选模式。作为值参数传入（而非读 model），保证 SwiftUI 检测到变化并触发 updateNSView。
    let spectrumLocalMode: Bool
    /// 视速度测算模式。作为值参数传入（而非读 model），保证 SwiftUI 检测到变化并触发 updateNSView。
    let velocityMode: Bool
    /// 已完成的视速度线（蓝线绘制用）。
    let velocityLine: VelocityLine?
    /// 视速度锚点（第一次点击后显示一个点）。
    let velocityAnchor: VelocityAnchor?

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
        v.onSpectrumRect = { [weak model] r in
            MainActor.assumeIsolated { model?.spectrumFromRect(normalized: r) }
        }
        v.onVelocityClick = { [weak model] pos, sample in
            MainActor.assumeIsolated { model?.velocityClick(position: pos, sample: sample) }
        }
        return v
    }

    func updateNSView(_ v: SectionNSView, context: Context) {
        v.image = image.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        v.imageScaling = .scaleAxesIndependently
        v.firstTrace = model.viewport.firstTrace
        v.imageWidth = min(model.viewport.traceSpan, totalTraces)
        v.totalTraces = totalTraces
        v.zoomRectMode = zoomRectMode
        v.spectrumLocalMode = spectrumLocalMode
        v.velocityMode = velocityMode
        v.velocityLine = velocityLine
        v.velocityAnchor = velocityAnchor
        v.firstSample = model.viewport.firstSample
        v.sampleSpan = model.viewport.sampleSpan
        v.imageHeight = image?.height ?? 0
        v.totalSamples = totalSamples
        v.traceResolver = { [weak model] pos in
            // 事件回调（AppKit）不被视为 @MainActor，读 DocumentModel 状态需显式放回主 actor。
            MainActor.assumeIsolated {
                guard let model else { return pos }
                if model.viewport.traceOrder != .byTrace, let idx = model.offsetIndex {
                    return OffsetIndexLookup.traceAt(idx, position: pos, order: model.viewport.traceOrder) ?? pos
                }
                return pos
            }
        }
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
    /// 频谱局部框选完成回调：参数为归一化矩形（x/y ∈ [0,1]，原点在左下）。
    var onSpectrumRect: ((CGRect) -> Void)?

    // 更新于 updateNSView：用于把视图坐标换算成绝对道号。
    var firstTrace: Int = 0
    var imageWidth: Int = 0       // 渲染图像的像素宽 == 当前显示的道数
    var totalTraces: Int = 0
    /// 局部放大模式：为 true 时双指点击（右键）拖动框选矩形，而不是左键选道。
    var zoomRectMode = false
    /// 频谱局部框选模式：为 true 时右键拖动框选矩形，松手后计算该区域频谱。
    var spectrumLocalMode = false
    /// 视速度测算点击回调：参数为（剖面位置，采样号）。
    var onVelocityClick: ((Int, Int) -> Void)?
    /// 视速度测算模式：为 true 时左键两次分别设锚点/连线，不再选道。
    var velocityMode = false
    /// 已完成的视速度线（蓝线绘制用）。
    var velocityLine: VelocityLine?
    /// 视速度锚点（第一次点击后显示一个点）。
    var velocityAnchor: VelocityAnchor?
    var firstSample = 0
    var sampleSpan = 0
    var imageHeight = 0
    var totalSamples = 0
    /// 排序模式下把「位置」反查成真实道号（nil = 道号模式）。
    var traceResolver: ((Int) -> Int)?

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
        if velocityMode {
            let p = convert(event.locationInWindow, from: nil)
            guard let t = trace(at: p), let s = sample(at: p) else { return }
            onVelocityClick?(t, s)
            return
        }
        if let t = trace(at: convert(event.locationInWindow, from: nil)) {
            onSelect?(resolvedTrace(t))
        }
    }

    /// 双指点击 = 右键（secondary click）。局部放大 / 频谱局部模式下用右键拖动框选矩形。
    override func rightMouseDown(with event: NSEvent) {
        guard zoomRectMode || spectrumLocalMode else { return }
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
        let rect = normalizedRect(from: start, to: current)
        if zoomRectMode { onZoomRect?(rect) }
        else if spectrumLocalMode { onSpectrumRect?(rect) }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let start = zoomDragStart, let current = zoomDragCurrent {
            let r = pixelRect(from: start, to: current)
            NSColor.controlAccentColor.withAlphaComponent(0.2).setFill()
            NSBezierPath(rect: r).fill()
            NSColor.controlAccentColor.setStroke()
            NSBezierPath(rect: r).stroke()
        }
        if let a = velocityAnchor {
            drawDot(at: NSPoint(x: x(for: a.position), y: y(for: a.sample)))
        }
        if let line = velocityLine {
            drawVelocityLine(line)
        }
    }

    private static let velocityGreen = NSColor(calibratedRed: 0.0, green: 0.9, blue: 0.1, alpha: 1.0)

    private func drawVelocityLine(_ line: VelocityLine) {
        let p0 = NSPoint(x: x(for: line.start.position), y: y(for: line.start.sample))
        let p1 = NSPoint(x: x(for: line.end.position), y: y(for: line.end.sample))
        // 连线（加粗）
        let path = NSBezierPath()
        path.move(to: p0); path.line(to: p1)
        path.lineWidth = 3
        Self.velocityGreen.setStroke()
        path.stroke()
        // 两端各一个点
        drawDot(at: p0)
        drawDot(at: p1)
        // 速度标签：沿线的朝上法向偏移，避开线本身，居中且更大字体
        let label = String(format: "v=%.0f m/s", line.mps) as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: Self.velocityGreen,
            .font: NSFont.boldSystemFont(ofSize: 18)
        ]
        let mid = NSPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
        let dx = p1.x - p0.x, dy = p1.y - p0.y
        let len = max(hypot(dx, dy), 0.001)
        var nx = -dy / len, ny = dx / len
        if ny < 0 { nx = -nx; ny = -ny }   // 取朝上的法向分量
        let offset: CGFloat = 30
        let c = NSPoint(x: mid.x + nx * offset, y: mid.y + ny * offset)
        let sz = label.size(withAttributes: attrs)
        label.draw(at: NSPoint(x: c.x - sz.width / 2, y: c.y - sz.height / 2), withAttributes: attrs)
    }

    private func drawDot(at p: NSPoint) {
        let r: CGFloat = 4
        let rect = NSRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        Self.velocityGreen.setFill()
        NSBezierPath(ovalIn: rect).fill()
    }

    private func x(for position: Int) -> CGFloat {
        guard bounds.width > 0, imageWidth > 0 else { return 0 }
        let frac = CGFloat(position - firstTrace) / CGFloat(imageWidth)
        return bounds.width * frac
    }

    private func y(for sample: Int) -> CGFloat {
        guard bounds.height > 0 else { return 0 }
        let shown = sampleSpan > 0 ? sampleSpan : max(totalSamples, 1)
        let frac = CGFloat(sample - firstSample) / CGFloat(shown)
        return bounds.height * (1 - frac)
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
        onCursor?(trace(at: convert(windowPoint, from: nil)).map(resolvedTrace))
    }

    /// 视图坐标 → 绝对道号（夹到 [0, totalTraces-1]）；视图/图像宽度非法时返回 nil。
    private func trace(at pt: NSPoint) -> Int? {
        guard bounds.width > 0, imageWidth > 0 else { return nil }
        let frac = max(0, min(1, pt.x / bounds.width))
        let raw = firstTrace + Int(frac * CGFloat(imageWidth))
        return min(max(0, raw), max(0, totalTraces - 1))
    }

    /// 视图坐标 → 采样号（采样 0 在顶部；夹到 [0, totalSamples-1]）；视图/图像高度非法时返回 nil。
    private func sample(at pt: NSPoint) -> Int? {
        guard bounds.height > 0, imageHeight > 0, totalSamples > 0 else { return nil }
        let shown = sampleSpan > 0 ? sampleSpan : totalSamples
        let frac = max(0, min(1, 1 - pt.y / bounds.height))   // 顶部 y 大 → 采样号小
        let raw = firstSample + Int(frac * CGFloat(shown))
        return min(max(0, raw), max(0, totalSamples - 1))
    }

    /// 把「位置」解析为上报用的真实道号：byOffset 模式下经 traceResolver 反查，否则原样。
    private func resolvedTrace(_ position: Int) -> Int {
        traceResolver?(position) ?? position
    }
}
