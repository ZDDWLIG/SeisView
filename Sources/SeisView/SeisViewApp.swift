import SwiftUI
import AppKit
import SegyKit
import Localization

@main
struct SeisViewApp: App {
    @StateObject private var model = DocumentModel()
    @StateObject private var l10n = L10n.shared

    var body: some Scene {
        WindowGroup {
            ContentView(model: model, l10n: l10n)
                .frame(minWidth: 800, minHeight: 600)
                .onOpenURL { url in model.open(url) }
                .onAppear {
                    // 菜单栏此时可能还没构建完，让出一轮再改标题。
                    DispatchQueue.main.async { MainMenuLocalizer.apply(l10n.lang) }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(l10n(.menuFileOpen)) {
                    let panel = NSOpenPanel()
                    if panel.runModal() == .OK, let url = panel.url { model.open(url) }
                }.keyboardShortcut("o")
                Button(l10n(.menuFileCompare)) {
                    let panel = NSOpenPanel()
                    if panel.runModal() == .OK, let url = panel.url {
                        model.addForCompare(url)
                    }
                }.keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandMenu(l10n(.menuView)) {
                Button(l10n(.menuViewReset)) { model.resetView() }
                    .keyboardShortcut("0", modifiers: .command)
                    .disabled(model.file == nil)
                Toggle(l10n(.menuViewHeaderToggle), isOn: Binding(
                    get: { model.showHeaderInspector },
                    set: { model.showHeaderInspector = $0 }
                ))
                .keyboardShortcut("h", modifiers: [.command, .shift])
                Divider()
                // 子菜单固定两项，顺序 [中文, English]——MainMenuLocalizer 依赖这个顺序设勾选态。
                Menu(l10n(.menuViewLanguage)) {
                    Button(l10n(.menuLangChinese)) { l10n.set(.zh) }
                    Button(l10n(.menuLangEnglish)) { l10n.set(.en) }
                }
            }
            CommandMenu(l10n(.menuNav)) {
                Button(l10n(.menuNavPrevShot)) { model.goToPreviousShot() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button(l10n(.menuNavNextShot)) { model.goToNextShot() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                HelpMenuButton(title: l10n(.menuHelpUsage))
            }
        }

        Window(l10n(.helpWindowTitle), id: "help") {
            HelpView(l10n: l10n)
        }
        .defaultSize(width: 760, height: 560)
    }
}

struct ContentView: View {
    @ObservedObject var model: DocumentModel
    @ObservedObject var l10n: L10n

    var body: some View {
        VStack(spacing: 0) {
            if model.file != nil || model.compareMode != .single {
                ZoomBar(model: model, l10n: l10n)
            }
            if let e = model.error {
                // 存的是错误值而非成品字符串，切语言时这里会跟着重算。
                Text(errorMessage(e, l10n)).foregroundColor(.red).padding()
            } else if model.compareMode != .single, model.files.count >= 2 {
                HStack(spacing: 0) {
                    ScrolledSection(model: model,
                                    totalTraces: model.files[0].geometry.nTraces,
                                    totalSamples: model.files[0].geometry.ns) {
                        CompareLayout(model: model)
                    }
                    if model.showHeaderInspector {
                        Divider()
                        HeaderInspector(model: model, l10n: l10n)
                            .frame(width: 230)
                    }
                }
                StatusBar(model: model, l10n: l10n, nTraces: model.files[0].geometry.nTraces)
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
                        HeaderInspector(model: model, l10n: l10n)
                            .frame(width: 230)
                    }
                }
                StatusBar(model: model, l10n: l10n, nTraces: f.geometry.nTraces)
            } else {
                Text(l10n(.emptyOpenHint)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                // 绑 GainKind 而不是 GainMode：百分位载荷随滑块变，若 tag 写死载荷，
                // 一调百分比 selection 就匹配不上任何选项、Picker 会变空白。
                Picker(l10n(.tbGain), selection: Binding(
                    get: { model.viewport.gain.kind },
                    set: { model.setGainKind($0) }
                )) {
                    Text(l10n(.gainPercentiles)).tag(GainKind.percentiles)
                    Text(l10n(.gainAGC)).tag(GainKind.agc)
                    Text(l10n(.gainPerTrace)).tag(GainKind.perTrace)
                    Text(l10n(.gainMaxAbs)).tag(GainKind.maxAbs)
                }
                .help(l10n(.tbGainHelp))
                if model.viewport.gain.kind == .percentiles {
                    LineSlider(
                        value: Binding(
                            get: { model.viewport.clipPercent },
                            set: { model.setClipPercent($0) }
                        ),
                        range: Viewport.clipPercentRange
                    )
                    .frame(width: 110, height: 20)
                    .help(l10n(.tbClipHelp))
                    Text(String(format: "%.1f%%", model.viewport.clipPercent))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundColor(.secondary)
                        .frame(width: 44, alignment: .leading)
                }
                Picker(l10n(.tbPalette), selection: Binding(
                    get: { model.viewport.palette },
                    set: { p in
                        var v = model.viewport
                        v.palette = p
                        model.viewport = v
                    }
                )) {
                    Text(l10n(.paletteGray)).tag(Palette.grayscale)
                    Text(l10n(.paletteRedWhiteBlue)).tag(Palette.redWhiteBlue)
                    Text(l10n(.paletteRedWhiteBlack)).tag(Palette.redWhiteBlack)
                    Text(l10n(.paletteBrownWhiteBlack)).tag(Palette.brownWhiteBlack)
                }
                .help(l10n(.tbPalette))
                Picker(l10n(.tbOrder), selection: Binding(
                    get: { model.viewport.traceOrder },
                    set: { model.setTraceOrder($0) }
                )) {
                    Text(l10n(.orderByTrace)).tag(TraceOrder.byTrace)
                    Text(l10n(.orderByOffset)).tag(TraceOrder.byOffset)
                    Text(l10n(.orderByOffsetAbs)).tag(TraceOrder.byOffsetAbs)
                }
                .help(l10n(.tbOrder))
                .disabled(model.file == nil || !model.offsetIndexReady || model.compareMode != .single)
                Toggle(isOn: Binding(
                    get: { model.showHeaderInspector },
                    set: { model.showHeaderInspector = $0 }
                )) {
                    Text(l10n(.tbHeaderToggle))
                }
                .help(l10n(.tbHeaderToggleHelp))
                Toggle(isOn: Binding(
                    get: { model.zoomRectMode },
                    set: { model.zoomRectMode = $0 }
                )) {
                    Label(l10n(.tbZoomRect), systemImage: "rectangle.dashed")
                }
                .toggleStyle(.button)
                .help(l10n(.tbZoomRectHelp))
                .disabled(model.file == nil)
                if model.compareMode != .single {
                    Button { model.resetView() } label: {
                        Label(l10n(.tbAlign), systemImage: "align.horizontal.center")
                    }
                    .help(l10n(.tbAlignHelp))
                }
                Button { model.resetView() } label: {
                    Label(l10n(.tbReset), systemImage: "arrow.counterclockwise")
                }
                .help(l10n(.tbResetHelp))
                .disabled(model.file == nil)
                Button { model.goToPreviousShot() } label: {
                    Label(l10n(.tbPrevShot), systemImage: "chevron.left")
                }
                .help(l10n(.tbPrevShotHelp))
                .disabled(model.shots.isEmpty)
                Button { model.goToNextShot() } label: {
                    Label(l10n(.tbNextShot), systemImage: "chevron.right")
                }
                .help(l10n(.tbNextShotHelp))
                .disabled(model.shots.isEmpty)
            }
        }
    }
}

/// 正文顶部居中的缩放控制条：道方向 + 时间方向两个独立槽。
/// 放这里而不是工具栏，避免两个 Slider 被并进同一个工具栏槽。
struct ZoomBar: View {
    @ObservedObject var model: DocumentModel
    @ObservedObject var l10n: L10n

    var body: some View {
        HStack(spacing: 16) {
            Text(l10n(.zoomTraceAxis)).font(.system(size: 11)).foregroundColor(.secondary)
            ZoomSlider { model.zoomTraces(by: $0) }
                .help(l10n(.zoomTraceAxisHelp))
            Divider().frame(height: 20)
            Text(l10n(.zoomTimeAxis)).font(.system(size: 11)).foregroundColor(.secondary)
            ZoomSlider { model.zoomSamples(by: $0) }
                .help(l10n(.zoomTimeAxisHelp))
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
    @ObservedObject var l10n: L10n
    @ObservedObject var cursor: CursorStore
    let nTraces: Int

    init(model: DocumentModel, l10n: L10n, nTraces: Int) {
        self.model = model
        self.l10n = l10n
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
            if model.viewport.traceOrder != .byTrace {
                Text(l10n.f(.statusPositions, ["\(first + 1)", "\(last + 1)", "\(nTraces)"]))
            } else {
                Text(l10n.f(.statusTraces, ["\(first + 1)", "\(last + 1)", "\(nTraces)"]))
            }
            Text(l10n.f(.statusSamples, ["\(vp.firstSample + 1)", "\(sLast)", "\(ns)"]))
            Text(l10n.f(.statusTraceSpan, ["\(vp.traceSpan)"]))
            Text(l10n.f(.statusCursor, [cursor.trace.map(String.init) ?? l10n(.statusCursorNone)]))
            if model.shotsReady {
                Text(l10n.f(.statusShotCount, ["\(model.shots.count)"]))
                if !model.shots.isEmpty {
                    Text(l10n.f(.statusShotCurrent, ["\(model.currentShotIndex + 1)", "\(model.shots.count)"]))
                }
            } else {
                Text(l10n(.statusShotBuilding))
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
