import SwiftUI
import AppKit
import SegyKit

@main
struct SeisViewApp: App {
    @StateObject private var model = DocumentModel()
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 800, minHeight: 600)
                .onOpenURL { url in model.open(url) }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开 SEG-Y…") {
                    let panel = NSOpenPanel()
                    if panel.runModal() == .OK, let url = panel.url { model.open(url) }
                }.keyboardShortcut("o")
                Button("对比…") {
                    let panel = NSOpenPanel()
                    if panel.runModal() == .OK, let url = panel.url {
                        model.addForCompare(url)
                    }
                }.keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandMenu("视图") {
                Button("重置视图") { model.resetView() }
                    .keyboardShortcut("0", modifiers: .command)
                    .disabled(model.file == nil)
                Toggle("显示道头信息", isOn: Binding(
                    get: { model.showHeaderInspector },
                    set: { model.showHeaderInspector = $0 }
                ))
                .keyboardShortcut("h", modifiers: [.command, .shift])
            }
            CommandMenu("导航") {
                Button("上一炮") { model.goToPreviousShot() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("下一炮") { model.goToNextShot() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: DocumentModel
    var body: some View {
        VStack(spacing: 0) {
            if model.file != nil || model.compareMode != .single {
                ZoomBar(model: model)
            }
            if let e = model.errorText {
                Text(e).foregroundColor(.red).padding()
            } else if model.compareMode != .single, model.files.count >= 2 {
                HStack(spacing: 0) {
                    ScrolledSection(model: model,
                                    totalTraces: model.files[0].geometry.nTraces,
                                    totalSamples: model.files[0].geometry.ns) {
                        CompareLayout(model: model)
                    }
                    if model.showHeaderInspector {
                        Divider()
                        HeaderInspector(model: model)
                            .frame(width: 230)
                    }
                }
                StatusBar(model: model, nTraces: model.files[0].geometry.nTraces)
            } else if let f = model.file {
                HStack(spacing: 0) {
                    ScrolledSection(model: model,
                                    totalTraces: f.geometry.nTraces,
                                    totalSamples: f.geometry.ns) {
                        SectionView(model: model, cursor: model.cursor, image: model.render(),
                                    totalTraces: f.geometry.nTraces, zoomRectMode: model.zoomRectMode)
                    }
                    if model.showHeaderInspector {
                        Divider()
                        HeaderInspector(model: model)
                            .frame(width: 230)
                    }
                }
                StatusBar(model: model, nTraces: f.geometry.nTraces)
            } else {
                Text("⌘O 打开 SEG-Y 文件").foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                // 绑 GainKind 而不是 GainMode：百分位载荷随滑块变，若 tag 写死载荷，
                // 一调百分比 selection 就匹配不上任何选项、Picker 会变空白。
                Picker("增益", selection: Binding(
                    get: { model.viewport.gain.kind },
                    set: { model.setGainKind($0) }
                )) {
                    Text("百分位").tag(GainKind.percentiles)
                    Text("AGC").tag(GainKind.agc)
                    Text("每道").tag(GainKind.perTrace)
                    Text("最大幅值").tag(GainKind.maxAbs)
                }
                .help("增益方式")
                if model.viewport.gain.kind == .percentiles {
                    LineSlider(
                        value: Binding(
                            get: { model.viewport.clipPercent },
                            set: { model.setClipPercent($0) }
                        ),
                        range: Viewport.clipPercentRange
                    )
                    .frame(width: 110, height: 20)
                    .help("百分位裁剪：保留中间百分比，越小对比越强")
                    Text(String(format: "%.1f%%", model.viewport.clipPercent))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundColor(.secondary)
                        .frame(width: 44, alignment: .leading)
                }
                Picker("调色板", selection: Binding(
                    get: { model.viewport.palette },
                    set: { p in
                        var v = model.viewport
                        v.palette = p
                        model.viewport = v
                    }
                )) {
                    Text("灰度").tag(Palette.grayscale)
                    Text("红白蓝").tag(Palette.redWhiteBlue)
                    Text("红白黑").tag(Palette.redWhiteBlack)
                    Text("棕白黑").tag(Palette.brownWhiteBlack)
                }
                .help("调色板")
                Toggle(isOn: Binding(
                    get: { model.showHeaderInspector },
                    set: { model.showHeaderInspector = $0 }
                )) {
                    Text("道头信息")
                }
                .help("显示/隐藏右侧道头信息框")
                Toggle(isOn: Binding(
                    get: { model.zoomRectMode },
                    set: { model.zoomRectMode = $0 }
                )) {
                    Label("局部放大", systemImage: "rectangle.dashed")
                }
                .toggleStyle(.button)
                .help("局部放大：双指点击（右键）拖动框选剖面区域，松开放大到该区域")
                .disabled(model.file == nil)
                if model.compareMode != .single {
                    Button { model.resetView() } label: { Label("对齐", systemImage: "align.horizontal.center") }
                        .help("对齐：所有窗口回到相同道号/采样号起点")
                }
                Button { model.resetView() } label: {
                    Label("重置视图", systemImage: "arrow.counterclockwise")
                }
                .help("重置视图（⌘0）：位置与缩放回到初始窗口，保留增益与调色板")
                .disabled(model.file == nil)
                Button { model.goToPreviousShot() } label: {
                    Label("上一炮", systemImage: "chevron.left")
                }
                .help("上一炮")
                .disabled(model.shots.isEmpty)
                Button { model.goToNextShot() } label: {
                    Label("下一炮", systemImage: "chevron.right")
                }
                .help("下一炮")
                .disabled(model.shots.isEmpty)
            }
        }
    }
}

/// 正文顶部居中的缩放控制条：道方向 + 时间方向两个独立槽。
/// 放这里而不是工具栏，避免两个 Slider 被并进同一个工具栏槽。
struct ZoomBar: View {
    @ObservedObject var model: DocumentModel

    var body: some View {
        HStack(spacing: 16) {
            Text("道方向").font(.system(size: 11)).foregroundColor(.secondary)
            ZoomSlider { model.zoomTraces(by: $0) }
                .help("道方向缩放：左拖=放大，右拖=显示更多道，松手回中")
            Divider().frame(height: 20)
            Text("时间方向").font(.system(size: 11)).foregroundColor(.secondary)
            ZoomSlider { model.zoomSamples(by: $0) }
                .help("时间方向缩放：左拖=放大，右拖=显示更多采样，松手回中")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// 相对缩放滑块：把手位置 0.5=中性，**只在松手时**把最终位置换算成缩放因子回调，
/// 随后回中。拖动期间不触发任何重渲染，从根上避免「拖一下就整段重解码卡死主线程」。
struct ZoomSlider: View {
    let onZoom: (Double) -> Void
    @State private var value = 0.5

    private let sensitivity = 4.0

    var body: some View {
        Slider(value: Binding(
            get: { value },
            set: { v in value = v }
        ), in: 0...1, onEditingChanged: { editing in
            if !editing {
                onZoom(pow(2, (value - 0.5) * sensitivity))
                value = 0.5
            }
        })
        .frame(width: 120)
    }
}

/// 单线轨道滑块 cell：只画一条细线作为轨道，去掉原生 NSSlider 凹槽下方那条白色描边。
final class LineSliderCell: NSSliderCell {
    override func drawBar(inside aRect: NSRect, flipped: Bool) {
        let y = aRect.midY
        let path = NSBezierPath()
        path.move(to: NSPoint(x: aRect.minX, y: y))
        path.line(to: NSPoint(x: aRect.maxX, y: y))
        path.lineWidth = 2
        NSColor.tertiaryLabelColor.setStroke()
        path.stroke()
    }
}

/// 连续值滑块（NSViewRepresentable），外观用上面的单线 cell。
struct LineSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider()
        slider.cell = LineSliderCell()
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.doubleValue = value
        slider.sliderType = .linear
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        if slider.doubleValue != value {
            slider.doubleValue = value
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var value: Binding<Double>
        init(value: Binding<Double>) { self.value = value }
        @objc func changed(_ sender: NSSlider) {
            value.wrappedValue = sender.doubleValue
        }
    }
}

/// 底部状态栏：视口位置 / 跨度 / 采样跨度 / 光标道号。
struct StatusBar: View {
    @ObservedObject var model: DocumentModel
    @ObservedObject var cursor: CursorStore
    let nTraces: Int

    init(model: DocumentModel, nTraces: Int) {
        self.model = model
        self.cursor = model.cursor
        self.nTraces = nTraces
    }

    var body: some View {
        let vp = model.viewport
        let first = vp.firstTrace
        let last = min(first + vp.traceSpan, nTraces) - 1
        let ns = model.file?.geometry.ns ?? 0
        let sSpan = vp.sampleSpan > 0 ? min(vp.sampleSpan, ns) : ns
        let sLast = min(vp.firstSample + sSpan, ns)
        HStack(spacing: 16) {
            Text("道 \(first + 1)–\(last + 1) / \(nTraces)")
            Text("采样 \(vp.firstSample + 1)–\(sLast) / \(ns)")
            Text("traceSpan \(vp.traceSpan)")
            Text("光标道 \(cursor.trace.map(String.init) ?? "—")")
            if model.shotsReady {
                Text("炮索引：\(model.shots.count) 炮")
                if !model.shots.isEmpty {
                    Text("炮 \(model.currentShotIndex + 1)/\(model.shots.count)")
                }
            } else {
                Text("炮索引：构建中…")
            }
            Spacer()
        }
        .font(.system(size: 11).monospacedDigit())
        .foregroundColor(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) { Divider() }
    }
}
