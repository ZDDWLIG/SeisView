import SegyKit

/// 视速度测算的一次点击：position = 剖面位置（绘制用），sample = 采样号，offset = 解析出的真实道号 offset。
struct VelocityAnchor {
    let position: Int
    let sample: Int
    let offset: Int
}

/// 视速度线的端点（仅绘制用坐标）。
struct VelocityPoint: Equatable {
    let position: Int
    let sample: Int
}

/// 已完成的视速度测量：两端点 + 速度值（m/s）。
struct VelocityLine: Equatable {
    let start: VelocityPoint
    let end: VelocityPoint
    let mps: Float
}

/// 单道波形数据（Task 6 使用，这里一并定义）。
struct SingleTraceData: Identifiable {
    let trace: Int
    let ffid: Int?
    let samples: [Float]
    let dtMicros: Int
    var id: Int { trace }
}

/// 振幅谱结果（Task 8 使用，这里一并定义）。
struct SpectrumResult: Identifiable {
    let spectrum: Spectrum
    let title: String
    let ns: Int
    let dtMicros: Int
    var id: Int { ns }
}
