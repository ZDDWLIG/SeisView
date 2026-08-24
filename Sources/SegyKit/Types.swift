public enum ByteOrder: Sendable { case big, little }

public enum SampleFormat: Sendable {
    case ibm32, int32, int16, ieee32, int8
    public var bytesPerSample: Int {
        switch self { case .ibm32, .int32, .ieee32: return 4
                      case .int16: return 2; case .int8: return 1 }
    }
}

public struct Geometry: Sendable, Equatable {
    public var ns: Int; public var dtMicros: Int
    public var format: SampleFormat; public var byteOrder: ByteOrder
    public var firstTraceOffset: UInt64; public var traceBytes: Int; public var nTraces: Int
    public init(ns: Int, dtMicros: Int, format: SampleFormat, byteOrder: ByteOrder,
                firstTraceOffset: UInt64, traceBytes: Int, nTraces: Int) {
        self.ns = ns; self.dtMicros = dtMicros; self.format = format
        self.byteOrder = byteOrder; self.firstTraceOffset = firstTraceOffset
        self.traceBytes = traceBytes; self.nTraces = nTraces
    }
}

public struct BinaryHeader: Sendable {
    public var ns: Int; public var dtMicros: Int; public var formatCode: Int
    public var segyRevision: Int; public var fixedLengthFlag: Int; public var extTextHeaders: Int
    public init(ns: Int, dtMicros: Int, formatCode: Int, segyRevision: Int,
                fixedLengthFlag: Int, extTextHeaders: Int) {
        self.ns = ns; self.dtMicros = dtMicros; self.formatCode = formatCode
        self.segyRevision = segyRevision; self.fixedLengthFlag = fixedLengthFlag
        self.extTextHeaders = extTextHeaders
    }
}

public struct TraceHeader: Sendable {
    public var ffid: Int; public var traceSeq: Int; public var cdp: Int
    public var offset: Int; public var ns: Int; public var dtMicros: Int
    public init(ffid: Int, traceSeq: Int, cdp: Int, offset: Int, ns: Int, dtMicros: Int) {
        self.ffid = ffid; self.traceSeq = traceSeq; self.cdp = cdp
        self.offset = offset; self.ns = ns; self.dtMicros = dtMicros
    }
}
