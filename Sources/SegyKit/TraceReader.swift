import Foundation

/// 并行道读取器：每个 worker 持有独立 fd，用 pread 按偏移读取互不重叠的道区间。
/// Swift 6 严格并发下，@Sendable 闭包不能捕获非 Sendable 的 `file`/`self`（含 inout 参数），
/// 因此把需要的原始值先拷成局部 Sendable 常量再进入闭包；输出缓冲指针经 `@unchecked Sendable`
/// 包装传递（各线程只写互不重叠的道区间，构造上安全）。
public final class TraceReader {
    private let file: SegyFile
    private let maxThreads: Int
    public init(file: SegyFile, maxThreads: Int = min(8, ProcessInfo.processInfo.activeProcessorCount)) {
        self.file = file; self.maxThreads = max(1, maxThreads)
    }

    public func readDecoded(traceRange: Range<Int>, sampleRange: Range<Int>?) -> [Float] {
        let n = traceRange.count
        let lo = sampleRange?.lowerBound ?? 0
        let hi = sampleRange?.upperBound ?? file.geometry.ns
        let span = hi - lo
        var out = [Float](repeating: 0, count: n * span)
        // Hoist Sendable primitives before the @concurrent closure (no self/file capture).
        let maxT = maxThreads
        let path = file.url.path
        let format = file.geometry.format
        let order = file.geometry.byteOrder
        let bps = format.bytesPerSample
        let step = file.geometry.traceBytes
        let head = Int(file.geometry.firstTraceOffset)
        let fullTrace = (sampleRange == nil)   // 整道读取时可一次大块读，避免每道一次 pread
        out.withUnsafeMutableBufferPointer { obp in
            let buf = BufferRef(obp)
            DispatchQueue.concurrentPerform(iterations: maxT) { t in
                let loI = n * t / maxT, hiI = n * (t + 1) / maxT
                if loI >= hiI { return }
                let fd = open(path, O_RDONLY)
                defer { close(fd) }
                if fullTrace {
                    // 一个分区内所有道的完整字节连续，一次 pread 读整块（含 240 道头），再逐道解码。
                    // 这样向前/向后滚动都退化为单次连续读，消除向后退的回读抖动。
                    let blockLen = (hiI - loI) * step
                    var block = [UInt8](repeating: 0, count: blockLen)
                    let blockStart = off_t(head + (traceRange.lowerBound + loI) * step)
                    block.withUnsafeMutableBytes { _ = pread(fd, $0.baseAddress, blockLen, blockStart) }
                    block.withUnsafeBytes { rb in
                        let base = rb.baseAddress!
                        for i in loI..<hiI {
                            let dataPtr = base + (i - loI) * step + 240
                            Decoder.decode(bytes: dataPtr, count: span, format: format,
                                           order: order, into: buf.base + i * span)
                        }
                    }
                } else {
                    // 采样窗（纵向缩放）时各道只取一段，仍按道 pread。
                    let rawBytes = span * bps
                    var raw = [UInt8](repeating: 0, count: rawBytes)
                    for i in loI..<hiI {
                        let off = off_t(head + (traceRange.lowerBound + i) * step + 240 + lo * bps)
                        raw.withUnsafeMutableBytes { _ = pread(fd, $0.baseAddress, rawBytes, off) }
                        raw.withUnsafeBytes { rb in
                            Decoder.decode(bytes: rb.baseAddress!, count: span, format: format,
                                           order: order, into: buf.base + i * span)
                        }
                    }
                }
            }
        }
        return out
    }

    public func readTraceHeaders(range: Range<Int>) -> [TraceHeader] {
        let n = range.count
        var out = [TraceHeader](repeating: TraceHeader(ffid: 0, traceSeq: 0, cdp: 0, offset: 0, ns: 0, dtMicros: 0), count: n)
        let maxT = maxThreads
        let path = file.url.path
        let order = file.geometry.byteOrder
        let step = file.geometry.traceBytes
        let head = Int(file.geometry.firstTraceOffset)
        out.withUnsafeMutableBufferPointer { obp in
            let buf = BufferRef(obp)
            DispatchQueue.concurrentPerform(iterations: maxT) { t in
                let loI = n * t / maxT, hiI = n * (t + 1) / maxT
                let fd = open(path, O_RDONLY)
                defer { close(fd) }
                var raw = [UInt8](repeating: 0, count: 240)
                for i in loI..<hiI {
                    let off = off_t(head + (range.lowerBound + i) * step)
                    raw.withUnsafeMutableBytes { _ = pread(fd, $0.baseAddress, 240, off) }
                    raw.withUnsafeBytes { rb in
                        buf.base[i] = SegyFile.parseTraceHeader(rb.baseAddress!, order: order)
                    }
                }
            }
        }
        return out
    }
}

/// 仅用于把 withUnsafeMutableBufferPointer 的基址传入 @Sendable 闭包。
/// 各并发分区写入互不重叠的下标区间，因此 @unchecked 是安全的。
private struct BufferRef<Element>: @unchecked Sendable {
    let base: UnsafeMutablePointer<Element>
    init(_ bp: UnsafeMutableBufferPointer<Element>) {
        self.base = bp.baseAddress!
    }
}
