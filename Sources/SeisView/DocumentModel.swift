import Foundation
import CoreGraphics
import SegyKit
import Combine

/// 光标处信息（独立于 DocumentModel 发布，避免鼠标移动触发整段重渲染）。
@MainActor
final class CursorStore: ObservableObject {
    @Published var trace: Int?

    func setTrace(_ t: Int?) { trace = t }
}

@MainActor
final class DocumentModel: ObservableObject {
    @Published var file: SegyFile?
    @Published var viewport = Viewport()
    @Published var errorText: String?
    let reader: TraceReader? = nil
    let cursor = CursorStore()

    func open(_ url: URL) {
        do {
            let f = try SegyFile.open(url: url)
            file = f
            viewport = Viewport()
            cursor.setTrace(nil)
            errorText = nil
        } catch { errorText = String(describing: error) }
    }

    /// 沿道号平移视口。整体重新赋值 viewport，保证 @Published 发出 objectWillChange。
    func pan(dTraces: Int) {
        guard let f = file else { return }
        var v = viewport
        v.pan(dTraces: dTraces, total: f.geometry.nTraces)
        viewport = v
    }

    /// 采样轴缩放（更新 sampleSpan；渲染接线见 Viewport.zoom 注释）。
    func zoom(timeFactor: Double) {
        guard let f = file else { return }
        var v = viewport
        v.zoom(timeFactor: timeFactor, ns: f.geometry.ns)
        viewport = v
    }

    func render() -> CGImage? {
        guard let f = file else { return nil }
        let n = f.geometry.nTraces
        let span = min(max(1, viewport.traceSpan), n)
        let lo = min(max(0, viewport.firstTrace), max(0, n - span))
        let r = TraceReader(file: f, maxThreads: 8)
        let data = r.readDecoded(traceRange: lo..<(lo + span), sampleRange: nil)
        let h = 800
        let b = Decimator.minMax(data, ns: f.geometry.ns, nTraces: span, h: h)
        let g = Gain.apply(b, viewport.gain)
        return Rasterizer.makeImage(g, palette: viewport.palette)
    }
}
