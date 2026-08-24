import Foundation
import SegyKit

public struct Viewport: Equatable {
    public var firstTrace: Int = 0
    public var traceSpan: Int = 0     // 0 = 显示全部
    public var firstSample: Int = 0
    public var sampleSpan: Int = 0    // 0 = 全部
    public var gain: GainMode = .percentiles(0.01, 0.99)
    public var palette: Palette = .grayscale
    public init() {}
}
