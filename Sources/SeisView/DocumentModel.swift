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
    /// 按偏移距排列用的全文件置换（nil = 未建好）。
    @Published var offsetIndex: OffsetIndex?
    @Published var offsetIndexReady = false
    /// 点击剖面选中的绝对道号（HeaderInspector 依据它显示道头）。
    @Published var selectedTrace = 0
    /// 选中道的道头（由 selectTrace 读取，避免在视图 body 里做磁盘 IO）。
    @Published var selectedHeader: TraceHeader?
    /// 是否显示最右侧的道头信息框（可在「视图」菜单里切换）。
    @Published var showHeaderInspector = true
    /// 局部放大模式：为 true 时在剖面上框选矩形、松开后放大到该区域（一次性，放大后自动退出）。
    @Published var zoomRectMode = false
    /// 视速度测算模式 + 锚点 + 已测量的线。
    @Published var velocityMode = false
    @Published var velocityAnchor: VelocityAnchor?
    @Published var velocityLine: VelocityLine?
    /// 单道波形弹窗的数据（非 nil 时弹出 sheet）。
    @Published var singleTrace: SingleTraceData?
    /// 振幅谱弹窗的数据（非 nil 时弹出 sheet）。
    @Published var spectrumResult: SpectrumResult?
    /// 频谱局部框选模式：为 true 时在剖面上框选矩形、松开后计算该区域频谱（一次性，完成后自动退出）。
    @Published var spectrumLocalMode = false
    let reader: TraceReader? = nil
    let cursor = CursorStore()
    /// 图像缓存：按文件分桶，键为完整 viewport（含 gain/palette）。
    /// 分桶是因为对比模式下同一 body 里要渲染 2+ 个文件，单条缓存会被互相顶掉、永远 miss。
    private var imageCache: [URL: (viewport: Viewport, image: CGImage)] = [:]
    /// 解码+分箱缓存：键只含几何（firstTrace/traceSpan/firstSample/sampleSpan），**不含增益**。
    /// 拖百分比滑块时几何没变，靠它跳过 pread + 解码 + 分箱，只重跑增益与栅格化。
    private var binnedCache: [URL: (key: GeomKey, binned: Binned)] = [:]

    /// 决定解码结果的那部分视口状态。增益/调色板不在其中——它们只影响之后的着色。
    /// traceOrder 必须纳入：不同排列产生不同几何，漏掉会复用旧排列的分箱结果 → 图像错乱。
    private struct GeomKey: Equatable {
        let firstTrace: Int, traceSpan: Int, firstSample: Int, sampleSpan: Int
        let traceOrder: TraceOrder
        init(_ v: Viewport) {
            firstTrace = v.firstTrace; traceSpan = v.traceSpan
            firstSample = v.firstSample; sampleSpan = v.sampleSpan
            traceOrder = v.traceOrder
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
            velocityMode = false
            velocityAnchor = nil
            velocityLine = nil
            singleTrace = nil
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
            velocityMode = false
            velocityAnchor = nil
            velocityLine = nil
            singleTrace = nil
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
    /// 排序模式（byOffset）下，这里换算的是「位置」区间，渲染时再映射回真实道号。
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
        velocityMode = false
        velocityAnchor = nil
        velocityLine = nil
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
        if viewport.palette == .wiggle {
            guard let img = renderWiggle(file: file, viewport: viewport) else { return nil }
            imageCache[file.url] = (viewport: viewport, image: img)
            return img
        }
        let b = binned(file: file, viewport: viewport)
        let img = Rasterizer.makeImage(Gain.apply(b, viewport.gain), palette: viewport.palette)
        imageCache[file.url] = (viewport: viewport, image: img)
        return img
    }

    /// wiggle 渲染：跳过 min/max 分箱，直接拿解码样本画波形变面积。
    /// 宽 = 道数（traceRange.count），高 = decodePlan.binHeight（全采样 800 / 窗口化 = sampleSpan）。
    private func renderWiggle(file: SegyFile, viewport: Viewport) -> CGImage? {
        let plan = viewport.decodePlan(nTraces: file.geometry.nTraces, ns: file.geometry.ns)
        let r = TraceReader(file: file, maxThreads: 8)
        let data: [Float]
        if viewport.traceOrder != .byTrace, let idx = offsetIndex {
            let indices = OffsetIndexLookup.traces(idx, positions: plan.traceRange, order: viewport.traceOrder)
            data = r.readDecoded(traceIndices: indices, sampleRange: plan.sampleRange)
        } else {
            data = r.readDecoded(traceRange: plan.traceRange, sampleRange: plan.sampleRange)
        }
        return WiggleRenderer.makeImage(data, ns: plan.decodedNs, nTraces: plan.traceRange.count,
                                        width: plan.traceRange.count, height: plan.binHeight)
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
        let data: [Float]
        if viewport.traceOrder != .byTrace, let idx = offsetIndex {
            let positions = plan.traceRange
            let indices = OffsetIndexLookup.traces(idx, positions: positions, order: viewport.traceOrder)
            data = r.readDecoded(traceIndices: indices, sampleRange: plan.sampleRange)
        } else {
            data = r.readDecoded(traceRange: plan.traceRange, sampleRange: plan.sampleRange)
        }
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
            buildOffsetIndex()
        case .failure:
            shots = []
            offsetIndex = nil
            offsetIndexReady = false   // 建不出炮索引，offset 索引也无法建；选项保持禁用
        }
    }

    /// 构建 offset 索引：后台读所有道头、炮内 offset 排序。仿 buildShots，url 比对丢过期结果。
    func buildOffsetIndex() {
        guard let f = file else { return }
        let url = f.url
        let builtShots = shots
        offsetIndex = nil
        offsetIndexReady = false
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = Result {
                let reopened = try SegyFile.open(url: url)
                let reader = TraceReader(file: reopened)
                return OffsetIndexBuilder.build(shots: builtShots, source: reader)
            }
            await MainActor.run {
                guard let self, self.file?.url == url else { return }
                self.offsetIndex = (try? result.get())
                self.offsetIndexReady = true
            }
        }
    }

    // MARK: - 振幅谱

    /// 局部频谱：由框选矩形换算道区间 × 采样区间后后台计算。
    func spectrumFromRect(normalized r: CGRect) {
        guard let f = file, r.width > 0.001, r.height > 0.001 else {
            spectrumLocalMode = false
            return
        }
        let n = f.geometry.nTraces, ns = f.geometry.ns
        let v = viewport
        let shownTraces = min(max(1, v.traceSpan), n)
        let t0 = v.firstTrace + Int(r.minX * CGFloat(shownTraces))
        let t1 = v.firstTrace + Int(r.maxX * CGFloat(shownTraces))
        let shownSamples = v.sampleSpan > 0 ? v.sampleSpan : ns
        let sTop = v.firstSample + Int((1 - r.maxY) * CGFloat(shownSamples))
        let sBottom = v.firstSample + Int((1 - r.minY) * CGFloat(shownSamples))
        let traceRange = max(0, min(t0, n - 1))..<max(1, min(t1, n))
        let sampleRange = max(0, min(sTop, ns - 1))..<max(1, min(sBottom, ns))
        spectrumLocalMode = false
        computeSpectrum(traceRange: traceRange, sampleRange: sampleRange, title: l10nTitle(.spectrumLocal))
    }

    /// 全局频谱：整个文件均匀抽道。
    func computeGlobalSpectrum() {
        guard let f = file else { return }
        computeSpectrum(traceRange: 0..<f.geometry.nTraces, sampleRange: nil, title: l10nTitle(.spectrumGlobal))
    }

    /// 取当前语言下某 key 的文案（频谱 title 需要在后台结果里携带，用当前语言快照）。
    private func l10nTitle(_ key: S) -> String {
        string(key, L10n.shared.lang)
    }

    /// 后台：抽 ≤400 道 → 读样 → 平均 → FFT → 发布结果。仿 buildShots 的 reopen + url 比对。
    private func computeSpectrum(traceRange: Range<Int>, sampleRange: Range<Int>?, title: String) {
        guard let f = file else { return }
        let url = f.url
        let ns = sampleRange.map { $0.count } ?? f.geometry.ns
        let dt = f.geometry.dtMicros
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = Result<Spectrum, Error> {
                let reopened = try SegyFile.open(url: url)
                let reader = TraceReader(file: reopened)
                let indices = SpectrumBuilder.sampledIndices(range: traceRange, maxTraces: 400)
                let data = reader.readDecoded(traceIndices: indices, sampleRange: sampleRange)
                let stacked = SpectrumBuilder.stack(data, nTraces: indices.count, ns: ns)
                return FFT.amplitudeSpectrum(stacked, dtMicros: dt)
            }
            await MainActor.run {
                guard let self, self.file?.url == url else { return }
                self.spectrumResult = (try? result.get()).map {
                    SpectrumResult(spectrum: $0, title: title, ns: ns, dtMicros: dt)
                }
            }
        }
    }

    /// 切换排列方式。整体重赋值 viewport（铁律）、清两级缓存、firstTrace 归零。
    /// 显示参数（增益/调色板/百分比）保留。对齐 resetView：currentShotIndex 与光标归零，
    /// 否则状态栏还显示旧炮而画面已回到第一炮/位置 0，自相矛盾。
    func setTraceOrder(_ o: TraceOrder) {
        guard let f = file else { return }
        var v = viewport
        v.traceOrder = o
        viewport = v
        imageCache.removeAll(); binnedCache.removeAll()
        var v2 = viewport
        v2.firstTrace = 0
        viewport = v2
        currentShotIndex = 0
        cursor.setTrace(nil)
        _ = f  // 保持与其它 setter 形态一致；无额外逻辑
    }

    func goToShot(_ i: Int) {
        guard shots.indices.contains(i) else { return }
        currentShotIndex = i
        let shot = shots[i]
        if viewport.traceOrder != .byTrace, let idx = offsetIndex,
           let r = OffsetIndexLookup.positionRange(idx, shotIndex: i) {
            viewport.firstTrace = r.lowerBound
            viewport.traceSpan = min(r.count, Viewport.maxTraceSpan)
            let real = OffsetIndexLookup.traceAt(idx, position: r.lowerBound, order: viewport.traceOrder) ?? 0
            selectTrace(real)
        } else {
            viewport.firstTrace = shot.firstTrace
            // 大炮（单炮可达 ~21000 道）绝不整炮解码：traceSpan 夹到屏宽上限。
            viewport.traceSpan = min(shot.count, Viewport.maxTraceSpan)
            selectTrace(shot.firstTrace)
        }
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

    /// 读取选中道的全部采样，弹出单道波形。
    func showSingleTrace() {
        guard let f = file, f.geometry.nTraces > 0 else { return }
        let t = max(0, min(selectedTrace, f.geometry.nTraces - 1))
        let samples = TraceReader(file: f, maxThreads: 1)
            .readDecoded(traceRange: t..<(t + 1), sampleRange: nil)
        var ffid: Int? = nil
        if shots.indices.contains(currentShotIndex) {
            let s = shots[currentShotIndex]
            if t >= s.firstTrace && t < s.firstTrace + s.count { ffid = s.ffid }
        }
        singleTrace = SingleTraceData(trace: t, ffid: ffid, samples: samples, dtMicros: f.geometry.dtMicros)
    }

    /// 视速度模式下的一次剖面点击：第一次设锚点，第二次连成线并计算速度。
    /// position/sample 由 SectionNSView 上报（position 经 traceResolver 解析前）。
    func velocityClick(position: Int, sample: Int) {
        guard let f = file else { return }
        let n = f.geometry.nTraces
        let clamped = max(0, min(position, n - 1))
        let real = realTrace(forPosition: clamped)
        let off = readHeader(forTrace: real)?.offset ?? 0
        if let anchor = velocityAnchor {
            if let mps = Velocity.apparentVelocity(offsetA: anchor.offset, offsetB: off,
                                                   sampleA: anchor.sample, sampleB: sample,
                                                   dtMicros: f.geometry.dtMicros) {
                velocityLine = VelocityLine(start: VelocityPoint(position: anchor.position, sample: anchor.sample),
                                            end: VelocityPoint(position: clamped, sample: sample),
                                            mps: mps)
            } else {
                velocityLine = nil
            }
            velocityAnchor = nil
        } else {
            velocityAnchor = VelocityAnchor(position: clamped, sample: sample, offset: off)
            velocityLine = nil
        }
    }

    /// 把剖面位置解析成真实道号（byOffset/byOffsetAbs 经 offsetIndex 反查）。
    private func realTrace(forPosition p: Int) -> Int {
        if viewport.traceOrder != .byTrace, let idx = offsetIndex {
            return OffsetIndexLookup.traceAt(idx, position: p, order: viewport.traceOrder) ?? p
        }
        return p
    }

    /// 退出视速度模式并清除已画的线。
    func toggleVelocityMode() {
        velocityMode.toggle()
        velocityAnchor = nil
        velocityLine = nil
    }

    /// 读取单道道头（240 字节 pread，开销可忽略）。
    func readHeader(forTrace t: Int) -> TraceHeader? {
        guard let f = file, f.geometry.nTraces > 0, (0..<f.geometry.nTraces).contains(t) else { return nil }
        return TraceReader(file: f).readTraceHeaders(range: t..<(t + 1)).first
    }
}
