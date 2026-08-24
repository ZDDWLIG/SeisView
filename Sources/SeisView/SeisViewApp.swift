import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
                    panel.allowedContentTypes = [UTType(filenameExtension: "sgy")!,
                                                 UTType(filenameExtension: "segy")!]
                    if panel.runModal() == .OK, let url = panel.url { model.open(url) }
                }.keyboardShortcut("o")
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
            } else if let f = model.file {
                HStack(spacing: 0) {
                    SectionView(model: model, cursor: model.cursor, image: model.render())
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
