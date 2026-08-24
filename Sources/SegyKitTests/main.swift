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

    // BinaryHeader 解析：构造 400 字节，offset 是 1-indexed 字段位置 −1
    var bh = [UInt8](repeating: 0, count: 400)
    bh[16] = 0x07; bh[17] = 0xD0                      // 3217-3218 → raw[16..17] dt=2000
    bh[20] = 0x0F; bh[21] = 0xA0                      // 3221-3222 → raw[20..21] ns=4000
    bh[24] = 0x00; bh[25] = 0x01                      // 3225-3226 → raw[24..25] format=1
    bh[102] = 0x01                                    // 3503-3504 定长标志
    bh[104] = 0x00; bh[105] = 0x02                    // 3505-3506 扩展头=2
    let parsed = SegyFile.parseBinaryHeader(bh)
    h.check(parsed.ns == 4000, "bh ns"); h.check(parsed.dtMicros == 2000, "bh dt")
    h.check(parsed.formatCode == 1, "bh format"); h.check(parsed.extTextHeaders == 2, "bh ext text")

    // SampleFormat 字节宽
    h.check(SampleFormat.ibm32.bytesPerSample == 4, "ibm32 width")
    h.check(SampleFormat.int16.bytesPerSample == 2, "int16 width")

    // Decoder：IBM 大端 4 采样 = 1,2,3,-1
    var ibmBytes: [UInt8] = []
    for v: UInt32 in [0x4110_0000, 0x4120_0000, 0x4130_0000, 0xC110_0000] {
        withUnsafeBytes(of: v.bigEndian) { ibmBytes.append(contentsOf: $0) }
    }
    var out = [Float](repeating: 0, count: 4)
    ibmBytes.withUnsafeBytes {
        Decoder.decode(bytes: $0.baseAddress!, count: 4, format: .ibm32, order: .big, into: &out)
    }
    h.checkClose(out[0], 1.0, 1e-5, "dec ibm 1"); h.checkClose(out[3], -1.0, 1e-5, "dec ibm -1")

    h.finish()
}
runAll()
