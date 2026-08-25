import Foundation

public enum SegyError: Error, CustomStringConvertible {
    case fileTooSmall
    case invalidFormatCode(Int)
    case nonIntegerTraceCount(fileSize: UInt64, traceBytes: Int, remainder: UInt64)
    case badSampleCount(binaryHeader: Int, traceHeader: Int)
    /// 开发者向的技术描述（日志 / 调试用）。用户可见文案在 Localization.userMessage，
    /// 这里刻意保持语言中性，不参与界面本地化。
    public var description: String {
        switch self {
        case .fileTooSmall:
            return "file is smaller than 3600 bytes; not a valid SEG-Y"
        case .invalidFormatCode(let c):
            return "unsupported sample format code \(c)"
        case .nonIntegerTraceCount(let s, let t, let r):
            return "trace length mismatch: file \(s) bytes / trace \(t) bytes, remainder \(r) — variable-length traces suspected"
        case .badSampleCount(let b, let t):
            return "sample count mismatch: binary header \(b) vs trace header \(t)"
        }
    }
}

public final class SegyFile {
    public let url: URL
    public let geometry: Geometry
    public let binaryHeader: BinaryHeader
    public let fileSize: UInt64
    public let formatWasCorrected: Bool
    public init(url: URL, geometry: Geometry, binaryHeader: BinaryHeader, fileSize: UInt64, formatWasCorrected: Bool) {
        self.url = url; self.geometry = geometry; self.binaryHeader = binaryHeader; self.fileSize = fileSize
        self.formatWasCorrected = formatWasCorrected
    }

    public static func parseBinaryHeader(_ raw: [UInt8]) -> BinaryHeader {
        let dt = Int(UInt16(raw[16]) << 8 | UInt16(raw[17]))
        let ns = Int(UInt16(raw[20]) << 8 | UInt16(raw[21]))
        // 注意：格式码用 UInt16 读入，保留高字节（rev2 小端标志位于 0x8000 位）
        let fmt = Int(UInt16(raw[24]) << 8 | UInt16(raw[25]))
        let rev = Int(UInt16(raw[300]) << 8 | UInt16(raw[301]))
        let fixed = Int(UInt16(raw[302]) << 8 | UInt16(raw[303]))
        let ext = Int(UInt16(raw[304]) << 8 | UInt16(raw[305]))
        return BinaryHeader(ns: ns, dtMicros: dt, formatCode: fmt,
                            segyRevision: rev, fixedLengthFlag: fixed, extTextHeaders: ext)
    }

    public static func parseTraceHeader(_ p: UnsafeRawPointer, order: ByteOrder) -> TraceHeader {
        let ffid = Int(ByteOrderReader.u32(p + 8, order))
        let seq = Int(ByteOrderReader.u32(p + 0, order))
        let cdp = Int(ByteOrderReader.u32(p + 20, order))
        let off = Int(ByteOrderReader.u32(p + 36, order))
        let ns = Int(ByteOrderReader.u16(p + 114, order))
        let dt = Int(ByteOrderReader.u16(p + 116, order))
        return TraceHeader(ffid: ffid, traceSeq: seq, cdp: cdp, offset: off, ns: ns, dtMicros: dt)
    }

