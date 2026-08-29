import Foundation

/// 观测系统中的一个点（坐标已经过比例因子换算的物理坐标）。
public struct GeoPoint: Hashable, Sendable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// 观测系统布局：去重后的炮点与检波点，以及每个炮覆盖哪些检波点。
public struct ObservationLayout: Sendable {
    /// 每个炮（FFID）一个点，按首现顺序。
    public let shots: [GeoPoint]
    /// 去重后的检波点，按首现顺序。
    public let receivers: [GeoPoint]
    /// 每个炮覆盖的检波点下标：shotReceivers[i] 是 shots[i] 对应炮的检波点（receivers 的下标）。
    public let shotReceivers: [[Int]]
    /// 高程（z），与 shots 平行：炮点 = 源地表高程。
    public let shotElevations: [Double]
    /// 高程（z），与 receivers 平行：检波点 = 检波点高程。
    public let receiverElevations: [Double]
    public init(shots: [GeoPoint], receivers: [GeoPoint], shotReceivers: [[Int]] = [],
                shotElevations: [Double] = [], receiverElevations: [Double] = []) {
        self.shots = shots; self.receivers = receivers; self.shotReceivers = shotReceivers
        self.shotElevations = shotElevations; self.receiverElevations = receiverElevations
    }
}

/// 观测系统扫描：读全部道头，产出炮点 + 去重检波点 + 每炮覆盖的检波点下标。
/// 与 OffsetIndexBuilder 一样只依赖 `TraceHeaderSource`，测试可注入假 source。
public enum ObservationBuilder {
    /// 分块读道头、边读边去重，避免把整文件道头同时留在内存里。
    public static func build(source: TraceHeaderSource, nTraces: Int, chunk: Int = 8192) -> ObservationLayout {
        guard nTraces > 0 else { return ObservationLayout(shots: [], receivers: [], shotReceivers: []) }
        var seenFFID = Set<Int>()
        var shots: [GeoPoint] = []
        var shotElevations: [Double] = []
        var receiverIndex: [GeoPoint: Int] = [:]
        var receivers: [GeoPoint] = []
        var receiverElevations: [Double] = []
        var shotReceivers: [[Int]] = []
        var currentShotSet = Set<Int>()   // 当前炮内去重

        var i = 0
        while i < nTraces {
            let end = min(i + chunk, nTraces)
            for h in source.readTraceHeaders(range: i..<end) {
                if seenFFID.insert(h.ffid).inserted {
                    shots.append(GeoPoint(x: h.sourceX, y: h.sourceY))
                    shotElevations.append(h.sourceElevationValue)
                    shotReceivers.append([])
                    currentShotSet.removeAll(keepingCapacity: true)
                }
                let rp = GeoPoint(x: h.receiverX, y: h.receiverY)
                let idx: Int
                if let e = receiverIndex[rp] { idx = e }
                else {
                    idx = receivers.count; receiverIndex[rp] = idx; receivers.append(rp)
                    receiverElevations.append(h.receiverElevationValue)
                }
                if currentShotSet.insert(idx).inserted {
                    shotReceivers[shotReceivers.count - 1].append(idx)
                }
            }
            i = end
        }
        return ObservationLayout(shots: shots, receivers: receivers, shotReceivers: shotReceivers,
                                 shotElevations: shotElevations, receiverElevations: receiverElevations)
    }
}
