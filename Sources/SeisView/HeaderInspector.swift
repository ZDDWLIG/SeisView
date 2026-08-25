import SwiftUI
import SegyKit
import Localization

/// 道头检查器：显示当前选中道的 SEG-Y 道头字段（字段名 / 字节位置 / 值）。
/// 点击剖面（SectionNSView.mouseDown）→ DocumentModel.selectTrace 更新
/// selectedTrace / selectedHeader，本面板据此展示。
struct HeaderInspector: View {
    @ObservedObject var model: DocumentModel
    @ObservedObject var l10n: L10n

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n(.hdrTitle))
                .font(.headline)
            if let h = model.selectedHeader {
                Text(l10n.f(.hdrTraceLabel, ["\(model.selectedTrace + 1)", shotSuffix]))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Divider()
                rows(h)
            } else {
                Text(l10n(.hdrEmptyHint))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    /// 若选中道落在当前炮内，附上「 · FFID n」；否则不显示。
    private var shotSuffix: String {
        guard model.shots.indices.contains(model.currentShotIndex) else { return "" }
        let s = model.shots[model.currentShotIndex]
        guard model.selectedTrace >= s.firstTrace,
              model.selectedTrace < s.firstTrace + s.count else { return "" }
        return " · FFID \(s.ffid)"
    }

    @ViewBuilder
    private func rows(_ h: TraceHeader) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HeaderRow(name: l10n(.hdrTraceSeq), bytes: "1–4", value: "\(h.traceSeq)")
            HeaderRow(name: l10n(.hdrFFID), bytes: "9–12", value: "\(h.ffid)")
            HeaderRow(name: l10n(.hdrCDP), bytes: "21–24", value: "\(h.cdp)")
            HeaderRow(name: l10n(.hdrOffset), bytes: "37–40", value: "\(h.offset)")
            HeaderRow(name: l10n(.hdrNs), bytes: "115–116", value: "\(h.ns)")
            HeaderRow(name: l10n(.hdrDt), bytes: "117–118", value: "\(h.dtMicros)")
        }
    }
}

private struct HeaderRow: View {
    let name: String
    let bytes: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(name).frame(width: 76, alignment: .leading)
            Text(bytes).font(.system(size: 10)).foregroundColor(.secondary)
            Spacer(minLength: 8)
            Text(value).monospacedDigit()
        }
        .font(.system(size: 11))
    }
}
