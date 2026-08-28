import SwiftUI
import AppKit

/// 自绘折线坐标图（AppKit）：曲线 + 坐标轴 + 刻度数值 + 轴标题。
/// 文字用 AppKit 的 NSAttributedString 绘制（SwiftUI Canvas 的文本在此 macOS 环境不可靠）。
struct LinePlot: NSViewRepresentable {
    let points: [CGPoint]            // 数据坐标 (x, y)
    let xMin: Double, xMax: Double, yMin: Double, yMax: Double
    let xTitle: String, yTitle: String
    let drawsZeroLine: Bool
    let lineWidth: CGFloat

    func makeNSView(context: Context) -> PlotNSView { PlotNSView() }

    func updateNSView(_ v: PlotNSView, context: Context) {
        v.points = points
        v.xMin = xMin; v.xMax = xMax; v.yMin = yMin; v.yMax = yMax
        v.xTitle = xTitle; v.yTitle = yTitle
        v.drawsZeroLine = drawsZeroLine
        v.lineWidth = lineWidth
        v.needsDisplay = true
    }
}

final class PlotNSView: NSView {
    var points: [CGPoint] = []
    var xMin = 0.0, xMax = 1.0, yMin = -1.0, yMax = 1.0
    var xTitle = "", yTitle = ""
    var drawsZeroLine = false
    var lineWidth: CGFloat = 2.5

    private let lineColor = NSColor.black
    private let gridColor = NSColor(calibratedWhite: 0.6, alpha: 1)
    private let labelColor = NSColor(calibratedWhite: 0.2, alpha: 1)
    private let leftPad: CGFloat = 56, bottomPad: CGFloat = 28, topPad: CGFloat = 8, rightPad: CGFloat = 10

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let plotW = bounds.width - leftPad - rightPad
        let plotH = bounds.height - topPad - bottomPad
        guard plotW > 0, plotH > 0, xMax > xMin, yMax > yMin else { return }
        let xr = xMax - xMin, yr = yMax - yMin

        func px(_ v: Double) -> CGFloat { leftPad + CGFloat((v - xMin) / xr) * plotW }
        func py(_ v: Double) -> CGFloat { bottomPad + CGFloat((v - yMin) / yr) * plotH }

        // 坐标轴边框（左竖线 + 底横线，两段分开，不能首尾相连成斜线）
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

        // y 轴刻度 + 数值（右对齐）
        for tick in niceTicks(min: yMin, max: yMax) {
            let y = py(tick)
            let mark = NSBezierPath()
            mark.move(to: NSPoint(x: leftPad - 4, y: y))
            mark.line(to: NSPoint(x: leftPad, y: y))
            mark.lineWidth = 0.5
            gridColor.setStroke(); mark.stroke()
            let s = compactNum(tick) as NSString
            let sz = s.size(withAttributes: labelAttrs)
            s.draw(at: NSPoint(x: leftPad - 6 - sz.width, y: y - sz.height / 2), withAttributes: labelAttrs)
        }
        // x 轴刻度 + 数值（居中）
        for tick in niceTicks(min: xMin, max: xMax) {
            let x = px(tick)
            let mark = NSBezierPath()
            mark.move(to: NSPoint(x: x, y: bottomPad))
            mark.line(to: NSPoint(x: x, y: bottomPad + 4))
            mark.lineWidth = 0.5
            gridColor.setStroke(); mark.stroke()
            let s = compactNum(tick) as NSString
            let sz = s.size(withAttributes: labelAttrs)
            s.draw(at: NSPoint(x: x - sz.width / 2, y: bottomPad - sz.height - 2), withAttributes: labelAttrs)
        }

        // 轴标题
        let xt = xTitle as NSString
        let xts = xt.size(withAttributes: labelAttrs)
        xt.draw(at: NSPoint(x: leftPad + plotW / 2 - xts.width / 2, y: 2), withAttributes: labelAttrs)
        drawRotated(yTitle, at: NSPoint(x: 18, y: bottomPad + plotH / 2), attributes: labelAttrs)

        // 零线
        if drawsZeroLine && yMin < 0 && yMax > 0 {
            let z = py(0)
            let zero = NSBezierPath()
            zero.move(to: NSPoint(x: leftPad, y: z))
            zero.line(to: NSPoint(x: leftPad + plotW, y: z))
            zero.lineWidth = 0.5
            gridColor.setStroke(); zero.stroke()
        }

        // 曲线（裁剪到绘图区，避免超出范围的点画进边距）
        guard points.count > 1 else { return }
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: leftPad, y: bottomPad, width: plotW, height: plotH)).addClip()
        let curve = NSBezierPath()
        var started = false
        for p in points {
            let pt = NSPoint(x: px(p.x), y: py(p.y))
            if !started { curve.move(to: pt); started = true }
            else { curve.line(to: pt) }
        }
        curve.lineWidth = lineWidth
        lineColor.setStroke()
        curve.stroke()
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private func drawRotated(_ text: String, at p: NSPoint, attributes: [NSAttributedString.Key: Any]) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.saveGState()
        cg.translateBy(x: p.x, y: p.y)
        cg.rotate(by: .pi / 2)   // 自下而上阅读（标准 y 轴标题方向）
        (text as NSString).draw(at: .zero, withAttributes: attributes)
        cg.restoreGState()
    }
}
