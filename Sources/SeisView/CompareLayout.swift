import SwiftUI
import SegyKit

/// 多文件对比布局：并排 HStack 或叠加 ZStack。
/// 所有 pane 共享同一个 viewport（联动缩放/平移）；叠加时第一个文件为灰度底图，
/// 第二个文件以 50% 透明度叠在其上。几何不一致时回退到并排并显示警告条。
struct CompareLayout: View {
    @ObservedObject var model: DocumentModel

    var body: some View {
        Group {
            if model.compareMode == .overlay {
                overlayView
            } else {
                sideBySideView
            }
        }
    }

    /// 叠加要求两文件几何一致（ns / nTraces / 采样格式）；否则不叠加。
    private var overlayCompatible: Bool {
        guard model.files.count >= 2 else { return false }
        let a = model.files[0], b = model.files[1]
        return a.geometry.ns == b.geometry.ns
            && a.geometry.nTraces == b.geometry.nTraces
            && a.geometry.format == b.geometry.format
    }

    /// 并排：每个文件一个剖面，宽度均分，顶部标注文件名。
    @ViewBuilder
    private var sideBySideView: some View {
        HStack(spacing: 0) {
            ForEach(model.files.indices, id: \.self) { i in
                if i > 0 { Divider() }
                pane(model.files[i])
            }
        }
    }

    /// 叠加：底图 + 半透明 mask。几何不一致时显示警告条并回退并排。
    @ViewBuilder
    private var overlayView: some View {
        if overlayCompatible, model.files.count >= 2 {
            let base = model.files[0], mask = model.files[1]
            VStack(spacing: 0) {
                caption("底图 \(base.url.lastPathComponent) · 叠加 \(mask.url.lastPathComponent)")
                ZStack {
                    SectionView(model: model, cursor: model.cursor,
                                image: model.render(file: base, viewport: model.viewport),
                                totalTraces: base.geometry.nTraces)
                    SectionView(model: model, cursor: model.cursor,
                                image: model.render(file: mask, viewport: model.viewport),
                                totalTraces: mask.geometry.nTraces)
                        .opacity(0.5)
                }
            }
        } else {
            VStack(spacing: 0) {
                warningBanner
                sideBySideView
            }
        }
    }

    private var warningBanner: some View {
        Text("几何不一致，无法叠加")
            .font(.system(size: 12))
            .foregroundColor(.orange)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color(nsColor: .underPageBackgroundColor))
            .overlay(alignment: .bottom) { Divider() }
    }

    /// 单文件剖面 pane：顶部文件名小标题 + 剖面。
    private func pane(_ f: SegyFile) -> some View {
        VStack(spacing: 0) {
            caption(f.url.lastPathComponent)
            SectionView(model: model, cursor: model.cursor,
                        image: model.render(file: f, viewport: model.viewport),
                        totalTraces: f.geometry.nTraces)
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
