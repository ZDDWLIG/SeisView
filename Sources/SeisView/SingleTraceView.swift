import SwiftUI
import SegyKit
import Localization

/// 单道波形弹窗：横轴时间(s)、纵轴振幅，带坐标刻度与时间范围选择。
struct SingleTraceView: View {
    let data: SingleTraceData
    @ObservedObject var l10n: L10n
    @Environment(\.dismiss) private var dismiss

    @State private var tMin = 0.0
    @State private var tMax = 0.0
    @State private var didInit = false

    /// 整道时长（秒）。
    private var fullSec: Double {
        Double(max(0, data.samples.count - 1)) * Double(data.dtMicros) / 1e6
    }

    /// 振幅范围（整道 maxAbs，缩放时间不改变纵向尺度）。
    private var ampMax: Float {
        max(data.samples.map { abs($0) }.max() ?? 1, 1)
    }

    /// 波形折线点（数据坐标：x=秒，y=振幅），裁到 [tMin, tMax]。
    private var points: [CGPoint] {
        guard data.samples.count > 1 else { return [] }
        let total = Double(data.samples.count - 1) * Double(data.dtMicros) / 1e6
        var out: [CGPoint] = []
        for i in 0..<data.samples.count {
            let t = Double(i) / Double(data.samples.count - 1) * total
            guard t >= tMin && t <= tMax else { continue }
            out.append(CGPoint(x: t, y: Double(data.samples[i])))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l10n(.singleTraceTitle)).font(.headline)
                if let ffid = data.ffid {
                    Text("FFID \(ffid)").font(.system(size: 11)).foregroundColor(.secondary)
                }
                Text(l10n.f(.hdrTraceLabel, ["\(data.trace + 1)", ""]))
                    .font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
                closeButton
            }
            LinePlot(points: points,
                     xMin: tMin, xMax: tMax,
                     yMin: Double(-ampMax), yMax: Double(ampMax),
                     xTitle: l10n(.singleTraceAxisTime),
                     yTitle: l10n(.singleTraceAxisAmp),
                     drawsZeroLine: true,
                     lineWidth: 2.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 8) {
                rangeField()
                Button(l10n(.spectrumAuto)) { resetRange() }
                Spacer()
            }
        }
        .padding(14)
        .frame(minWidth: 1000, minHeight: 500)
        .onAppear { if !didInit { resetRange(); didInit = true } }
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func resetRange() {
        tMin = 0; tMax = fullSec
    }

    private func rangeField() -> some View {
        HStack(spacing: 4) {
            Text(l10n(.singleTraceTimeRange)).font(.system(size: 11)).foregroundColor(.secondary)
            TextField("", value: $tMin, format: .number).frame(width: 70)
            Text("–").foregroundColor(.secondary)
            TextField("", value: $tMax, format: .number).frame(width: 70)
            Text("s").font(.system(size: 10)).foregroundColor(.secondary)
        }
    }
}
