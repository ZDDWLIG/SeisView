import Foundation
import CoreGraphics
import SegyKit
import Combine

@MainActor
final class DocumentModel: ObservableObject {
    @Published var file: SegyFile?
    @Published var viewport = Viewport()
    @Published var errorText: String?
    let reader: TraceReader? = nil

    func open(_ url: URL) {
        do {
            let f = try SegyFile.open(url: url)
            file = f
            viewport = Viewport()
            errorText = nil
        } catch { errorText = String(describing: error) }
    }

    func render() -> CGImage? {
        guard let f = file else { return nil }
        let n = f.geometry.nTraces
        let span = viewport.traceSpan > 0 ? viewport.traceSpan : n
        let lo = min(viewport.firstTrace, max(0, n - span))
        let r = TraceReader(file: f, maxThreads: 8)
        let data = r.readDecoded(traceRange: lo..<(lo + span), sampleRange: nil)
        let h = 800
        let b = Decimator.minMax(data, ns: f.geometry.ns, nTraces: span, h: h)
        let g = Gain.apply(b, viewport.gain)
        return Rasterizer.makeImage(g, palette: viewport.palette)
    }
}
