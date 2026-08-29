import SwiftUI
import Localization

/// 目录浏览器侧栏：列出当前目录下的子文件夹与 sgy 文件。
/// 点文件夹进入下一级，点文件打开，顶栏箭头返回上一级。
struct DirectoryBrowser: View {
    @ObservedObject var model: DocumentModel
    @ObservedObject var l10n: L10n

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if model.browserEntries.isEmpty {
                Text(l10n(.dirEmptyHint))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.browserEntries) { entry in
                    Button {
                        model.openBrowserEntry(entry)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: entry.isDirectory ? "folder" : "doc")
                                .foregroundColor(entry.isDirectory ? .secondary : .blue)
                            Text(entry.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.sidebar)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 4) {
            Button {
                model.browserGoUp()
            } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.plain)
            .disabled(model.browserDir == nil)
            .help(l10n(.dirUp))
            Text(model.browserDir?.lastPathComponent ?? "")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(model.browserDir?.path ?? "")
            Spacer()
        }
        .padding(8)
    }
}
