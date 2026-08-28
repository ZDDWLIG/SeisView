import SwiftUI
import SegyKit
import Localization

/// 单道波形弹窗：横轴时间(ms)、纵轴振幅，自绘折线。
struct SingleTraceView: View {
    let data: SingleTraceData
    @ObservedObject var l10n: L10n
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l10n(.singleTraceTitle)).font(.headline)
                Spacer()
                if let ffid = data.ffid {
                    Text("FFID \(ffid)").font(.system(size: 11)).foregroundColor(.secondary)
                }
                Text(l10n.f(.hdrTraceLabel, ["\(data.trace + 1)", ""]))
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            GeometryReader { geo in
                WaveformPlot(samples: data.samples, dtMicros: data.dtMicros)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            HStack {
                Text(l10n(.singleTraceAxisTime)).font(.system(size: 10)).foregroundColor(.secondary)
                Spacer()
                Text(l10n(.singleTraceAxisAmp)).font(.system(size: 10)).foregroundColor(.secondary)
            }
            HStack {
                Spacer()
                Button(l10n(.tbReset)) { dismiss() }
            }
        }
        .padding(14)
        .frame(minWidth: 520, minHeight: 320)
    }
}

/// 波形图：时间 → x，振幅 → y（自动缩放到自身 maxAbs）。
struct WaveformPlot: View {
    let samples: [Float]
    let dtMicros: Int

    var body: some View {
        Canvas { ctx, size in
            guard samples.count > 1 else { return }
            var m: Float = 0
            for v in samples { m = max(m, abs(v)) }
            if m <= 0 { return }
            let midY = size.height / 2
            let ampScale = Float(size.height / 2 - 8)
            let totalMs = Float(samples.count - 1) * Float(dtMicros) / 1000
            var path = Path()
            for (i, v) in samples.enumerated() {
                let x = CGFloat(i) / CGFloat(samples.count - 1) * size.width
                let y = midY - CGFloat(v / m * ampScale)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path, with: .color(.black), lineWidth: 1)
            // 零线
            var zero = Path()
            zero.move(to: CGPoint(x: 0, y: midY))
            zero.addLine(to: CGPoint(x: size.width, y: midY))
            ctx.stroke(zero, with: .color(.gray.opacity(0.5)), lineWidth: 0.5)
            _ = totalMs
        }
        .background(Color.white)
    }
}
