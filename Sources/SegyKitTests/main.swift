import Foundation
import SegyKit
import Localization

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

    // 新增配色（对照 utils.py seismic(iop)）：端点颜色约定
    let (rwbMinR, rwbMinG, rwbMinB) = Rasterizer.color(for: .redWhiteBlue, t: 0)
    h.check(rwbMinR == 255 && rwbMinG == 0 && rwbMinB == 0, "红白蓝 min 端纯红")
    let (rwbMaxR, rwbMaxG, rwbMaxB) = Rasterizer.color(for: .redWhiteBlue, t: 1)
    h.check(rwbMaxR == 0 && rwbMaxG == 0 && rwbMaxB == 255, "红白蓝 max 端纯蓝")
    let (rbwMinR, rbwMinG, rbwMinB) = Rasterizer.color(for: .redWhiteBlack, t: 0)
    h.check(rbwMinR == 255 && rbwMinG == 0 && rbwMinB == 0, "红白黑 min 端纯红")
    let (rbwMaxR, rbwMaxG, rbwMaxB) = Rasterizer.color(for: .redWhiteBlack, t: 1)
    h.check(rbwMaxR == 0 && rbwMaxG == 0 && rbwMaxB == 0, "红白黑 max 端纯黑")
    let (bwMinR, bwMinG, bwMinB) = Rasterizer.color(for: .brownWhiteBlack, t: 0)
    h.check(bwMinR > bwMinG && bwMinG > bwMinB, "棕白黑 min 端为棕")
    let (grayR, grayG, grayB) = Rasterizer.color(for: .grayscale, t: 0.5)
    h.check(grayR == 127 && grayG == 127 && grayB == 127, "灰度中点 127")

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
    // 需将 SEGY_BIG_FILE 指向 ns=4000 / nTraces=589248 的测试文件；未设置则跳过本组。
    // 期望值由 segyio 生成，vals = [t0s0..t0s9, t1s0..t1s9, t2s0..t2s9]
    if let bigPath = ProcessInfo.processInfo.environment["SEGY_BIG_FILE"] {
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
    } else {
        print("skip: SEGY_BIG_FILE 未设置，跳过真实文件黄金测试与性能回归")
    }

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

    // Viewport.resetView：只重置位置与缩放，显示参数（增益/调色板）必须保留
    var rv = Viewport()
    rv.firstTrace = 5000
    rv.traceSpan = 300
    rv.firstSample = 120
    rv.sampleSpan = 400
    rv.gain = .agc(100)
    rv.palette = .redWhiteBlue
    rv.resetView()
    h.check(rv.firstTrace == 0, "resetView firstTrace 归零")
    h.check(rv.traceSpan == Viewport().traceSpan, "resetView traceSpan 回默认")
    h.check(rv.firstSample == 0, "resetView firstSample 归零")
    h.check(rv.sampleSpan == 0, "resetView sampleSpan 回全采样")
    h.check(rv.gain == .agc(100), "resetView 保留增益")
    h.check(rv.palette == .redWhiteBlue, "resetView 保留调色板")

    // Viewport.panSamples：纵向平移（此前未实现，垂直滚动条依赖它）
    var pv = Viewport()
    pv.sampleSpan = 200
    pv.firstSample = 100
    pv.panSamples(dSamples: 50, ns: 1000)
    h.check(pv.firstSample == 150, "panSamples 正常下移")
    pv.panSamples(dSamples: -500, ns: 1000)
    h.check(pv.firstSample == 0, "panSamples 上边界钳到 0")
    pv.panSamples(dSamples: 99999, ns: 1000)
    h.check(pv.firstSample == 800, "panSamples 下边界钳到 ns-sampleSpan")

    // sampleSpan == 0 表示全采样铺满，纵向没有可滚余量，平移必须无效
    var fullv = Viewport()
    fullv.sampleSpan = 0
    fullv.panSamples(dSamples: 300, ns: 1000)
    h.check(fullv.firstSample == 0, "全采样时 panSamples 不动")

    // zoom 缩小放大倍数后，原本合法的 firstSample 会越界，必须被 clamp 回来。
    // 旧代码只在渲染时临时夹住、存的仍是脏值，滚动条滑块位置会因此算错。
    var zv = Viewport()
    zv.sampleSpan = 200
    zv.firstSample = 800              // 合法上限：1000 − 200
    zv.zoom(timeFactor: 2.0, ns: 1000)
    h.check(zv.sampleSpan == 400, "zoom 放大 sampleSpan")
    h.check(zv.firstSample == 600, "zoom 后 firstSample 被钳回 ns-sampleSpan")

    // 百分比对称裁剪换算：保留 P% → lo=(1−P)/2, hi=1−(1−P)/2
    let b98 = Viewport.percentileBounds(clipPercent: 98)
    h.checkClose(b98.0, 0.01, 1e-6, "98% → lo")
    h.checkClose(b98.1, 0.99, 1e-6, "98% → hi")
    let b99 = Viewport.percentileBounds(clipPercent: 99)
    h.checkClose(b99.0, 0.005, 1e-6, "99% → lo")
    h.checkClose(b99.1, 0.995, 1e-6, "99% → hi")
    let b985 = Viewport.percentileBounds(clipPercent: 98.5)
    h.checkClose(b985.0, 0.0075, 1e-6, "98.5% → lo")
    h.checkClose(b985.1, 0.9925, 1e-6, "98.5% → hi")
    h.checkClose(Viewport.percentileBounds(clipPercent: 100).0, 0, 1e-6, "100% 不裁剪")
    h.checkClose(Viewport.percentileBounds(clipPercent: 90).0, 0.05, 1e-6, "90% → lo")
    // 越界钳制到 [90, 100]
    h.checkClose(Viewport.percentileBounds(clipPercent: 500).1, 1.0, 1e-6, "超上限钳到 100%")
    h.checkClose(Viewport.percentileBounds(clipPercent: 10).0, 0.05, 1e-6, "超下限钳到 90%")

    // 默认视口：归一化方式为 maxAbs；clipPercent 仍记住 98，供切回百分位时重建载荷。
    let dv = Viewport()
    h.checkClose(dv.clipPercent, 98, 1e-9, "默认 clipPercent 98")
    h.check(dv.gain == .maxAbs, "默认 gain 为 maxAbs")
    // 切回百分位时仍用记住的 98% 重建（证明 clipPercent 没被 maxAbs 默认破坏）
    var dvc = Viewport()
    dvc.setGainKind(.percentiles)
    h.check(dvc.gain == .percentiles(0.01, 0.99), "切回百分位用记住的 98%")

    // setClipPercent：gain 是百分位时同步重算载荷，真值只有 clipPercent 一个，不会漂移
    var cv = Viewport()
    cv.setGainKind(.percentiles)   // 默认已是 maxAbs，先切回百分位以测试 setClipPercent 的载荷同步
    cv.setClipPercent(99)
    h.checkClose(cv.clipPercent, 99, 1e-9, "setClipPercent 存值")
    h.check(cv.gain == .percentiles(0.005, 0.995), "setClipPercent 同步 gain 载荷")
    cv.setClipPercent(1000)
    h.checkClose(cv.clipPercent, 100, 1e-9, "setClipPercent 越界钳制")

    // gain 不是百分位时，改百分比只存值、不得把增益方式偷偷改回百分位
    var av = Viewport()
    av.gain = .agc(100)
    av.setClipPercent(99)
    h.check(av.gain == .agc(100), "非百分位时 setClipPercent 不改增益方式")
    h.checkClose(av.clipPercent, 99, 1e-9, "非百分位时仍记住百分比")
    // 切回百分位时，用记住的百分比重建载荷
    av.setGainKind(.percentiles)
    h.check(av.gain == .percentiles(0.005, 0.995), "切回百分位用记住的 99%")

    // GainMode.kind 投影：载荷不同但种类相同，Picker 才不会因载荷变化而匹配不上 tag
    h.check(GainMode.percentiles(0.01, 0.99).kind == .percentiles, "kind 百分位")
    h.check(GainMode.percentiles(0.005, 0.995).kind == .percentiles, "kind 百分位（载荷不同）")
    h.check(GainMode.agc(100).kind == .agc, "kind AGC")
    h.check(GainMode.agc(50).kind == .agc, "kind AGC（载荷不同）")
    h.check(GainMode.perTrace.kind == .perTrace, "kind 每道")
    h.check(GainMode.maxAbs.kind == .maxAbs, "kind 最大幅值")

    // resetView 也必须保留百分比
    var rp = Viewport()
    rp.setGainKind(.percentiles)   // 默认已是 maxAbs，先切回百分位
    rp.setClipPercent(99)
    rp.firstTrace = 900
    rp.resetView()
    h.checkClose(rp.clipPercent, 99, 1e-9, "resetView 保留百分比")
    h.check(rp.gain == .percentiles(0.005, 0.995), "resetView 保留百分位载荷")

    // ScrollMetrics：滚动条滑块几何（纯计算，与 SwiftUI 无关，因此可测）
    // 跨度占一半 → 滑块占轨道一半，位于最左
    let m0 = ScrollMetrics(track: 200, total: 1000, span: 500, first: 0)
    h.check(m0.enabled, "半跨度滚动条可用")
    h.checkClose(m0.knobLength, 100, 1e-9, "滑块长 = 轨道 × span/total")
    h.checkClose(m0.knobOffset, 0, 1e-9, "first=0 滑块贴起点")

    // first 到最大 → 滑块贴末端
    let mEnd = ScrollMetrics(track: 200, total: 1000, span: 500, first: 500)
    h.checkClose(mEnd.knobOffset, 100, 1e-9, "first 到底滑块贴末端")

    // 中间位置按比例
    let mMid = ScrollMetrics(track: 200, total: 1000, span: 500, first: 250)
    h.checkClose(mMid.knobOffset, 50, 1e-9, "滑块偏移按 first/(total−span) 比例")

    // 超大文件：589k 道里看 1200 道，按比例滑块不足 1px，必须有最小长度
    let mBig = ScrollMetrics(track: 200, total: 589_000, span: 1200, minKnob: 24)
    h.checkClose(mBig.knobLength, 24, 1e-9, "极小比例时滑块取最小长度")

    // span >= total（全部可见）→ 禁用，滑块占满轨道
    let mFull = ScrollMetrics(track: 200, total: 1000, span: 1000, first: 0)
    h.check(!mFull.enabled, "全部可见时滚动条禁用")
    h.checkClose(mFull.knobLength, 200, 1e-9, "禁用时滑块占满轨道")

    // span == 0 表示全采样铺满 → 同样禁用（垂直条默认就是这个状态）
    h.check(!ScrollMetrics(track: 200, total: 1000, span: 0).enabled, "span=0 时禁用")
    // 轨道宽度非法时不得除零
    h.check(!ScrollMetrics(track: 0, total: 1000, span: 100).enabled, "轨道为 0 时禁用")

    // 反算：像素偏移 → 索引，且与正算互为逆
    h.check(mMid.index(atKnobOffset: 50) == 250, "偏移反算回 first")
    h.check(m0.index(atKnobOffset: 100) == 500, "偏移到底反算为最大 first")
    h.check(m0.index(atKnobOffset: -20) == 0, "负偏移钳到 0")
    h.check(m0.index(atKnobOffset: 9999) == 500, "超界偏移钳到最大 first")
    // 最小滑块长度生效时，拖到底仍要能覆盖到最后一屏
    h.check(mBig.index(atKnobOffset: mBig.maxKnobOffset) == 589_000 - 1200,
            "最小滑块下仍可拖到文件末尾")
    // 禁用时反算恒为 0，避免拖动禁用条改变视口
    h.check(mFull.index(atKnobOffset: 100) == 0, "禁用时反算恒为 0")

    // Viewport.decodePlan：视口 → 实际解码窗口。此前这段钳制逻辑埋在 DocumentModel
    // （可执行 target，测不到），越界视口是否被正确夹住全靠肉眼。
    // 默认视口：traceSpan 夹到文件道数，全采样（sampleRange nil、分箱高 800）
    let p0 = Viewport().decodePlan(nTraces: 500, ns: 1000)
    h.check(p0.traceRange == 0..<500, "默认视口 traceSpan 夹到文件道数")
    h.check(p0.sampleRange == nil, "全采样时 sampleRange 为 nil")
    h.check(p0.binHeight == 800, "全采样分箱高 800")
    h.check(p0.decodedNs == 1000, "全采样 decodedNs = ns")

    // traceSpan 上限 1200：绝不因视口设得大就整文件解码
    var wide = Viewport()
    wide.traceSpan = 1200
    h.check(wide.decodePlan(nTraces: 589_000, ns: 1000).traceRange == 0..<1200,
            "大文件仍只解码一屏")

    // firstTrace 越界要夹回最后一屏，而不是读到文件外
    var over = Viewport()
    over.traceSpan = 200
    over.firstTrace = 999_999
    h.check(over.decodePlan(nTraces: 500, ns: 1000).traceRange == 300..<500,
            "firstTrace 越界夹回最后一屏")

    // 纵向缩放：只解码该采样窗，并按窗高分箱
    var vz = Viewport()
    vz.sampleSpan = 200
    vz.firstSample = 100
    let pz = vz.decodePlan(nTraces: 500, ns: 1000)
    h.check(pz.sampleRange == 100..<300, "纵向缩放只解码采样窗")
    h.check(pz.binHeight == 200, "分箱高 = 采样窗高")
    h.check(pz.decodedNs == 200, "decodedNs = 采样窗高")

    // sampleSpan 超过 ns 要夹住，且此时 firstSample 只能是 0
    var vbig = Viewport()
    vbig.sampleSpan = 99_999
    vbig.firstSample = 500
    let pbig = vbig.decodePlan(nTraces: 500, ns: 1000)
    h.check(pbig.sampleRange == 0..<1000, "sampleSpan 超过 ns 夹到全采样窗")

    // firstSample 越界夹回最后一窗
    var vfs = Viewport()
    vfs.sampleSpan = 200
    vfs.firstSample = 99_999
    h.check(vfs.decodePlan(nTraces: 500, ns: 1000).sampleRange == 800..<1000,
            "firstSample 越界夹回最后一窗")

    // 端到端：合成文件 → 视口 → 最终像素。走的是 DocumentModel.binned/render 的同一条链
    // （decodePlan → readDecoded → minMax → Gain.apply → makeImage），
    // 用来证明「三个功能真的改变/复原了画面」，而不只是改了状态字段。
    let e2ePath = tmpDir + "segy_e2e.sgy"
    let eNS = 400, eNT = 600
    var ed = [UInt8](repeating: 0, count: 3600)
    ed[3216] = 0x07; ed[3217] = 0xD0                 // dt = 2000
    ed[3220] = UInt8(eNS >> 8); ed[3221] = UInt8(eNS & 0xFF)
    ed[3224] = 0x00; ed[3225] = 0x05                 // format 5 = IEEE32
    for t in 0..<eNT {
        var tr = [UInt8](repeating: 0, count: 240 + eNS * 4)
        tr[114] = UInt8(eNS >> 8); tr[115] = UInt8(eNS & 0xFF)
        for s in 0..<eNS {
            // 倾斜同相轴：振幅同时依赖道号与采样号，保证横向/纵向任一方向移动画面都会变
            let amp = Float(sin(Double(s) * 0.11 + Double(t) * 0.03)) * Float(1 + t % 7)
            let v = amp.bitPattern.bigEndian
            withUnsafeBytes(of: v) { for (i, b) in $0.enumerated() { tr[240 + s*4 + i] = b } }
        }
        ed += tr
    }
    try! Data(ed).write(to: URL(fileURLWithPath: e2ePath))
    let e2eFileA = try! SegyFile.open(url: URL(fileURLWithPath: e2ePath))
    h.check(e2eFileA.geometry.nTraces == eNT && e2eFileA.geometry.ns == eNS, "e2e 合成文件几何正确")

    /// 复刻 DocumentModel 的渲染链，返回 RGBA 字节，供逐字节比较。
    func pixels(_ f: SegyFile, _ v: Viewport) -> [UInt8] {
        let plan = v.decodePlan(nTraces: f.geometry.nTraces, ns: f.geometry.ns)
        let data = TraceReader(file: f, maxThreads: 4)
            .readDecoded(traceRange: plan.traceRange, sampleRange: plan.sampleRange)
        let b = Decimator.minMax(data, ns: plan.decodedNs,
                                 nTraces: plan.traceRange.count, h: plan.binHeight)
        let img = Rasterizer.makeImage(Gain.apply(b, v.gain), palette: v.palette)
        return [UInt8](img.dataProvider!.data! as Data)
    }

    var base = Viewport()
    base.traceSpan = 200
    let basePx = pixels(e2eFileA, base)
    h.check(!basePx.isEmpty, "e2e 基准图像非空")
    // 对照：相同视口必须产出逐字节相同的像素。否则下面所有「画面改变」断言都不足为证。
    h.check(pixels(e2eFileA, base) == basePx, "相同视口产出相同像素（对照）")

    // 水平滚动条：改 firstTrace 必须真的换画面
    var moved = base
    moved.firstTrace = 300
    h.check(pixels(e2eFileA, moved) != basePx, "改 firstTrace 画面改变（水平滚动有效）")

    // 垂直滚动条：纵向缩放后改 firstSample 必须真的换画面
    var zoomed = base
    zoomed.sampleSpan = 100
    let zoomedPx = pixels(e2eFileA, zoomed)
    var scrolled = zoomed
    scrolled.firstSample = 200
    h.check(pixels(e2eFileA, scrolled) != zoomedPx, "改 firstSample 画面改变（垂直滚动有效）")

    // 百分比滑块：不同裁剪比例必须真的换画面
    var clipped = base
    clipped.setGainKind(.percentiles)   // 默认已是 maxAbs，先切回百分位
    clipped.setClipPercent(90)
    h.check(pixels(e2eFileA, clipped) != basePx, "改 clipPercent 画面改变（百分比滑块有效）")

    // 重置视图：位置/缩放全部动过之后，resetView 必须逐字节回到初始画面
    var dirty = Viewport()
    dirty.traceSpan = 200
    dirty.firstTrace = 350
    dirty.sampleSpan = 120
    dirty.firstSample = 210
    _ = pixels(e2eFileA, dirty)
    dirty.resetView()
    dirty.traceSpan = 200          // 基准视口本身用的就是 200，对齐后比较
    h.check(pixels(e2eFileA, dirty) == basePx, "resetView 后逐字节回到初始画面")

    // 重置不得动显示参数：改过百分比再重置，画面应与「只改百分比」一致
    var dirty2 = clipped
    dirty2.firstTrace = 400
    dirty2.sampleSpan = 90
    dirty2.resetView()
    dirty2.traceSpan = 200
    h.check(pixels(e2eFileA, dirty2) == pixels(e2eFileA, clipped), "resetView 保留百分比裁剪效果")

    // 对比模型：同一 viewport 渲染两个几何不同的文件，产出各自非空且互异的图像
    let e2ePath2 = tmpDir + "segy_e2e_2.sgy"
    let eNS2 = 250, eNT2 = 300
    var ed2 = [UInt8](repeating: 0, count: 3600)
    ed2[3216] = 0x07; ed2[3217] = 0xD0
    ed2[3220] = UInt8(eNS2 >> 8); ed2[3221] = UInt8(eNS2 & 0xFF)
    ed2[3224] = 0x00; ed2[3225] = 0x05
    for t in 0..<eNT2 {
        var tr = [UInt8](repeating: 0, count: 240 + eNS2 * 4)
        tr[114] = UInt8(eNS2 >> 8); tr[115] = UInt8(eNS2 & 0xFF)
        for s in 0..<eNS2 {
            let amp = Float(cos(Double(s) * 0.09 + Double(t) * 0.05)) * Float(3 + t % 5)
            let v = amp.bitPattern.bigEndian
            withUnsafeBytes(of: v) { for (i, b) in $0.enumerated() { tr[240 + s*4 + i] = b } }
        }
        ed2 += tr
    }
    try! Data(ed2).write(to: URL(fileURLWithPath: e2ePath2))
    let e2eFileB = try! SegyFile.open(url: URL(fileURLWithPath: e2ePath2))
    var shared = Viewport()
    shared.traceSpan = 150
    let imgA = pixels(e2eFileA, shared), imgB = pixels(e2eFileB, shared)
    h.check(!imgA.isEmpty && !imgB.isEmpty, "对比：两文件在共享视口下各自渲染非空")
    h.check(imgA != imgB, "对比：不同文件产出不同图像")
    shared.firstTrace = 999
    shared.resetView()
    h.check(shared.firstTrace == 0 && shared.traceSpan == Viewport().traceSpan, "对齐按钮语义：共享视口归默认")

    // 缩放映射：zoom=0 全展、zoom=1 放大到最小，中间线性
    h.check(Viewport.zoomSpan(zoom: 0, minSpan: 1, maxSpan: 1200) == 1200, "zoomSpan 0 → maxSpan")
    h.check(Viewport.zoomSpan(zoom: 1, minSpan: 1, maxSpan: 1200) == 1, "zoomSpan 1 → minSpan")
    h.check(Viewport.zoomSpan(zoom: 0.5, minSpan: 1, maxSpan: 1200) == 600, "zoomSpan 0.5 线性中点")
    h.check(Viewport.zoomSpan(zoom: -1, minSpan: 1, maxSpan: 100) == 100, "zoomSpan 越界钳到 maxSpan")
    h.check(Viewport.zoomSpan(zoom: 9, minSpan: 1, maxSpan: 100) == 1, "zoomSpan 越界钳到 minSpan")
    // 逆映射：端点往返一致。注意 span 离散，(maxSpan−minSpan)=1199，中点对应 zoom=(1200−600)/1199
    h.checkClose(Viewport.spanZoom(span: 1200, minSpan: 1, maxSpan: 1200), 0, 1e-9, "spanZoom maxSpan → 0")
    h.checkClose(Viewport.spanZoom(span: 1, minSpan: 1, maxSpan: 1200), 1, 1e-9, "spanZoom minSpan → 1")
    h.checkClose(Viewport.spanZoom(span: 600, minSpan: 1, maxSpan: 1200), 600.0 / 1199.0, 1e-9, "spanZoom 中点 → 600/1199")
    // 往返：zoom→span→zoom 应回到同一点
    h.check(Viewport.zoomSpan(zoom: Viewport.spanZoom(span: 600, minSpan: 1, maxSpan: 1200),
                              minSpan: 1, maxSpan: 1200) == 600, "zoomSpan∘spanZoom 往返一致")
    // time 全采样约定：sampleSpan==0 或 ==ns 都是全采样，映射为 0
    h.checkClose(Viewport.timeZoom(span: 0, ns: 1000), 0, 1e-9, "timeZoom 0 → 0（全采样）")
    h.checkClose(Viewport.timeZoom(span: 1000, ns: 1000), 0, 1e-9, "timeZoom ns → 0（全采样）")
    h.checkClose(Viewport.timeZoom(span: 100, ns: 1000), 900.0 / 999.0, 1e-9, "timeZoom 窗口化中点")

    // 中心锚缩放：缩放前后视口中心那道不变（中段）
    var zt = Viewport()
    zt.traceSpan = 200; zt.firstTrace = 400           // 中心道 = 500
    zt.zoomTraces(to: 400, total: 1000)
    h.check(zt.traceSpan == 400, "zoomTraces 更新 span")
    h.check(zt.firstTrace == 300, "zoomTraces 中心道保持（500）")

    // 贴左边界：span 放大后中心无法保持，firstTrace 应夹到 0
    var zl = Viewport()
    zl.traceSpan = 200; zl.firstTrace = 0             // 中心道 = 100
    zl.zoomTraces(to: 600, total: 1000)
    h.check(zl.firstTrace == 0, "zoomTraces 贴左夹到 0")
    h.check(zl.traceSpan == 600, "zoomTraces 贴左 span 仍更新")

    // 贴右边界：夹到 total-span
    var zr = Viewport()
    zr.traceSpan = 200; zr.firstTrace = 800           // 中心道 = 900
    zr.zoomTraces(to: 600, total: 1000)
    h.check(zr.firstTrace == 400, "zoomTraces 贴右夹到 total-span")

    // targetSpan 越界钳制
    var zo = Viewport()
    zo.traceSpan = 100; zo.firstTrace = 100
    zo.zoomTraces(to: 99999, total: 1000)
    h.check(zo.traceSpan == 1000, "zoomTraces target 越界钳到 total")
    zo.zoomTraces(to: 0, total: 1000)
    h.check(zo.traceSpan == 1, "zoomTraces target 过小钳到 1")

    // 采样中心锚：从全采样起步进入窗口化，再缩放保持中心
    var zs = Viewport()
    zs.sampleSpan = 0; zs.firstSample = 0
    zs.zoomSamples(to: 200, ns: 1000)
    h.check(zs.sampleSpan == 200 && zs.firstSample == 400, "zoomSamples 全采样→200 时中心采样点=ns/2=500")
    zs.zoomSamples(to: 400, ns: 1000)
    h.check(zs.firstSample == 300, "zoomSamples 中心采样点保持（500）")
    // 回到全采样
    zs.zoomSamples(to: 0, ns: 1000)
    h.check(zs.sampleSpan == 0 && zs.firstSample == 0, "zoomSamples 回全采样清零")

    // 相对缩放 factor：factor<1 放大（span 变小）、factor>1 缩小（span 变大）、factor==1 不动
    var rf = Viewport()
    rf.traceSpan = 200; rf.firstTrace = 400        // 中心道 = 500
    rf.zoomTraces(factor: 0.5, total: 1000)
    h.check(rf.traceSpan == 100 && rf.firstTrace == 450, "zoomTraces factor=0.5 放大且中心道保持")
    rf.zoomTraces(factor: 2.0, total: 1000)
    h.check(rf.traceSpan == 200 && rf.firstTrace == 400, "zoomTraces factor=2 缩小回原位")
    rf.zoomTraces(factor: 1.0, total: 1000)
    h.check(rf.traceSpan == 200 && rf.firstTrace == 400, "zoomTraces factor=1 不动")

    // 贴边夹住：factor 放大到 span×factor，中心无法保持时贴左
    var rl = Viewport()
    rl.traceSpan = 200; rl.firstTrace = 100        // 中心道 = 200
    rl.zoomTraces(factor: 3.0, total: 1000)
    h.check(rl.traceSpan == 600 && rl.firstTrace == 0, "zoomTraces 放大 200→600 且中心无法保持贴左")

    // traceSpan 绝不越过屏宽上限：大文件里 zoomTraces 放大到 1200 后不再增长，
    // 否则缩放滑块一松手就整文件解码、卡死主线程（回归根因）。
    var rc = Viewport()
    rc.traceSpan = 1200; rc.firstTrace = 0
    rc.zoomTraces(factor: 4.0, total: 589_000)
    h.check(rc.traceSpan == Viewport.maxTraceSpan, "zoomTraces factor 放大到屏宽上限后夹住")
    rc.zoomTraces(to: 999_999, total: 589_000)
    h.check(rc.traceSpan == Viewport.maxTraceSpan, "zoomTraces(to:) 目标越界也夹到屏宽上限")

    // 采样相对缩放：全采样 → 窗口化平滑过渡，中心采样点保持
    var rs = Viewport()
    rs.sampleSpan = 0; rs.firstSample = 0          // 全采样，ns=1000
    rs.zoomSamples(factor: 0.5, ns: 1000)
    h.check(rs.sampleSpan == 500 && rs.firstSample == 250, "zoomSamples 全采样→0.5 中心采样点=500")
    rs.zoomSamples(factor: 0.5, ns: 1000)
    h.check(rs.sampleSpan == 250 && rs.firstSample == 375, "zoomSamples 连续放大中心采样点保持")
    rs.zoomSamples(factor: 2.0, ns: 1000)
    h.check(rs.sampleSpan == 500 && rs.firstSample == 250, "zoomSamples 连续缩小中心采样点保持")
    // 全采样时 factor>1 不能再放大，保持全采样
    var rs2 = Viewport()
    rs2.sampleSpan = 0; rs2.firstSample = 0
    rs2.zoomSamples(factor: 2.0, ns: 1000)
    h.check(rs2.sampleSpan == 0 && rs2.firstSample == 0, "zoomSamples 全采样 factor>1 保持全采样")
    // 窗口化放大到 >= ns 时回到全采样
    var rs3 = Viewport()
    rs3.sampleSpan = 400; rs3.firstSample = 300
    rs3.zoomSamples(factor: 5.0, ns: 1000)
    h.check(rs3.sampleSpan == 0 && rs3.firstSample == 0, "zoomSamples 放大到 ns 回全采样")

    // MARK: - 本地化：语言判定
    h.check(Lang.fromSystem(preferred: ["zh-Hans", "en-US"]) == .zh, "fromSystem zh-Hans → zh")
    h.check(Lang.fromSystem(preferred: ["zh-Hant"]) == .zh, "fromSystem zh-Hant → zh")
    h.check(Lang.fromSystem(preferred: ["en-US"]) == .en, "fromSystem en-US → en")
    h.check(Lang.fromSystem(preferred: ["de-DE"]) == .en, "fromSystem de-DE → en")
    h.check(Lang.fromSystem(preferred: []) == .en, "fromSystem 空列表 → en")
    // 存过的用户选择优先于系统语言
    h.check(Lang.resolve(stored: "en", preferred: ["zh-Hans"]) == .en, "resolve 用户选 en 覆盖系统 zh")
    h.check(Lang.resolve(stored: "zh", preferred: ["en-US"]) == .zh, "resolve 用户选 zh 覆盖系统 en")
    h.check(Lang.resolve(stored: nil, preferred: ["zh-Hans"]) == .zh, "resolve 未存过回落系统 zh")
    h.check(Lang.resolve(stored: "klingon", preferred: ["en-US"]) == .en, "resolve 非法存值回落系统")

    // MARK: - 本地化：两表完整性
    var missingZh = 0, missingEn = 0, emptyCells = 0
    for k in S.allCases {
        if zhTable[k] == nil { missingZh += 1 }
        if enTable[k] == nil { missingEn += 1 }
        if zhTable[k]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? false { emptyCells += 1 }
        if enTable[k]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? false { emptyCells += 1 }
    }
    h.check(missingZh == 0, "每个 key 都有中文文案（缺 \(missingZh) 个）")
    h.check(missingEn == 0, "每个 key 都有英文文案（缺 \(missingEn) 个）")
    h.check(emptyCells == 0, "没有空白文案（\(emptyCells) 处）")
    h.check(Set(zhTable.keys) == Set(S.allCases), "中文表 key 集合 == S.allCases")
    h.check(Set(enTable.keys) == Set(S.allCases), "英文表 key 集合 == S.allCases")

    // 占位符数量必须一致，否则状态栏参数错位
    var badPlaceholders: [String] = []
    for k in S.allCases {
        let z = placeholderCount(zhTable[k] ?? "")
        let e = placeholderCount(enTable[k] ?? "")
        if z != e { badPlaceholders.append("\(k.rawValue)(zh:\(z) en:\(e))") }
    }
    h.check(badPlaceholders.isEmpty, "中英占位符数量一致（不一致：\(badPlaceholders.joined(separator: ", "))）")

    // format 行为
    h.check(format(.statusTraceSpan, .en, ["1200"]) == "traceSpan 1200", "format 单参数替换")
    h.check(format(.statusShotCurrent, .en, ["3", "57"]) == "Shot 3/57", "format 双参数按顺序替换")
    h.check(format(.statusShotCurrent, .en, ["3"]).contains("%@"), "format 参数不足时保留剩余占位符、不崩")
    h.check(format(.statusTraceSpan, .en, ["1200", "多余"]) == "traceSpan 1200", "format 多余参数忽略")
    h.check(string(.tbGain, .zh) == "增益" && string(.tbGain, .en) == "Gain", "string 按语言取值")

    // MARK: - 本地化：错误文案
    let errCases: [SegyError] = [
        .fileTooSmall,
        .invalidFormatCode(9),
        .nonIntegerTraceCount(fileSize: 1000, traceBytes: 300, remainder: 100),
        .badSampleCount(binaryHeader: 4000, traceHeader: 1000),
    ]
    var errOK = true
    for e in errCases {
        for lang in Lang.allCases {
            let msg = userMessage(for: e, lang)
            // 非空、且确实走了映射（不是把 description 原样吐出来）
            if msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errOK = false }
            if msg == String(describing: e) { errOK = false }
            if msg.contains("%@") { errOK = false }   // 占位符必须都填上了
        }
    }
    h.check(errOK, "4 个 SegyError 在中英两语下都产出非空、已填充、非原始 description 的文案")
    h.check(userMessage(for: SegyError.invalidFormatCode(9), .zh).contains("9"),
            "格式码错误文案带上了实际格式码")
    h.check(userMessage(for: SegyError.invalidFormatCode(9), .en).contains("9"),
            "格式码错误文案带上了实际格式码（en）")
    // 非 SegyError 也要有兜底，不能崩
    struct OtherError: Error {}
    h.check(!userMessage(for: OtherError(), .zh).isEmpty, "非 SegyError 有兜底文案")
    // description 已改成中性英文，不再含中文
    h.check(!String(describing: SegyError.fileTooSmall).contains("文件"),
            "SegyError.description 已改为中性英文")

    // MARK: - 本地化：菜单标题反查
    h.check(retitledMenuTitle(current: "视图", to: .en) == "View", "视图 → View")
    h.check(retitledMenuTitle(current: "View", to: .zh) == "视图", "View → 视图")
    h.check(retitledMenuTitle(current: "退出 SeisView", to: .en) == "Quit SeisView", "退出 → Quit")
    h.check(retitledMenuTitle(current: "Quit SeisView", to: .zh) == "退出 SeisView", "Quit → 退出")
    h.check(retitledMenuTitle(current: "上一炮", to: .en) == "Previous Shot", "上一炮 → Previous Shot")
    // 同语言重复调用是幂等的（切两次同一语言不应错乱）
    h.check(retitledMenuTitle(current: "View", to: .en) == "View", "同语言反查幂等")
    // 认不出的标题必须返回 nil，绝不能瞎改系统菜单里我们不认识的项
    h.check(retitledMenuTitle(current: "Some Third-Party Item", to: .zh) == nil, "未知标题不动")
    h.check(retitledMenuTitle(current: "", to: .zh) == nil, "空标题不动")
    // 反查子集内部两语文案不得重复，否则反查会撞车
    var zhTitles: [String] = [], enTitles: [String] = []
    for k in menuTitleKeys {
        zhTitles.append(string(k, .zh)); enTitles.append(string(k, .en))
    }
    h.check(Set(zhTitles).count == zhTitles.count, "菜单中文标题无重复（反查不撞车）")
    h.check(Set(enTitles).count == enTitles.count, "菜单英文标题无重复（反查不撞车）")
    // 跨语言也不得撞车：menuKey 同时比对两张表（zhTable[k] == title || enTable[k] == title），
    // 若 zh 的某值恰好等于 en 的某值，同一标题会命中两个 key、返回结果不确定
    let crossDup = Set(zhTitles).intersection(Set(enTitles)).sorted()
    h.check(crossDup.isEmpty, "菜单跨语言文案无重叠（撞车：\(crossDup.joined(separator: ", "))）")

    // MARK: - 本地化：Help 结构对齐
    let zhHelp = helpSections(.zh), enHelp = helpSections(.en)
    h.check(zhHelp.count == 9, "Help 共 9 章（中文实际 \(zhHelp.count)）")
    h.check(zhHelp.count == enHelp.count, "Help 中英章节数一致")
    var helpStructOK = true, helpTitlesOK = true, helpBlocksNonEmpty = true
    for (z, e) in zip(zhHelp, enHelp) {
        if z.blocks.count != e.blocks.count { helpStructOK = false }
        if z.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || e.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { helpTitlesOK = false }
        for (zb, eb) in zip(z.blocks, e.blocks) {
            switch (zb, eb) {
            case (.paragraph(let a), .paragraph(let b)):
                if a.isEmpty || b.isEmpty { helpBlocksNonEmpty = false }
            case (.bullets(let a), .bullets(let b)):
                if a.count != b.count || a.isEmpty { helpStructOK = false }
            case (.keyTable(let a), .keyTable(let b)):
                if a.count != b.count || a.isEmpty { helpStructOK = false }
            default:
                helpStructOK = false   // 同位置 block 类型必须相同
            }
        }
    }
    h.check(helpStructOK, "Help 中英每章 block 数、类型、列表长度逐一对齐")
    h.check(helpTitlesOK, "Help 每章标题两语都非空")
    h.check(helpBlocksNonEmpty, "Help 段落两语都非空")
    // 快捷键表两语的按键写法必须完全相同（⌘O 不该被翻译）
    var keysIdentical = true
    for (z, e) in zip(zhHelp, enHelp) {
        for (zb, eb) in zip(z.blocks, e.blocks) {
            if case .keyTable(let a) = zb, case .keyTable(let b) = eb {
                if a.map(\.keys) != b.map(\.keys) { keysIdentical = false }
                if a.contains(where: { $0.desc.isEmpty }) { keysIdentical = false }
                if b.contains(where: { $0.desc.isEmpty }) { keysIdentical = false }
            }
        }
    }
    h.check(keysIdentical, "快捷键表两语按键写法相同、说明都非空")

    // MARK: - 按偏移距排列

    do {
        // 局部作用域：外层 runAll 已声明过 shots / src 同名局部变量，这里包一层避免重声明。
        /// 假道头源：按 trace 序号返回预先设定的 offset，供 OffsetIndexBuilder 测试。
        final class FakeHeaderSource: TraceHeaderSource {
            let offsets: [Int]
            init(_ o: [Int]) { self.offsets = o }
            func readTraceHeaders(range: Range<Int>) -> [TraceHeader] {
                range.map { i in
                    TraceHeader(ffid: 0, traceSeq: i, cdp: 0,
                                offset: offsets[i], ns: 0, dtMicros: 0)
                }
            }
        }

        // 两炮：炮1 = 道 0..<3（offset 300,100,100），炮2 = 道 3..<6（offset -50, 10, -50）
        // 炮1 内 offset 升序（并列按道号稳定）→ 道号顺序 [1,2,0]
        // 炮2 内 offset 升序 → 道号顺序 [3,5,4]（道3 的 offset -50 属炮2）
        // 注意：下面构造 shots 时 firstTrace/count 必须与 offsets 长度一致。
        let shots = [Shot(ffid: 1, firstTrace: 0, count: 3),
                     Shot(ffid: 2, firstTrace: 3, count: 3)]
        let src = FakeHeaderSource([300, 100, 100, -50, 10, -50])
        let idx = OffsetIndexBuilder.build(shots: shots, source: src)
        h.check(idx.permSigned == [1, 2, 0, 3, 5, 4], "有符号：炮内 offset 升序 + 并列按道号稳定")
        h.check(idx.permAbs == [1, 2, 0, 4, 3, 5], "绝对值：炮内 |offset| 升序 + 并列负在前")
        h.check(idx.shotStarts == [0, 3, 6], "每炮起始位置")

        h.check(OffsetIndexLookup.traceAt(idx, position: 0, order: .byOffset) == 1, "traceAt 首（有符号）")
        h.check(OffsetIndexLookup.traceAt(idx, position: 3, order: .byOffsetAbs) == 4, "traceAt（绝对值）")
        h.check(OffsetIndexLookup.traceAt(idx, position: 5, order: .byOffset) == 4, "traceAt 末（有符号）")
        h.check(OffsetIndexLookup.traceAt(idx, position: -1, order: .byOffset) == nil, "traceAt 越界下")
        h.check(OffsetIndexLookup.traceAt(idx, position: 6, order: .byOffset) == nil, "traceAt 越界上")

        h.check(OffsetIndexLookup.traces(idx, positions: 0..<3, order: .byOffset) == [1, 2, 0], "traces 区间（有符号）")
        h.check(OffsetIndexLookup.traces(idx, positions: 3..<6, order: .byOffsetAbs) == [4, 3, 5], "traces 区间（绝对值）")
        h.check(OffsetIndexLookup.traces(idx, positions: 0..<0, order: .byOffset).isEmpty, "traces 空区间")

        h.check(OffsetIndexLookup.positionRange(idx, shotIndex: 0) == 0..<3, "positionRange 炮1")
        h.check(OffsetIndexLookup.positionRange(idx, shotIndex: 1) == 3..<6, "positionRange 炮2")
        h.check(OffsetIndexLookup.positionRange(idx, shotIndex: 2) == nil, "positionRange 越界")
    }

    // 负 offset 的有符号解析：SEG-Y offset（道头字节 37–40）是有符号 int32，
    // 炮点一侧为负。若按无符号 u32 读，-2000 会变成 42 亿量级，排序时排到炮内最后。
    do {
        var tr = [UInt8](repeating: 0, count: 240)
        tr[36] = 0xFF; tr[37] = 0xFF; tr[38] = 0xF8; tr[39] = 0x30   // int32 -2000 大端
        tr.withUnsafeBytes { rb in
            let th = SegyFile.parseTraceHeader(rb.baseAddress!, order: .big)
            h.check(th.offset == -2000, "offset 有符号解析：读出 -2000 而非无符号巨大值")
        }
    }

    h.finish()
}
runAll()
