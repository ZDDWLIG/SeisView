import SegyKit

@MainActor
func runAll() {
    let h = Harness()
    h.check(SegyKit.version == "0.1.0", "SegyKit version")

    // 大端读取
    var beBytes: [UInt8] = [0x01, 0x02, 0x03, 0x04]
    beBytes.withUnsafeBytes {
        h.check(ByteOrderReader.u32($0.baseAddress!, .big) == 0x01020304, "BE u32")
        h.check(ByteOrderReader.u16($0.baseAddress! + 2, .big) == 0x0304, "BE u16")
    }
    var leBytes: [UInt8] = [0x01, 0x02, 0x03, 0x04]
    leBytes.withUnsafeBytes {
        h.check(ByteOrderReader.u32($0.baseAddress!, .little) == 0x04030201, "LE u32")
    }

    // IBM 解码参考值：IBM 0x41100000 = (-1)^0 × 0x100000 × 2^(4×1 − 280) = 1.0
    let tab = IBM.expTable()
    h.check(tab.count == 128, "expTable 128 entries")
    h.checkClose(IBM.toFloat(0x4110_0000, tab), 1.0, 1e-6, "IBM 1.0")
    h.checkClose(IBM.toFloat(0xC110_0000, tab), -1.0, 1e-6, "IBM -1.0")
    h.check(IBM.toFloat(0x0000_0000, tab) == 0.0, "IBM zero mantissa")
    // 0x4120_0000 = 2.0
    h.checkClose(IBM.toFloat(0x4120_0000, tab), 2.0, 1e-6, "IBM 2.0")

    h.finish()
}
runAll()
