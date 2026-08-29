import SwiftUI
import SegyKit
import Localization

/// 带通滤波弹窗：设置低/高截止频率，应用或清除。
struct FilterView: View {
    @ObservedObject var model: DocumentModel
    @ObservedObject var l10n: L10n
    @Environment(\.dismiss) private var dismiss

    @State private var lowHz = 0.0
    @State private var highHz = 0.0
    @State private var didInit = false

    private var nyquist: Double {
        guard let f = model.file, f.geometry.dtMicros > 0 else { return 0 }
        return 1.0 / (2.0 * Double(f.geometry.dtMicros) / 1e6)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(l10n(.filterTitle)).font(.headline)
                if model.viewport.filter != nil {
                    Text(l10n(.filterActive)).font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
                closeButton
            }
            VStack(alignment: .leading, spacing: 10) {
                freqField(l10n(.filterLowCut), $lowHz)
                freqField(l10n(.filterHighCut), $highHz)
                Text(l10n.f(.filterNyquist, [compactNum(nyquist)]))
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
            HStack {
                Button(l10n(.filterApply)) {
                    model.setFilter(BandFilter(lowHz: max(0, lowHz), highHz: max(0, highHz)))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                Button(l10n(.filterClear)) {
                    model.setFilter(nil)
                    dismiss()
                }
                .disabled(model.viewport.filter == nil)
                Spacer()
            }
        }
        .padding(16)
        .frame(minWidth: 340, minHeight: 200)
        .onAppear {
            if !didInit {
                let nyq = nyquist
                if let f = model.viewport.filter {
                    lowHz = f.lowHz; highHz = f.highHz
                } else {
                    lowHz = 0
                    highHz = min(100, nyq > 0 ? nyq : 100)
                }
                didInit = true
            }
        }
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func freqField(_ label: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 12)).frame(width: 110, alignment: .leading)
            TextField("", value: value, format: .number).frame(width: 90)
            Text(l10n(.spectrumUnitHz)).font(.system(size: 10)).foregroundColor(.secondary)
        }
    }
}
