import Foundation

public enum IBM {
    public static func expTable() -> [Float] {
        (0..<128).map { Float(exp2(Double(4 * $0 - 280))) }
    }
    @inlinable
    public static func toFloat(_ raw: UInt32, _ tab: [Float]) -> Float {
        let mant = raw & 0x00FF_FFFF
        if mant == 0 { return 0 }
        let e = Int((raw >> 24) & 0x7F)
        let v = Float(mant) * tab[e]
        return (raw & 0x8000_0000) != 0 ? -v : v
    }
}
