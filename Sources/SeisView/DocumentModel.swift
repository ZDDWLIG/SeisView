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

/// 显示模式：单文件 / 并排对比 / 叠加对比。
enum CompareMode: Hashable {
    case single
    case sideBySide
    case overlay
}

@MainActor
final class DocumentModel: ObservableObject {
    @Published var file: SegyFile?
    /// 对比模式下的全部文件；单文件模式为 [file]。
    @Published var files: [SegyFile] = []
    @Published var compareMode: CompareMode = .single
    @Published var viewport = Viewport()
    @Published var errorText: String?
    /// 炮索引（FFID → 首道 + 道数）。为空表示尚未构建或构建失败。
    @Published var shots: [Shot] = []
    /// 炮索引是否已构建完成（供状态栏显示「构建中… / N 炮」）。
    @Published var shotsReady = false
    /// 当前所在炮在 `shots` 中的下标。
    @Published var currentShotIndex = 0
    /// 点击剖面选中的绝对道号（HeaderInspector 依据它显示道头）。
    @Published var selectedTrace = 0
    /// 选中道的道头（由 selectTrace 读取，避免在视图 body 里做磁盘 IO）。
    @Published var selectedHeader: TraceHeader?
    let reader: TraceReader? = nil
    let cursor = CursorStore()

    /// 屏宽上限：任何情况下 traceSpan 都不超过它，绝不一次解码整炮/整文件。
    static let maxTraceSpan = 1200

    func open(_ url: URL) {
        do {
            let f = try SegyFile.open(url: url)
            file = f
            files = [f]
            compareMode = .single
            viewport = Viewport()
            cursor.setTrace(nil)
            selectedTrace = 0
            selectedHeader = nil
            shots = []
            shotsReady = false
            currentShotIndex = 0
            errorText = nil
            buildShots()
        } catch { errorText = String(describing: error) }
    }

    /// 打开 2+ 个文件进入对比模式：恰好两个默认叠加，更多则并排。
    /// 任一文件打开失败则整体放弃并提示，保持当前状态不变。
    func openCompare(_ urls: [URL]) {
        guard urls.count >= 2 else {
            errorText = "对比至少需要两个文件"
            return
        }
        var opened: [SegyFile] = []
        for url in urls {
            do { opened.append(try SegyFile.open(url: url)) }
            catch {
                errorText = "打开失败 \(url.lastPathComponent)：\(error)"
                return
            }
        }
        file = opened.first
        files = opened
        compareMode = opened.count == 2 ? .overlay : .sideBySide
        viewport = Viewport()
        cursor.setTrace(nil)
        selectedTrace = 0
        selectedHeader = nil
        shots = []
        shotsReady = false
        currentShotIndex = 0
        errorText = nil
        buildShots()
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
        return render(file: f, viewport: viewport)
    }

    /// 渲染单个文件的剖面图，供单文件与多文件对比（并排/叠加）共用。
    /// 所有 pane 共享同一个 viewport，从而保证联动缩放/平移。
    func render(file: SegyFile, viewport: Viewport) -> CGImage? {
        let n = file.geometry.nTraces
        let span = min(max(1, viewport.traceSpan), n)
        let lo = min(max(0, viewport.firstTrace), max(0, n - span))
        let r = TraceReader(file: file, maxThreads: 8)
        let data = r.readDecoded(traceRange: lo..<(lo + span), sampleRange: nil)
        let h = 800
        let b = Decimator.minMax(data, ns: file.geometry.ns, nTraces: span, h: h)
        let g = Gain.apply(b, viewport.gain)
        return Rasterizer.makeImage(g, palette: viewport.palette)
    }

    // MARK: - 炮导航

    /// 构建炮索引：离主线程执行「抽样 + 二分」扫描（真实 589k 道文件约 2300 次道头读取），
    /// 完成后回到主线程发布 `shots`。若期间重开了文件，用 url 比对丢弃过期结果。
    func buildShots() {
        guard let f = file else { return }
        let url = f.url
        let nTraces = f.geometry.nTraces
        shots = []
        shotsReady = false
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = Result {
                // 重新 open 只读 400+240 字节，开销可忽略；换来的是不把非 Sendable 的
                // SegyFile/TraceReader 送进 detached 域，避免 Swift 6 严格并发报错。
                let reopened = try SegyFile.open(url: url)
                let reader = TraceReader(file: reopened)
                return ShotIndex.build(reader: reader, nTraces: nTraces)
            }
            await MainActor.run {
                guard let self, self.file?.url == url else { return }
                self.applyShots(result)
            }
        }
    }

    private func applyShots(_ result: Result<[Shot], Error>) {
        shotsReady = true
        switch result {
        case .success(let built):
            shots = built
            if !built.isEmpty && !built.indices.contains(currentShotIndex) {
                currentShotIndex = 0
            }
        case .failure:
            shots = []
        }
    }

    func goToShot(_ i: Int) {
        guard shots.indices.contains(i) else { return }
        currentShotIndex = i
        let shot = shots[i]
        viewport.firstTrace = shot.firstTrace
        // 大炮（如 big-file 单炮 ~21000 道）绝不整炮解码：traceSpan 夹到屏宽上限。
        viewport.traceSpan = min(shot.count, Self.maxTraceSpan)
        selectTrace(shot.firstTrace)
    }

    func goToPreviousShot() { goToShot(currentShotIndex - 1) }

    func goToNextShot() { goToShot(currentShotIndex + 1) }

    // MARK: - 道头检查

    /// 点击剖面选中某道：更新 selectedTrace 并读取该道道头。
    func selectTrace(_ t: Int) {
        guard let f = file, f.geometry.nTraces > 0 else { return }
        let clamped = max(0, min(t, f.geometry.nTraces - 1))
        selectedTrace = clamped
        selectedHeader = readHeader(forTrace: clamped)
    }

    /// 读取单道道头（240 字节 pread，开销可忽略）。
    func readHeader(forTrace t: Int) -> TraceHeader? {
        guard let f = file, f.geometry.nTraces > 0, (0..<f.geometry.nTraces).contains(t) else { return nil }
        return TraceReader(file: f).readTraceHeaders(range: t..<(t + 1)).first
    }
}
