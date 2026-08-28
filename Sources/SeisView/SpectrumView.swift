import SwiftUI
import SegyKit
import Localization

/// 振幅谱弹窗：自绘坐标图（含刻度）+ x/y 轴范围输入 + 分贝谱开关。
struct SpectrumView: View {
    let result: SpectrumResult
    @ObservedObject var l10n: L10n
    @Environment(\.dismiss) private var dismiss

    @State private var xMin = 0.0
    @State private var xMax = 0.0
    @State private var yMin = 0.0
    @State private var yMax = 0.0
    @State private var db = false
    @State private var didInit = false

    private var nyquist: Double { result.spectrum.nyquist }
    private var maxAmp: Double { Double(result.spectrum.amplitudes.max() ?? 0) }

    /// 频谱折线点（数据坐标：x=Hz，y=振幅或 dB），裁到 [xMin, xMax]。
    private var points: [CGPoint] {
        let spec = result.spectrum
        guard maxAmp > 0 else { return [] }
        var out: [CGPoint] = []
        for i in 0..<spec.frequencies.count {
            let f = spec.frequencies[i]
            guard f >= xMin && f <= xMax else { continue }
            let amp = Double(spec.amplitudes[i])
            let yValue: Double
            if db {
                let a = max(amp, maxAmp * 1e-12)
                yValue = 20 * log10(a / maxAmp)
            } else {
                yValue = amp
            }
            out.append(CGPoint(x: f, y: yValue))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l10n(.spectrumTitle)).font(.headline)
                Text(result.title).font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
                closeButton
            }
            LinePlot(points: points,
                     xMin: xMin, xMax: xMax, yMin: yMin, yMax: yMax,
                     xTitle: l10n(.spectrumXAxis),
                     yTitle: db ? l10n(.spectrumUnitDb) : l10n(.spectrumYAxis),
                     drawsZeroLine: false,
                     lineWidth: 2.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 16) {
                rangeField(l10n(.spectrumXRange), "\(l10n(.spectrumUnitHz))", $xMin, $xMax)
                rangeField(l10n(.spectrumYRange), "", $yMin, $yMax)
                Toggle(l10n(.spectrumNormalize), isOn: Binding(
                    get: { db },
                    set: { on in
                        db = on
                        if on { yMin = -120; yMax = 0 } else { yMin = 0; yMax = maxAmp }
                    }
                ))
                Button(l10n(.spectrumAuto)) { resetRanges() }
                Spacer()
            }
        }
        .padding(14)
        .frame(minWidth: 820, minHeight: 540)
        .onAppear { if !didInit { resetRanges(); didInit = true } }
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func resetRanges() {
        // x 默认显示 0–100 Hz（若 Nyquist 更小则取 Nyquist）
        xMin = 0; xMax = min(100, nyquist)
        if db { yMin = -120; yMax = 0 } else { yMin = 0; yMax = maxAmp }
    }

    private func rangeField(_ label: String, _ unit: String,
                            _ lo: Binding<Double>, _ hi: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundColor(.secondary)
            TextField("", value: lo, format: .number).frame(width: 70)
            Text("–").foregroundColor(.secondary)
            TextField("", value: hi, format: .number).frame(width: 70)
            if !unit.isEmpty { Text(unit).font(.system(size: 10)).foregroundColor(.secondary) }
        }
    }
}
