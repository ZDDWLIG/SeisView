public enum ByteOrder: Sendable { case big, little }

public enum SampleFormat: Sendable, Equatable {
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
    /// 源（炮点）/ 接收（检波点）坐标（SEG-Y 道头字节 73–88）与坐标比例因子（字节 71–72）。
    /// 默认 0 表示未解码/缺失，旧代码与测试仍可只按核心字段构造。
    public var sx: Int; public var sy: Int; public var gx: Int; public var gy: Int
    public var coordScalar: Int
    /// 高程：检波点高程（字节 41–44）、源地表高程（字节 45–48），
    /// 与高程比例因子（字节 69–70，与坐标比例因子分离）。
    public var receiverElevation: Int; public var sourceElevation: Int
    public var elevationScalar: Int
    public init(ffid: Int, traceSeq: Int, cdp: Int, offset: Int, ns: Int, dtMicros: Int,
                sx: Int = 0, sy: Int = 0, gx: Int = 0, gy: Int = 0, coordScalar: Int = 0,
                receiverElevation: Int = 0, sourceElevation: Int = 0, elevationScalar: Int = 0) {
        self.ffid = ffid; self.traceSeq = traceSeq; self.cdp = cdp
        self.offset = offset; self.ns = ns; self.dtMicros = dtMicros
        self.sx = sx; self.sy = sy; self.gx = gx; self.gy = gy
        self.coordScalar = coordScalar
        self.receiverElevation = receiverElevation; self.sourceElevation = sourceElevation
        self.elevationScalar = elevationScalar
    }

    /// 应用坐标比例因子后的源坐标（正标量相乘、负标量取 |s| 相除、0 视为 1）。
    public var sourceX: Double { Self.scaled(sx, scalar: coordScalar) }
    public var sourceY: Double { Self.scaled(sy, scalar: coordScalar) }
    public var receiverX: Double { Self.scaled(gx, scalar: coordScalar) }
    public var receiverY: Double { Self.scaled(gy, scalar: coordScalar) }

    /// 应用高程比例因子后的高程（z）。
    public var receiverElevationValue: Double { Self.scaled(receiverElevation, scalar: elevationScalar) }
    public var sourceElevationValue: Double { Self.scaled(sourceElevation, scalar: elevationScalar) }

    /// SEG-Y 坐标比例因子语义：scalar > 0 相乘、scalar < 0 除 |scalar|、scalar == 0 视为 1。
    static func scaled(_ v: Int, scalar: Int) -> Double {
        let d = Double(v)
        if scalar > 0 { return d * Double(scalar) }
        if scalar < 0 { return d / Double(-scalar) }
        return d
    }
}
