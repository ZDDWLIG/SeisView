import Foundation
import CoreGraphics
import SegyKit
import Combine
import Localization

/// 光标处信息（独立于 DocumentModel 发布，避免鼠标移动触发整段重渲染）。
@MainActor
final class CursorStore: ObservableObject {
    @Published var trace: Int?

    func setTrace(_ t: Int?) { trace = t }
}

/// 显示模式：单文件 / 并排对比。
enum CompareMode: Hashable {
    case single
    case sideBySide
}

/// App 自身产生的、非 SegyKit 的错误。携带 key 与参数，渲染推迟到视图层，
/// 这样切语言时已显示的报错也会跟着变。nested 保存底层错误，渲染时再按当前语言翻译，
/// 避免把 SegyError 的英文描述提前拼进 args。
struct AppError: Error {
    let key: S
    let args: [String]
    var nested: Error? = nil
}

@MainActor
final class DocumentModel: ObservableObject {
    @Published var file: SegyFile?
    /// 对比模式下的全部文件；单文件模式为 [file]。
    @Published var files: [SegyFile] = []
    @Published var compareMode: CompareMode = .single
    @Published var viewport = Viewport()
    /// 存错误值而非成品字符串：文案在视图层按当前语言渲染，切语言时报错也跟着变。
    @Published var error: Error?
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
    /// 是否显示最右侧的道头信息框（可在「视图」菜单里切换）。
    @Published var showHeaderInspector = true
    /// 局部放大模式：为 true 时在剖面上框选矩形、松开后放大到该区域（一次性，放大后自动退出）。
    @Published var zoomRectMode = false
    let reader: TraceReader? = nil
    let cursor = CursorStore()
    /// 图像缓存：按文件分桶，键为完整 viewport（含 gain/palette）。
    /// 分桶是因为对比模式下同一 body 里要渲染 2+ 个文件，单条缓存会被互相顶掉、永远 miss。
    private var imageCache: [URL: (viewport: Viewport, image: CGImage)] = [:]
    /// 解码+分箱缓存：键只含几何（firstTrace/traceSpan/firstSample/sampleSpan），**不含增益**。
    /// 拖百分比滑块时几何没变，靠它跳过 pread + 解码 + 分箱，只重跑增益与栅格化。
    private var binnedCache: [URL: (key: GeomKey, binned: Binned)] = [:]