    public static func open(url: URL) throws -> SegyFile {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        // NSNumber bridging: read the true file size; a wrong (0/nil) size would
        // wrongly report a too-small file for any real SEG-Y.
        let size = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
        guard size >= 3600 else { throw SegyError.fileTooSmall }
        let fd = Darwin.open(url.path, O_RDONLY)
        defer { close(fd) }
        var bin = [UInt8](repeating: 0, count: 400)
        _ = bin.withUnsafeMutableBytes { pread(fd, $0.baseAddress, 400, 3200) }
        let bh = parseBinaryHeader(bin)

        // 格式码校验 + 小端回退
        var order: ByteOrder = .big
        var format: SampleFormat
        guard let resolvedFormat = sampleFormat(for: bh.formatCode, order: &order) else {
            throw SegyError.invalidFormatCode(bh.formatCode)
        }
        format = resolvedFormat

        let extOffset = UInt64(3600 + bh.extTextHeaders * 3200)
        // 畸形头可能声称大量扩展文本头，extOffset 超过实际文件大小；
        // 不拦截则下方 size - extOffset 会在 UInt64 下回绕成巨大值
        guard size >= extOffset else { throw SegyError.fileTooSmall }
        // 读第一道道头交叉校验 ns
        var thRaw = [UInt8](repeating: 0, count: 240)
        _ = thRaw.withUnsafeMutableBytes { pread(fd, $0.baseAddress, 240, off_t(extOffset)) }
        let th = parseTraceHeader(thRaw, order: order)

        var ns = bh.ns
        if ns <= 0 { ns = th.ns }                       // 二进制头 ns 非法则回退道头
        else if th.ns > 0 && th.ns != ns {
            // 二进制头与道头不一致时，以与文件大小吻合的那个 ns 为准；
            // 都吻合（或都不吻合）时以二进制头为准（SEG-Y rev1 权威字段）。
            // 真实文件的道头 ns 可能不可靠：曾见道头=1985 而二进制头=4000，
            // 只有 4000 与文件大小整除吻合，segyio 亦报 4000。
            let bytes = format.bytesPerSample
            func consistent(_ v: Int) -> Bool {
                let tb = UInt64(240 + v * bytes)
                return tb > 0 && (size - extOffset) % tb == 0
            }
            if !consistent(ns) && consistent(th.ns) { ns = th.ns }
        }
        guard ns > 0 else { throw SegyError.badSampleCount(binaryHeader: bh.ns, traceHeader: th.ns) }

        // 假 IBM 真 IEEE 自动校正：声明 IBM 但首道数据按 IEEE 解码明显更合理时，改为 IEEE
        var corrected = false
        if format == .ibm32 {
            let probe = readFirstSamples(fd, firstOffset: extOffset, count: min(256, ns), declared: .ibm32)
            let asIBM = sanityScore(probe.ibm)
            let asIEEE = sanityScore(probe.ieee)
            if asIEEE > asIBM * 3 { format = .ieee32; corrected = true }  // IEEE 明显更合理
        }

        let traceBytes = 240 + ns * format.bytesPerSample
        let dataBytes = size - extOffset
        guard dataBytes % UInt64(traceBytes) == 0 else {
            throw SegyError.nonIntegerTraceCount(fileSize: size, traceBytes: traceBytes, remainder: dataBytes % UInt64(traceBytes))
        }
        let nTraces = Int(dataBytes / UInt64(traceBytes))

        let geo = Geometry(ns: ns, dtMicros: bh.dtMicros, format: format, byteOrder: order,
                           firstTraceOffset: extOffset, traceBytes: traceBytes, nTraces: nTraces)
        return SegyFile(url: url, geometry: geo, binaryHeader: bh, fileSize: size, formatWasCorrected: corrected)
    }

    private static func readFirstSamples(_ fd: Int32, firstOffset: UInt64, count: Int,
                                         declared: SampleFormat) -> (ibm: [Float], ieee: [Float]) {
        var raw = [UInt8](repeating: 0, count: count * 4)
        let byteCount = raw.count
        _ = raw.withUnsafeMutableBytes { pread(fd, $0.baseAddress, byteCount, off_t(firstOffset) + 240) }
        var ibm = [Float](repeating: 0, count: count)
        var ieee = [Float](repeating: 0, count: count)
        raw.withUnsafeBytes { rb in
            Decoder.decode(bytes: rb.baseAddress!, count: count, format: .ibm32, order: .big, into: &ibm)
            Decoder.decode(bytes: rb.baseAddress!, count: count, format: .ieee32, order: .big, into: &ieee)
        }
        return (ibm, ieee)
    }

    private static func sanityScore(_ v: [Float]) -> Double {
        // 合理样本占比：有限且绝对振幅落在 [1e-6, 1e6] 内的比例
        var ok = 0
        for x in v where x.isFinite && abs(x) >= 1e-6 && abs(x) <= 1e6 { ok += 1 }
        return Double(ok) / Double(max(1, v.count))
    }

    public static func sampleFormat(for code: Int, order: inout ByteOrder) -> SampleFormat? {
        // 格式码按有符号 16 位读入；SEG-Y rev2 的格式码高字节可带 0x80 表示小端
        let c = code & 0xFFFF
        if c & 0x8000 != 0 { order = .little }
        switch c & 0xFF {
        case 1: return .ibm32; case 2: return .int32; case 3: return .int16
        case 5: return .ieee32; case 8: return .int8
        default: return nil
        }
    }
}
