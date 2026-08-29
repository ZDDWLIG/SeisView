import SwiftUI
import AppKit
import SegyKit
import Localization

/// 观测系统弹窗：炮点（红，稍大）/ 检波点（蓝）的 X-Y 散点图。
struct ObservationView: View {
    let layout: ObservationLayout
    @ObservedObject var l10n: L10n
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l10n(.obsTitle)).font(.headline)
                Spacer()
                legendDot(color: .red, label: l10n.f(.obsShots, ["\(layout.shots.count)"]))
                legendDot(color: .blue, label: l10n.f(.obsReceivers, ["\(layout.receivers.count)"]))
                closeButton
            }
            ScatterPlot(shots: layout.shots, receivers: layout.receivers, shotReceivers: layout.shotReceivers,
                        shotElevations: layout.shotElevations, receiverElevations: layout.receiverElevations)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(l10n(.obsClickHint)).font(.system(size: 10)).foregroundColor(.secondary)
        }
        .padding(14)
        .frame(minWidth: 900, minHeight: 650)
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 11)).foregroundColor(.secondary)
        }
    }
}

/// 双序列散点坐标图（AppKit）：炮点红、检波点蓝，点击炮点高亮其检波点（绿），
/// 点击任意点弹出 (x, y, z) 半透明坐标框。
struct ScatterPlot: NSViewRepresentable {
    let shots: [GeoPoint]
    let receivers: [GeoPoint]
    let shotReceivers: [[Int]]
    let shotElevations: [Double]
    let receiverElevations: [Double]

    func makeNSView(context: Context) -> ScatterNSView { ScatterNSView() }

    func updateNSView(_ v: ScatterNSView, context: Context) {
        v.shots = shots
        v.receivers = receivers
        v.shotReceivers = shotReceivers
        v.shotElevations = shotElevations
        v.receiverElevations = receiverElevations
        v.needsDisplay = true
    }
}

final class ScatterNSView: NSView {
    var shots: [GeoPoint] = []
    var receivers: [GeoPoint] = []
    var shotReceivers: [[Int]] = []
    var shotElevations: [Double] = []
    var receiverElevations: [Double] = []
    /// 当前选中的炮（shots 的下标）；nil = 未选中。
    private(set) var selectedShot: Int? = nil

    /// 上次 draw 时的数据范围与有效性，供鼠标命中检测复用同一套映射。
    private var xMin = 0.0, xMax = 1.0, yMin = 0.0, yMax = 1.0
    private var hasData = false

    /// 弹出的坐标框（屏幕坐标 + 文本）；nil = 不显示。
    private struct PopupInfo {
        let point: CGPoint
        let text: String
    }
    private var popup: PopupInfo? = nil

