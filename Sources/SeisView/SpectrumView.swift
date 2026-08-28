import SwiftUI
import SegyKit
import Localization

/// 振幅谱弹窗：自绘坐标图 + x/y 轴范围输入 + 归一化开关。
struct SpectrumView: View {
    let result: SpectrumResult
    @ObservedObject var l10n: L10n
    @Environment(\.dismiss) private var dismiss

    @State private var xMin = 0.0
    @State private var xMax = 0.0
    @State private var yMin = 0.0
    @State private var yMax = 0.0
    @State private var normalized = false
    @State private var didInit = false

    private var nyquist: Double { result.spectrum.nyquist }
    private var maxAmp: Double { Double(result.spectrum.amplitudes.max() ?? 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l10n(.spectrumTitle)).font(.headline)
                Text(result.title).font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
            }
            GeometryReader { geo in
                SpectrumPlot(result: result,
                             xMin: xMin, xMax: xMax, yMin: yMin, yMax: yMax,
                             normalized: normalized)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            HStack(spacing: 16) {
                rangeField(l10n(.spectrumXRange), "\(l10n(.spectrumUnitHz))", $xMin, $xMax)
                rangeField(l10n(.spectrumYRange), "", $yMin, $yMax)
                Toggle(l10n(.spectrumNormalize), isOn: $normalized)
                Button(l10n(.spectrumAuto)) { resetRanges() }
                Spacer()
                Button(l10n(.tbReset)) { dismiss() }
            }
        }
        .padding(14)
        .frame(minWidth: 680, minHeight: 420)
        .onAppear {
            if !didInit { resetRanges(); didInit = true }
        }
    }

    private func resetRanges() {
        xMin = 0; xMax = nyquist
        yMin = 0; yMax = normalized ? 1 : maxAmp
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

/// 频谱折线图：把 [xMin,xMax]×[yMin,yMax] 内的点画成折线，归一化时 y 除以 max。
struct SpectrumPlot: View {
    let result: SpectrumResult
    let xMin: Double, xMax: Double, yMin: Double, yMax: Double
    let normalized: Bool

    var body: some View {
        Canvas { ctx, size in
            guard size.width > 0, size.height > 0 else { return }
            let spec = result.spectrum
            let xr = xMax > xMin ? xMax - xMin : 1
            let yr = yMax > yMin ? yMax - yMin : 1
            let scale = normalized ? Double(spec.amplitudes.max() ?? 1) : 1
            guard scale > 0 else { return }
            // 背景 + 边框
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            // 折线
            var path = Path()
            var started = false
            for i in 0..<spec.frequencies.count {
                let f = spec.frequencies[i]
                guard f >= xMin && f <= xMax else { continue }
                let amp = Double(spec.amplitudes[i]) / scale
                guard amp >= yMin && amp <= yMax else { continue }
                let px = CGFloat((f - xMin) / xr) * size.width
                let py = size.height - CGFloat((amp - yMin) / yr) * size.height
                if !started { path.move(to: CGPoint(x: px, y: py)); started = true }
                else { path.addLine(to: CGPoint(x: px, y: py)) }
            }
            ctx.stroke(path, with: .color(.black), lineWidth: 1)
        }
        .background(Color.white)
    }
}
