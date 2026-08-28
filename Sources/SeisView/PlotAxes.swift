import Foundation

/// 计算一组「好看」的刻度值（1/2/5 × 10^k），覆盖 [min, max]，目标约 targetTicks 个。
func niceTicks(min: Double, max: Double, targetTicks: Int = 6) -> [Double] {
    guard max > min, targetTicks > 0 else { return [] }
    let range = max - min
    let rawStep = range / Double(targetTicks)
    let mag = pow(10.0, floor(log10(rawStep)))
    let norm = rawStep / mag
    let step: Double
    if norm < 1.5 { step = 1 }
    else if norm < 3.5 { step = 2 }
    else if norm < 7.5 { step = 5 }
    else { step = 10 }
    let stepMag = step * mag
    var ticks: [Double] = []
    var t = (min / stepMag).rounded(.down) * stepMag
    while t <= max + stepMag * 0.001 {
        ticks.append(t)
        t += stepMag
    }
    return ticks
}

/// 紧凑数字格式化（3 位有效数字），用于轴刻度标签。
func compactNum(_ v: Double) -> String {
    if abs(v) < 1e-12 { return "0" }
    return String(format: "%.3g", v)
}
