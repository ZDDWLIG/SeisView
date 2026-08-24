import Foundation
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
    bh[302] = 0x01                                    // 3503-3504 定长标志
    bh[304] = 0x00; bh[305] = 0x02                    // 3505-3506 扩展头=2
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

    // 合成一个合法文件：3600 文本头 + 3 道 (ns=100, IBM)
    func writeSegy(_ path: String, ns: Int, formatCode: Int, traces: Int, extText: Int = 0) {
        var d = [UInt8](repeating: 0, count: 3600 + extText * 3200)
        d[3216] = 0x07; d[3217] = 0xD0          // dt=2000
        let nsB = UInt16(ns)
        d[3220] = UInt8(nsB >> 8); d[3221] = UInt8(nsB & 0xFF)
        d[3224] = UInt8(formatCode >> 8); d[3225] = UInt8(formatCode & 0xFF)
        d[3502] = 0x00; d[3503] = 0x01          // 3503-3504 定长标志
        d[3504] = UInt8(extText >> 8); d[3505] = UInt8(extText & 0xFF)
        for t in 0..<traces {
            var tr = [UInt8](repeating: 0, count: 240 + ns * 4)
            let seq = UInt32(t + 1).bigEndian
            withUnsafeBytes(of: seq) { for (i, b) in $0.enumerated() { tr[i] = b } }   // 1-4 道序号
            tr[8] = 0x00; tr[9] = 0x00; tr[10] = 0x00; tr[11] = 0x2A                  // 9-12 FFID=42
            tr[114] = UInt8(ns >> 8); tr[115] = UInt8(ns & 0xFF)                       // 115-116 ns
            d += tr
        }
        try! Data(d).write(to: URL(fileURLWithPath: path))
    }
    let tmpDir = NSTemporaryDirectory()
    let good = tmpDir + "segy_good.sgy"
    writeSegy(good, ns: 100, formatCode: 1, traces: 3)
    let f = try! SegyFile.open(url: URL(fileURLWithPath: good))
    h.check(f.geometry.ns == 100, "open ns")
    h.check(f.geometry.nTraces == 3, "open nTraces")
    h.check(f.geometry.firstTraceOffset == 3600, "open firstTraceOffset")
    h.check(f.geometry.traceBytes == 240 + 100 * 4, "open traceBytes")
    h.check(f.geometry.format == .ibm32, "open format")
    h.check(f.geometry.dtMicros == 2000, "open dt")

    let bad = tmpDir + "segy_bad.sgy"
    writeSegy(bad, ns: 100, formatCode: 1, traces: 2)
    // 尾部追加半个道长，制造"除不尽"（同一句柄 seek 到末尾再写，才是真正的追加）
    let fh = try! FileHandle(forUpdatingAtPath: bad)!
    try! fh.seekToEndOfFile()
    try! fh.write(Data([UInt8](repeating: 0, count: 50)))
    var threw = false
    do { _ = try SegyFile.open(url: URL(fileURLWithPath: bad)) } catch { threw = true }
    h.check(threw, "variable-length detected")

    // 畸形文件：二进制头声称有 1 个扩展文本头（extOffset=6800），但文件只有 3600 字节
    // 若 extOffset > size 未校验，size - extOffset 会在 UInt64 下回绕成巨大值
    let under = tmpDir + "segy_under.sgy"
    var u = [UInt8](repeating: 0, count: 3600)          // 3200 文本头 + 400 二进制头，无扩展头、无道
    u[3224] = 0x00; u[3225] = 0x01                      // format=1 (ibm32)，让 sampleFormat 通过
    u[3504] = 0x00; u[3505] = 0x01                      // extTextHeaders=1 → extOffset=6800 > 3600
    try! Data(u).write(to: URL(fileURLWithPath: under))
    var underThrew = false
    do { _ = try SegyFile.open(url: URL(fileURLWithPath: under)) } catch let e {
        // 必须命中 extOffset 保护（.fileTooSmall），而非后续的 badSampleCount/其他错误
        if case SegyError.fileTooSmall = e { underThrew = true }
    }
    h.check(underThrew, "extOffset underflow guarded")

    // Task 5: 并行 TraceReader
    let good2 = tmpDir + "segy_read.sgy"
    writeSegy(good2, ns: 1000, formatCode: 1, traces: 100)
    let fr = try! SegyFile.open(url: URL(fileURLWithPath: good2))
    let rdr = TraceReader(file: fr, maxThreads: 4)
    let data = rdr.readDecoded(traceRange: 0..<100, sampleRange: nil)
    h.check(data.count == 100 * 1000, "readDecoded count")
    // 只读时窗
    let win = rdr.readDecoded(traceRange: 0..<10, sampleRange: 100..<200)
    h.check(win.count == 10 * 100, "readDecoded sample window count")
    let hdrs = rdr.readTraceHeaders(range: 0..<100)
    h.check(hdrs[0].ffid == 42, "readTraceHeaders ffid")

    // Task 6: Decimator（min/max 分箱）
    // 4 道 × 8 采样 → 高 2 像素，每 bin 4 采样
    var src: [Float] = []
    for t in 0..<4 { for s in 0..<8 { src.append(Float(t * 8 + s)) } }
    let b = Decimator.minMax(src, ns: 8, nTraces: 4, h: 2)
    h.check(b.w == 4 && b.h == 2, "binned dims")
    // 道 0 的采样 0..8 → bin0=min(0,3)=0 max=3，bin1=4..7
    h.check(b.mn[0] == 0 && b.mx[0] == 3, "bin minmax row0")
    h.check(b.mn[1] == 4 && b.mx[1] == 7, "bin minmax row1")
    // 道 3 的 bin0 = min(24,27)=24 max=27
    h.check(b.mn[3 * 2 + 0] == 24 && b.mx[3 * 2 + 0] == 27, "bin minmax trace3")

    // Task 7: Gain 标定
    var b0 = Binned(w: 1, h: 1, mn: [-10], mx: [10])
    let g0 = Gain.apply(b0, .percentiles(0.005, 0.995))
    h.check(g0.mn[0] > -10 && g0.mn[0] < 0, "percentile clip low")
    h.check(g0.mx[0] > 0 && g0.mx[0] < 10, "percentile clip high")
    var bz = Binned(w: 2, h: 2, mn: [0,0,0,0], mx: [0,0,0,0])
    let gz = Gain.apply(bz, .maxAbs)
    h.check(gz.mn.allSatisfy { $0.isFinite } && gz.mx.allSatisfy { $0.isFinite }, "zero no NaN")

    // Final-review Fix 2: maxAbs 对称归一化（区别于 percentiles 的 min-max 映射）
    let bm = Binned(w: 1, h: 1, mn: [-10], mx: [10])
    let gm = Gain.apply(bm, .maxAbs)
    h.check(gm.mn[0].isFinite && gm.mx[0].isFinite, "maxAbs finite")
    h.checkClose(gm.mn[0], -1, 1e-3, "maxAbs symmetric mn ≈ -1")
    h.checkClose(gm.mx[0], 1, 1e-3, "maxAbs symmetric mx ≈ 1")
    h.check(abs(gm.mn[0]) == abs(gm.mx[0]), "maxAbs symmetric |mn|==|mx|")
    // 非对称数据：maxAbs 按 max_abs 归一化 → mn∈(-1,0)，而 min-max 映射会给 -1
    let ba = Binned(w: 1, h: 1, mn: [-10], mx: [30])
    let ga = Gain.apply(ba, .maxAbs)
    h.checkClose(ga.mx[0], 1, 1e-3, "maxAbs asym mx ≈ 1")
    h.check(ga.mn[0] > -1 && ga.mn[0] < 0, "maxAbs asym mn in (-1,0) (got \(ga.mn[0]))")

    // Task 8: Rasterizer（灰度 + seismic 调色板）
    let img = Rasterizer.makeImage(Binned(w: 4, h: 3, mn: [0,0,0,0,0,0,0,0,0,0,0,0],
                                          mx: [1,1,1,1,1,1,1,1,1,1,1,1]), palette: .grayscale)
    h.check(img.width == 4 && img.height == 3, "raster dims")
    // 全正 → 灰度应偏白（8bit > 128）
    let cgData = img.dataProvider!.data! as Data
    h.check(cgData[0] > 128, "grayscale white for positive")

    // Task 9: ShotIndex 炮索引（抽样 + 二分）
    // 120 道，前 60 道 FFID=100，后 60 道 FFID=200
    func writeMultiShot(_ path: String) {
        var d = [UInt8](repeating: 0, count: 3600)
        d[3216] = 0x07; d[3217] = 0xD0; d[3220] = 0x00; d[3221] = 0x64  // ns=100
        d[3224] = 0x00; d[3225] = 0x01
        for t in 0..<120 {
            var tr = [UInt8](repeating: 0, count: 240 + 100 * 4)
            let ffid: UInt32 = t < 60 ? 100 : 200
            withUnsafeBytes(of: ffid.bigEndian) { for (i, b) in $0.enumerated() { tr[8 + i] = b } }
            tr[114] = 0x00; tr[115] = 0x64
            d += tr
        }
        try! Data(d).write(to: URL(fileURLWithPath: path))
    }
    let ms = tmpDir + "segy_multishot.sgy"
    writeMultiShot(ms)
    let mf = try! SegyFile.open(url: URL(fileURLWithPath: ms))
    let shots = ShotIndex.build(reader: TraceReader(file: mf), nTraces: mf.geometry.nTraces)
    h.check(shots.count == 2, "shot count")
    h.check(shots[0] == Shot(ffid: 100, firstTrace: 0, count: 60), "shot 1")
    h.check(shots[1] == Shot(ffid: 200, firstTrace: 60, count: 60), "shot 2")

    // Task 10: 真实文件黄金测试（vs segyio）+ 性能回归
    // 期望值由 segyio 生成（见 report），ns=4000, nTraces=589248,
    // vals = [t0s0..t0s9, t1s0..t1s9, t2s0..t2s9]
    let bigPath = ProcessInfo.processInfo.environment["SEGY_BIG_FILE"] ??
        "/path/to/big.segy"
    let bf = try! SegyFile.open(url: URL(fileURLWithPath: bigPath))
    h.check(bf.geometry.ns == 4000, "big file ns")
    h.check(bf.geometry.nTraces == 589248, "big file nTraces")
    let rdr2 = TraceReader(file: bf, maxThreads: 8)
    let first = rdr2.readDecoded(traceRange: 0..<3, sampleRange: 0..<10)
    h.check(first.count == 30, "big file 3×10 count")
    let gold: [Float] = [
        // trace 0 (samples 0-9)
        4.539411747828126e-05, -0.00016471336130052805, 0.00017713110719341785,
        -0.00025798031128942966, 0.0001991456956602633, -4.750918014906347e-05,
        4.395961877889931e-05, -8.894057828001678e-05, -4.121581150684506e-05,
        1.1413279025873635e-05,
        // trace 1 (samples 0-9)
        0.0002916385419666767, -0.000205475022085011, 0.00014127494068816304,
        -5.595973925665021e-05, -2.4273567760246806e-06, -2.3605942260473967e-05,
        -3.961613401770592e-05, -9.24542109714821e-05, -3.0440889531746507e-05,
        -0.0001222032733494416,
        // trace 2 (samples 0-9)
        0.0007365562487393618, -0.0004857792519032955, 0.0003083455376327038,
        -8.62692977534607e-05, 4.334631375968456e-05, -8.490505933878012e-06,
        6.003121961839497e-05, 3.556542651494965e-06, -2.416834468021989e-05,
        3.818098048213869e-05,
    ]
    for i in 0..<30 {
        // 三道的第 0/10/20 个值 = 各道首采样，尤其能暴露 traceBytes 步长错误
        h.checkRel(first[i], gold[i], 1e-3, "gold trace\(i / 10) sample\(i % 10) (idx \(i))")
    }

    // 性能回归：8 线程读一屏（1200 道 × 4000 采样）应 < 120 ms
    let perf = TraceReader(file: bf, maxThreads: 8)
    let t0 = DispatchTime.now().uptimeNanoseconds
    _ = perf.readDecoded(traceRange: 0..<1200, sampleRange: nil)
    let perfMs = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
    h.check(perfMs < 120, "perf: 1200 traces < 120ms (got \(perfMs)ms)")

    // Task 15: 假 IBM 真 IEEE 自动校正
    // 二进制头声明 format=1(IBM)，但道内数据实为 IEEE32（小振幅 0..9.9e-3）
    let fake = tmpDir + "segy_fake_ibm.sgy"
    var d = [UInt8](repeating: 0, count: 3600)
    d[3216] = 0x07; d[3217] = 0xD0; d[3220] = 0x00; d[3221] = 0x64  // ns=100
    d[3224] = 0x00; d[3225] = 0x01                                    // 声明 IBM
    for t in 0..<2 {
        var tr = [UInt8](repeating: 0, count: 240 + 100 * 4)
        tr[114] = 0x00; tr[115] = 0x64
        for s in 0..<100 {
            let amp: Float = (s == 0) ? 0 : Float(s) * 1e-4               // 小振幅，IBM 误读为 <1e-6
            let v = amp.bitPattern.bigEndian
            withUnsafeBytes(of: v) { for (i, b) in $0.enumerated() { tr[240 + s*4 + i] = b } }
        }
        d += tr
    }
    try! Data(d).write(to: URL(fileURLWithPath: fake))
    let ff = try! SegyFile.open(url: URL(fileURLWithPath: fake))
    h.check(ff.formatWasCorrected, "fake IBM detected")
    h.check(ff.geometry.format == .ieee32, "fake IBM corrected to ieee32")
    let fdata = TraceReader(file: ff, maxThreads: 1).readDecoded(traceRange: 0..<1, sampleRange: 0..<3)
    h.checkClose(fdata[0], 0, 1e-6, "fake corrected value0")
    h.checkClose(fdata[1], 1e-4, 1e-6, "fake corrected value1")

    h.finish()
}
runAll()
