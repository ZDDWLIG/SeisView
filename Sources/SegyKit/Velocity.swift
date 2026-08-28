import Foundation

public enum Velocity {
    /// 视速度 = |Δoffset| / (|Δsample| · dt)，单位沿用 offset 字段（通常 m/s）。
    /// Δt 或 Δx 为零（两点击同一道/同一采样）时返回 nil。
    public static func apparentVelocity(offsetA: Int, offsetB: Int,
                                        sampleA: Int, sampleB: Int,
                                        dtMicros: Int) -> Float? {
        let ds = sampleB - sampleA
        let dx = offsetB - offsetA
        guard ds != 0, dx != 0, dtMicros > 0 else { return nil }
        let dtSeconds = Double(abs(ds)) * Double(dtMicros) / 1e6
        guard dtSeconds > 0 else { return nil }
        return Float(Double(abs(dx)) / dtSeconds)
    }
}
