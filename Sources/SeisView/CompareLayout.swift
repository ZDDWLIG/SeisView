import SwiftUI
import SegyKit

/// 多文件对比布局：用 HSplitView 承载每个文件的 pane，分隔条可手动拖动调整各 pane 宽度。
/// 所有 pane 共享同一个 viewport（联动缩放/平移/滚动条同步）。
struct CompareLayout: View {
    @ObservedObject var model: DocumentModel

    var body: some View {
        // 每个 pane 给相同的 idealWidth，首次布局均分；minWidth 保证能拖到很小，
        // maxWidth .infinity 允许拖宽。分隔条由 HSplitView 自带、可拖动。
        HSplitView {
            ForEach(model.files.indices, id: \.self) { i in
                pane(model.files[i])
                    .frame(minWidth: 120, idealWidth: 800, maxWidth: .infinity)
            }
        }
    }

    /// 单文件剖面 pane：顶部文件名小标题 + 剖面。SectionView 填满并裁剪，
    /// 不依赖 NSImageView 的内在尺寸（否则并排会被图像宽度撑成左窄右宽）。
    private func pane(_ f: SegyFile) -> some View {
        VStack(spacing: 0) {
            caption(f.url.lastPathComponent)
            SectionView(model: model, cursor: model.cursor,
                        image: model.render(file: f, viewport: model.viewport),
                        totalTraces: f.geometry.nTraces, totalSamples: f.geometry.ns,
                        zoomRectMode: model.zoomRectMode,
                        velocityMode: model.velocityMode, velocityLine: model.velocityLine)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background(Color(nsColor: .underPageBackgroundColor))
            .overlay(alignment: .bottom) { Divider() }
    }
}