    /// 决定解码结果的那部分视口状态。增益/调色板不在其中——它们只影响之后的着色。
    private struct GeomKey: Equatable {
        let firstTrace: Int, traceSpan: Int, firstSample: Int, sampleSpan: Int
        init(_ v: Viewport) {
            firstTrace = v.firstTrace; traceSpan = v.traceSpan
            firstSample = v.firstSample; sampleSpan = v.sampleSpan
        }
    }

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
            zoomRectMode = false
            error = nil
            imageCache.removeAll(); binnedCache.removeAll()
            buildShots()
        } catch { self.error = error }
    }

    /// 追加一个文件进对比：已开一个 → 并排；已在对比如继续追加；没开文件 → 直接打开它。
    /// 与当前已开文件重复时忽略（避免跟自身上比）。
    func addForCompare(_ url: URL) {
        do {
            let f = try SegyFile.open(url: url)
            if files.contains(where: { $0.url == url }) {
                error = AppError(key: .errAlreadyComparing, args: [url.lastPathComponent])
                return
            }
            if files.isEmpty {
                open(url)
                return
            }
            files.append(f)
            file = files.first
            compareMode = .sideBySide
            viewport = Viewport()
            cursor.setTrace(nil)
            selectedTrace = 0
            selectedHeader = nil
            shots = []
            shotsReady = false
            currentShotIndex = 0
            zoomRectMode = false
            error = nil
            imageCache.removeAll(); binnedCache.removeAll()
            buildShots()
        } catch let e {
            error = AppError(key: .errOpenFailed, args: [url.lastPathComponent], nested: e)
        }
    }

    /// 沿道号平移视口。整体重新赋值 viewport，保证 @Published 发出 objectWillChange。
    func pan(dTraces: Int) {
        guard let f = file else { return }
        var v = viewport
        v.pan(dTraces: dTraces, total: f.geometry.nTraces)
        viewport = v
    }

    /// 沿采样轴平移视口（垂直滚动条翻页用）。
    func panSamples(dSamples: Int) {
        guard let f = file else { return }
        var v = viewport
        v.panSamples(dSamples: dSamples, ns: f.geometry.ns)
        viewport = v
    }

    /// 采样轴缩放（更新 sampleSpan；zoom 内部会把 firstSample 钳回合法范围）。
    func zoom(timeFactor: Double) {
        guard let f = file else { return }
        var v = viewport
        v.zoom(timeFactor: timeFactor, ns: f.geometry.ns)
        viewport = v
    }

    /// 横向相对缩放（滑块）：factor<1 放大、factor>1 缩小，中心锚。
    func zoomTraces(by factor: Double) {
        guard let f = file else { return }
        var v = viewport
        v.zoomTraces(factor: factor, total: f.geometry.nTraces)
        viewport = v
    }

    /// 纵向相对缩放（滑块）：factor<1 放大、factor>1 缩小，中心锚，全采样↔窗口化平滑过渡。
    func zoomSamples(by factor: Double) {
        guard let f = file else { return }
        var v = viewport
        v.zoomSamples(factor: factor, ns: f.geometry.ns)
        viewport = v
    }

    /// 局部放大：把框选矩形（归一化坐标 x/y ∈ [0,1]，原点在左下）换算成新的视口窗口。
    /// x → 道号范围，y → 采样号范围（y=1 是图像顶部、采样号最小处）。一次性，放大后退出模式。
    func zoomToRect(normalized r: CGRect) {
        guard let f = file, r.width > 0.001, r.height > 0.001 else {
            zoomRectMode = false
            return
        }
        let n = f.geometry.nTraces
        let ns = f.geometry.ns
        var v = viewport

        let shownTraces = min(max(1, v.traceSpan), n)
        let t0 = v.firstTrace + Int(r.minX * CGFloat(shownTraces))
        let t1 = v.firstTrace + Int(r.maxX * CGFloat(shownTraces))

        let shownSamples = v.sampleSpan > 0 ? v.sampleSpan : ns
        let sTop = v.firstSample + Int((1 - r.maxY) * CGFloat(shownSamples))
        let sBottom = v.firstSample + Int((1 - r.minY) * CGFloat(shownSamples))

        v.firstTrace = max(0, min(t0, n - 1))
        v.traceSpan = max(1, min(t1 - t0, Viewport.maxTraceSpan))
        v.firstSample = max(0, min(sTop, ns - 1))
        v.sampleSpan = max(1, min(sBottom - sTop, ns))
        if v.sampleSpan >= ns {
            v.sampleSpan = 0
            v.firstSample = 0
        }
        viewport = v
        zoomRectMode = false
    }

    /// 回到初始显示窗口：位置与缩放归默认，保留增益/百分比/调色板。
    /// firstTrace 归零后画面回到第一炮，currentShotIndex 也要跟上，否则状态栏自相矛盾。
    func resetView() {
        var v = viewport
        v.resetView()
        viewport = v
        currentShotIndex = 0
        zoomRectMode = false
    }

    /// 水平滚动条：直接定位到某道（绝对位置）。
    func scrollToTrace(_ t: Int) {
        guard let f = file else { return }
        let n = f.geometry.nTraces
        var v = viewport
        let span = min(max(1, v.traceSpan), n)
        v.firstTrace = max(0, min(t, max(0, n - span)))
        viewport = v
    }

    /// 垂直滚动条：直接定位到某采样（绝对位置）。
    func scrollToSample(_ s: Int) {
        guard let f = file else { return }
        var v = viewport
        v.firstSample = max(0, min(s, v.maxFirstSample(ns: f.geometry.ns)))
        viewport = v
    }

    /// 百分位裁剪比例（工具栏滑块）。
    func setClipPercent(_ p: Double) {
        var v = viewport
        v.setClipPercent(p)
        viewport = v
    }

    /// 增益方式（工具栏 Picker 绑 GainKind，载荷由 Viewport 用记住的参数重建）。
    func setGainKind(_ k: GainKind) {
        var v = viewport
        v.setGainKind(k)
        viewport = v
    }

    func render() -> CGImage? {
        guard let f = file else { return nil }
        return render(file: f, viewport: viewport)
    }

    /// 渲染单个文件的剖面图，供单文件与多文件并排对比共用。
    /// 所有 pane 共享同一个 viewport，从而保证联动缩放/平移。
    /// 两级缓存：viewport 完全未变 → 直接返回图像；只有增益/调色板变 → 复用分箱结果，跳过 I/O。
    func render(file: SegyFile, viewport: Viewport) -> CGImage? {
        if let hit = imageCache[file.url], hit.viewport == viewport {
            return hit.image
        }
        let b = binned(file: file, viewport: viewport)
        let img = Rasterizer.makeImage(Gain.apply(b, viewport.gain), palette: viewport.palette)
        imageCache[file.url] = (viewport: viewport, image: img)
        return img
    }

    /// 解码 + 分箱（不含增益/栅格化），按几何键缓存。纵向缩放：sampleSpan>0 时只解码该采样窗，
    /// 并按窗高分箱；sampleSpan==0 维持旧行为（全采样、h=800）。
    private func binned(file: SegyFile, viewport: Viewport) -> Binned {
        let key = GeomKey(viewport)
        if let hit = binnedCache[file.url], hit.key == key {
            return hit.binned
        }
        // 越界钳制全在 Viewport.decodePlan 里（纯函数、有测试覆盖）。
        let plan = viewport.decodePlan(nTraces: file.geometry.nTraces, ns: file.geometry.ns)
        let r = TraceReader(file: file, maxThreads: 8)
        let data = r.readDecoded(traceRange: plan.traceRange, sampleRange: plan.sampleRange)
        let b = Decimator.minMax(data, ns: plan.decodedNs,
                                 nTraces: plan.traceRange.count, h: plan.binHeight)
        binnedCache[file.url] = (key: key, binned: b)
        return b
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
        // 大炮（单炮可达 ~21000 道）绝不整炮解码：traceSpan 夹到屏宽上限。
        viewport.traceSpan = min(shot.count, Viewport.maxTraceSpan)
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
