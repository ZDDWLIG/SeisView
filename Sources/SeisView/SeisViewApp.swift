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
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开 SEG-Y…") {
                    let panel = NSOpenPanel()
                    if panel.runModal() == .OK, let url = panel.url { model.open(url) }
                }.keyboardShortcut("o")
                Button("对比…") {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = true
                    if panel.runModal() == .OK, panel.urls.count >= 2 {
                        model.openCompare(panel.urls)
                    }
                }.keyboardShortcut("o", modifiers: [.command, .shift])
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
            if let e = model.errorText {
                Text(e).foregroundColor(.red).padding()
            } else if model.compareMode != .single, model.files.count >= 2 {
                HStack(spacing: 0) {
                    CompareLayout(model: model)
                    Divider()
                    HeaderInspector(model: model)
                        .frame(width: 230)
                }
                StatusBar(model: model, nTraces: model.files[0].geometry.nTraces)
            } else if let f = model.file {
                HStack(spacing: 0) {
                    SectionView(model: model, cursor: model.cursor, image: model.renderedImage,
                                totalTraces: f.geometry.nTraces)
                    Divider()
                    HeaderInspector(model: model)
                        .frame(width: 230)
                }
                StatusBar(model: model, nTraces: f.geometry.nTraces)
            } else {
                Text("⌘O 打开 SEG-Y 文件").foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("增益", selection: Binding(
                    get: { model.viewport.gain },
                    set: { g in
                        var v = model.viewport
                        v.gain = g
                        model.viewport = v
                    }
                )) {
                    Text("百分位").tag(GainMode.percentiles(0.01, 0.99))
                    Text("AGC").tag(GainMode.agc(100))
                    Text("每道").tag(GainMode.perTrace)
                    Text("最大幅值").tag(GainMode.maxAbs)
                }
                .help("增益方式")
                Picker("调色板", selection: Binding(
                    get: { model.viewport.palette },
                    set: { p in
                        var v = model.viewport
                        v.palette = p
                        model.viewport = v
                    }
                )) {
                    Text("灰度").tag(Palette.grayscale)
                    Text("地震").tag(Palette.seismic)
                }
                .help("调色板")
                if model.compareMode != .single {
                    Picker("对比方式", selection: $model.compareMode) {
                        Text("并排").tag(CompareMode.sideBySide)
                        Text("叠加").tag(CompareMode.overlay)
                    }
                    .pickerStyle(.segmented)
                    .help("对比显示方式")
                }
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
        HStack(spacing: 16) {
            Text("道 \(first + 1)–\(last + 1) / \(nTraces)")
            Text("firstTrace \(first)")
            Text("traceSpan \(vp.traceSpan)")
            Text("sampleSpan \(vp.sampleSpan)")
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