    private let gridColor = NSColor(calibratedWhite: 0.6, alpha: 1)
    private let labelColor = NSColor(calibratedWhite: 0.2, alpha: 1)
    private let shotColor = NSColor.systemRed
    private let receiverColor = NSColor.systemBlue
    private let highlightColor = NSColor.systemGreen
    private let popupTextAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor.white
    ]
    private let leftPad: CGFloat = 60, bottomPad: CGFloat = 44, topPad: CGFloat = 20, rightPad: CGFloat = 14

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()

        let plotW = bounds.width - leftPad - rightPad
        let plotH = bounds.height - topPad - bottomPad
        guard plotW > 0, plotH > 0 else { return }

        // 数据范围（自动缩放，含 5% 边距；单点/共线时用 ±1 兜底避免零宽）
        var xMin = 0.0, xMax = 0.0, yMin = 0.0, yMax = 0.0
        var has = false
        for p in shots + receivers {
            if !has { xMin = p.x; xMax = p.x; yMin = p.y; yMax = p.y; has = true }
            else {
                xMin = min(xMin, p.x); xMax = max(xMax, p.x)
                yMin = min(yMin, p.y); yMax = max(yMax, p.y)
            }
        }
        guard has else { self.hasData = false; return }
        let xPad = (xMax - xMin) > 0 ? (xMax - xMin) * 0.05 : max(1, abs(xMax) * 0.05)
        let yPad = (yMax - yMin) > 0 ? (yMax - yMin) * 0.05 : max(1, abs(yMax) * 0.05)
        xMin -= xPad; xMax += xPad; yMin -= yPad; yMax += yPad
        self.xMin = xMin; self.xMax = xMax; self.yMin = yMin; self.yMax = yMax
        self.hasData = true

        func px(_ v: Double) -> CGFloat { leftPad + CGFloat((v - xMin) / (xMax - xMin)) * plotW }
        func py(_ v: Double) -> CGFloat { bottomPad + CGFloat((v - yMin) / (yMax - yMin)) * plotH }

        // 坐标轴边框（左 + 底，两段分开）
        let axis = NSBezierPath()
        axis.move(to: NSPoint(x: leftPad, y: bottomPad))
        axis.line(to: NSPoint(x: leftPad, y: bottomPad + plotH))
        axis.move(to: NSPoint(x: leftPad, y: bottomPad))
        axis.line(to: NSPoint(x: leftPad + plotW, y: bottomPad))
        axis.lineWidth = 1
        gridColor.setStroke()
        axis.stroke()

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: labelColor
        ]

        // 刻度：mantissa 标签（去掉 e+06），指数单独放轴端 ×10^k。
        let xt = scaledTicks(min: xMin, max: xMax)
        let yt = scaledTicks(min: yMin, max: yMax)
        for (tick, label) in zip(xt.ticks, xt.labels) {
            let x = px(tick)
            let mark = NSBezierPath()
            mark.move(to: NSPoint(x: x, y: bottomPad))
            mark.line(to: NSPoint(x: x, y: bottomPad + 4))
            mark.lineWidth = 0.5
            gridColor.setStroke(); mark.stroke()
            let s = label as NSString
            let sz = s.size(withAttributes: labelAttrs)
            s.draw(at: NSPoint(x: x - sz.width / 2, y: bottomPad - sz.height - 2), withAttributes: labelAttrs)
        }
        for (tick, label) in zip(yt.ticks, yt.labels) {
            let y = py(tick)
            let mark = NSBezierPath()
            mark.move(to: NSPoint(x: leftPad - 4, y: y))
            mark.line(to: NSPoint(x: leftPad, y: y))
            mark.lineWidth = 0.5
            gridColor.setStroke(); mark.stroke()
            let s = label as NSString
            let sz = s.size(withAttributes: labelAttrs)
            s.draw(at: NSPoint(x: leftPad - 6 - sz.width, y: y - sz.height / 2), withAttributes: labelAttrs)
        }

        // 指数注解：x 轴右端（刻度下一行）、y 轴上端。
        if xt.exp != 0 {
            let s = exponentText(xt.exp) as NSString
            let sz = s.size(withAttributes: labelAttrs)
            s.draw(at: NSPoint(x: leftPad + plotW - sz.width, y: bottomPad - sz.height * 2 - 4), withAttributes: labelAttrs)
        }
        if yt.exp != 0 {
            let s = exponentText(yt.exp) as NSString
            s.draw(at: NSPoint(x: leftPad - 2, y: bottomPad + plotH + 2), withAttributes: labelAttrs)
        }

        // 检波点（蓝，小）先画，炮点（红，大）后画盖在上层；选中炮的检波点画绿色。
        let highlightSet: Set<Int> = {
            if let s = selectedShot, s < shotReceivers.count { return Set(shotReceivers[s]) }
            return []
        }()
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: leftPad, y: bottomPad, width: plotW, height: plotH)).addClip()
        for (i, p) in receivers.enumerated() {
            (highlightSet.contains(i) ? highlightColor : receiverColor).setFill()
            let r: CGFloat = 1.25
            let c = NSPoint(x: px(p.x), y: py(p.y))
            NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()
        }
        shotColor.setFill()
        for p in shots {
            let r: CGFloat = 2.8125
            let c = NSPoint(x: px(p.x), y: py(p.y))
            NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()
        }
        NSGraphicsContext.current?.restoreGraphicsState()

        // 坐标框（半透明灰底白字，画在最上层，不受绘图区裁剪）
        if let popup = popup {
            let lines = popup.text.components(separatedBy: "\n")
            let lineHeight: CGFloat = 14
            let textW = lines.map { ($0 as NSString).size(withAttributes: popupTextAttrs).width }.max() ?? 0
            let boxW = textW + 18
            let boxH = CGFloat(lines.count) * lineHeight + 12
            var boxX = popup.point.x + 14
            var boxY = popup.point.y + 14
            boxX = min(max(boxX, 4), bounds.width - boxW - 4)
            boxY = min(max(boxY, 4), bounds.height - boxH - 4)
            let boxRect = NSRect(x: boxX, y: boxY, width: boxW, height: boxH)
            NSColor(calibratedWhite: 0.15, alpha: 0.82).setFill()
            NSBezierPath(roundedRect: boxRect, xRadius: 5, yRadius: 5).fill()
            for (i, line) in lines.enumerated() {
                let y = boxY + boxH - lineHeight * CGFloat(i + 1) - 6
                (line as NSString).draw(at: NSPoint(x: boxX + 9, y: y), withAttributes: popupTextAttrs)
            }
        }
    }

    /// 点击：命中炮点 → 切换高亮并弹其 (x,y,z)；命中检波点 → 弹其 (x,y,z)；
    /// 空白 → 清除高亮与坐标框。命中判定复用 draw 的映射。
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard hasData, xMax > xMin, yMax > yMin else { return }
        let plotW = bounds.width - leftPad - rightPad
        let plotH = bounds.height - topPad - bottomPad
        guard plotW > 0, plotH > 0 else { return }
        func px(_ v: Double) -> CGFloat { leftPad + CGFloat((v - xMin) / (xMax - xMin)) * plotW }
        func py(_ v: Double) -> CGFloat { bottomPad + CGFloat((v - yMin) / (yMax - yMin)) * plotH }

        // 先找炮点（较大，优先命中）
        var bestShot: Int? = nil
        var bestShotDist = CGFloat.greatestFiniteMagnitude
        for (i, s) in shots.enumerated() {
            let c = NSPoint(x: px(s.x), y: py(s.y))
            let dx = c.x - p.x, dy = c.y - p.y
            let d = sqrt(dx * dx + dy * dy)
            if d < bestShotDist { bestShotDist = d; bestShot = i }
        }
        if let b = bestShot, bestShotDist <= 8 {
            selectedShot = (selectedShot == b) ? nil : b
            popup = PopupInfo(point: NSPoint(x: px(shots[b].x), y: py(shots[b].y)),
                              text: coordinateText(x: shots[b].x, y: shots[b].y,
                                                   z: b < shotElevations.count ? shotElevations[b] : 0))
            needsDisplay = true
            return
        }
        // 再找检波点
        var bestRec: Int? = nil
        var bestRecDist = CGFloat.greatestFiniteMagnitude
        for (i, r) in receivers.enumerated() {
            let c = NSPoint(x: px(r.x), y: py(r.y))
            let dx = c.x - p.x, dy = c.y - p.y
            let d = sqrt(dx * dx + dy * dy)
            if d < bestRecDist { bestRecDist = d; bestRec = i }
        }
        if let r = bestRec, bestRecDist <= 6 {
            popup = PopupInfo(point: NSPoint(x: px(receivers[r].x), y: py(receivers[r].y)),
                              text: coordinateText(x: receivers[r].x, y: receivers[r].y,
                                                   z: r < receiverElevations.count ? receiverElevations[r] : 0))
            needsDisplay = true
            return
        }
        // 空白：清除高亮与坐标框
        selectedShot = nil
        popup = nil
        needsDisplay = true
    }

    /// (x, y, z) 三行坐标文本，去尾零。
    private func coordinateText(x: Double, y: Double, z: Double) -> String {
        "x = \(trimZero(String(format: "%.3f", x)))\n" +
        "y = \(trimZero(String(format: "%.3f", y)))\n" +
        "z = \(trimZero(String(format: "%.3f", z)))"
    }

    /// 刻度：返回 (原始刻度值, mantissa 标签, 指数)。标签去掉 10^exp，指数单独注解在轴端。
    private func scaledTicks(min lo: Double, max hi: Double, targetTicks: Int = 6) -> (ticks: [Double], labels: [String], exp: Int) {
        let ticks = niceTicks(min: lo, max: hi, targetTicks: targetTicks)
        let maxAbs = max(abs(lo), abs(hi))
        let exp = maxAbs > 0 ? Int(floor(log10(maxAbs))) : 0
        let scale = pow(10.0, Double(exp))
        let mantissa = ticks.map { $0 / scale }
        let step = mantissa.count > 1 ? mantissa[1] - mantissa[0] : 0
        let decimals = step > 0 ? min(6, max(0, Int(ceil(-log10(step))))) : 0
        let labels = mantissa.map { trimZero(String(format: "%.\(decimals)f", $0)) }
        return (ticks, labels, exp)
    }

    /// 去掉小数末尾的 0（"4.480" → "4.48"、"4.500" → "4.5"、"0.000" → "0"）。
    private func trimZero(_ s: String) -> String {
        guard s.contains(".") else { return s }
        var t = s
        while t.hasSuffix("0") { t.removeLast() }
        if t.hasSuffix(".") { t.removeLast() }
        return t.isEmpty ? "0" : t
    }

    private func exponentText(_ exp: Int) -> String {
        "×10^\(exp)"
    }
}
