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
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: DocumentModel
    var body: some View {
        VStack {
            if let e = model.errorText { Text(e).foregroundColor(.red) }
            else if let f = model.file {
                SectionView(image: model.render())
                Text("\(f.geometry.nTraces) 道 × \(f.geometry.ns) 采样")
            } else { Text("⌘O 打开 SEG-Y 文件").foregroundColor(.secondary) }
        }
    }
}
