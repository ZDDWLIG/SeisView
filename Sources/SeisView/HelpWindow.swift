import SwiftUI
import Localization

/// 使用说明窗口：左侧章节列表、右侧滚动正文。内容随语言实时切换。
struct HelpView: View {
    @ObservedObject var l10n: L10n
    @State private var selected: Int = 0

    var body: some View {
        let sections = helpSections(l10n.lang)
        HSplitView {
            List(sections, selection: $selected) { s in
                Text(s.title).tag(s.id)
            }
            .frame(minWidth: 160, idealWidth: 190, maxWidth: 260)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let s = sections.first(where: { $0.id == selected }) ?? sections.first {
                        Text(s.title).font(.title2).bold()
                        ForEach(Array(s.blocks.enumerated()), id: \.offset) { _, b in
                            block(b)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 380)
        }
        .frame(minWidth: 620, minHeight: 460)
        .navigationTitle(l10n(.helpWindowTitle))
    }

    @ViewBuilder
    private func block(_ b: HelpBlock) -> some View {
        switch b {
        case .paragraph(let t):
            Text(t).fixedSize(horizontal: false, vertical: true)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                        Text(item).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .keyTable(let rows):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    HStack(alignment: .top, spacing: 12) {
                        Text(r.keys)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 60, alignment: .leading)
                        Text(r.desc).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// 「帮助」菜单里打开使用说明窗口的菜单项。
/// 抽成独立 View 是为了在 body 内读 `@Environment(\.openWindow)`：直接把它塞进
/// `.commands` 闭包，macOS 13 上该环境值在 commands 的构建环境里不可靠（编译能过，
/// 但点菜单 / 按 ⌘? 时可能取不到而崩）。SwiftUI 渲染菜单项时会给这个 View 注入环境，
/// 按钮动作里读 `openWindow` 才稳定。
struct HelpMenuButton: View {
    @Environment(\.openWindow) private var openWindow
    let title: String

    var body: some View {
        Button(title) { openWindow(id: "help") }
            .keyboardShortcut("?", modifiers: .command)
    }
}
