import Foundation

/// 单边振幅谱结果。frequencies/amplitudes 等长（N/2+1），f[k] ∈ [0, Nyquist]。
public struct Spectrum: Sendable, Equatable {
    public let frequencies: [Double]   // Hz
    public let amplitudes: [Float]     // |X(k)|
    public let dtMicros: Int
    public let nSamples: Int           // 原始样本数（未填充）
    public init(frequencies: [Double], amplitudes: [Float], dtMicros: Int, nSamples: Int) {
        self.frequencies = frequencies; self.amplitudes = amplitudes
        self.dtMicros = dtMicros; self.nSamples = nSamples
    }
    public var nyquist: Double { frequencies.last ?? 0 }
}

public enum FFT {
    /// 实数序列 → Hann 窗 → 零填充到 2 的幂 → radix-2 FFT → 单边振幅 |X|。
    public static func amplitudeSpectrum(_ samples: [Float], dtMicros: Int) -> Spectrum {
        let m = samples.count
        let dt = Double(dtMicros) / 1e6
        guard m > 1 else {
            return Spectrum(frequencies: [0], amplitudes: [abs(samples.first ?? 0)],
                            dtMicros: dtMicros, nSamples: m)
        }
        // Hann 窗（基于原始长度 m，非填充长度）
        var windowed = [Double](repeating: 0, count: m)
        for k in 0..<m {
            let w = 0.5 * (1 - cos(2 * .pi * Double(k) / Double(m - 1)))
            windowed[k] = Double(samples[k]) * w
        }
        let n = nextPowerOfTwo(m)
        var re = [Double](repeating: 0, count: n)
        var im = [Double](repeating: 0, count: n)
        for k in 0..<m { re[k] = windowed[k] }
        fft(&re, &im)
        let half = n / 2
        var freqs = [Double](repeating: 0, count: half + 1)
        var amps = [Float](repeating: 0, count: half + 1)
        for k in 0...half {
            freqs[k] = Double(k) / (Double(n) * dt)
            amps[k] = Float(sqrt(re[k] * re[k] + im[k] * im[k]))
        }
        return Spectrum(frequencies: freqs, amplitudes: amps, dtMicros: dtMicros, nSamples: m)
    }

    /// 带通滤波：保留 [lowHz, highHz] 频带内的能量，其余置零。
    /// 零填充到 2 的幂 → 前向 FFT → 频带掩码（带边余弦锥度抑制 Gibbs 振铃）→ 逆 FFT。
    /// 返回与输入等长的实数序列。dtMicros<=0 或样本数<2 时无频率轴可算，原样返回。
    public static func bandPass(_ samples: [Float], dtMicros: Int, lowHz: Double, highHz: Double) -> [Float] {
        let m = samples.count
        guard m > 1, dtMicros > 0 else { return samples }
        let dt = Double(dtMicros) / 1e6
        let nyquist = 1.0 / (2.0 * dt)
        let lo = max(0, lowHz)
        let hi = min(highHz, nyquist)
        guard hi > lo else { return [Float](repeating: 0, count: m) }  // 频带整体在 Nyquist 之外 → 全零

        let n = nextPowerOfTwo(m)
        var re = [Double](repeating: 0, count: n)
        var im = [Double](repeating: 0, count: n)
        for k in 0..<m { re[k] = Double(samples[k]) }
        fft(&re, &im)

        // 频带掩码：k ∈ [0, n/2] 对应 f = k/(n·dt)，镜像 bin n−k 共享同一增益。
        let taper = 0.05 * (hi - lo)
        var gain = [Double](repeating: 0, count: n / 2 + 1)
        for k in 0...(n / 2) {
            let f = Double(k) / (Double(n) * dt)
            gain[k] = taperGain(f, lo: lo, hi: hi, taper: taper)
        }
        for k in 0..<n {
            let g = gain[k <= n / 2 ? k : n - k]
            re[k] *= g
            im[k] *= g
        }

        // 逆 FFT：IFFT(X) = conj(FFT(conj(X))) / n。
        for k in 0..<n { im[k] = -im[k] }
        fft(&re, &im)
        for k in 0..<n { im[k] = -im[k] }
        let inv = 1.0 / Double(n)
        var out = [Float](repeating: 0, count: m)
        for k in 0..<m { out[k] = Float(re[k] * inv) }
        return out
    }

    /// 带边余弦锥度：带内为 1、带外为 0，过渡带 [edge−taper, edge] 用半余弦平滑过渡。
    private static func taperGain(_ f: Double, lo: Double, hi: Double, taper: Double) -> Double {
        if f < lo {
            let x = (f - (lo - taper)) / taper
            return x <= 0 ? 0 : (x >= 1 ? 1 : 0.5 * (1 - cos(.pi * x)))
        }
        if f > hi {
            let x = (f - hi) / taper
            return x <= 0 ? 1 : (x >= 1 ? 0 : 0.5 * (1 + cos(.pi * x)))
        }
        return 1
    }

    private static func nextPowerOfTwo(_ v: Int) -> Int {
        var n = 1
        while n < v { n <<= 1 }
        return n
    }

    /// 就地迭代 radix-2 FFT（Cooley–Tukey，要求 n 为 2 的幂）。
    private static func fft(_ re: inout [Double], _ im: inout [Double]) {
        let n = re.count
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j |= bit
            if i < j { re.swapAt(i, j); im.swapAt(i, j) }
        }
        var len = 2
        while len <= n {
            let ang = -2 * .pi / Double(len)
            let wr = cos(ang), wi = sin(ang)
            var i = 0
            while i < n {
                var wrk = 1.0, wik = 0.0
                for k in 0..<(len / 2) {
                    let a = i + k, b = i + k + len / 2
                    let tr = re[b] * wrk - im[b] * wik
                    let ti = re[b] * wik + im[b] * wrk
                    re[b] = re[a] - tr; im[b] = im[a] - ti
                    re[a] = re[a] + tr; im[a] = im[a] + ti
                    let nwr = wrk * wr - wik * wi
                    wik = wrk * wi + wik * wr
                    wrk = nwr
                }
                i += len
            }
            len <<= 1
        }
    }
}

public enum SpectrumBuilder {
    /// 把按道排列的平面样本平均成一道（先叠后 FFT）。
    public static func stack(_ samples: [Float], nTraces: Int, ns: Int) -> [Float] {
        guard nTraces > 0, ns > 0 else { return [] }
        var out = [Float](repeating: 0, count: ns)
        for t in 0..<nTraces {
            let base = t * ns
            for s in 0..<ns { out[s] += samples[base + s] }
        }
        let inv = 1.0 / Float(nTraces)
        for s in 0..<ns { out[s] *= inv }
        return out
    }

    /// 均匀抽 ≤maxTraces 个下标（含首末道），保证超大文件可控。
    public static func sampledIndices(range: Range<Int>, maxTraces: Int) -> [Int] {
        let n = range.count
        guard n > 0, maxTraces > 0 else { return [] }
        guard n > maxTraces else { return Array(range) }
        let stride = Int((Double(n) / Double(maxTraces)).rounded(.up))
        var out: [Int] = []
        var i = 0
        while i < n { out.append(range.lowerBound + i); i += stride }
        if out.last != range.upperBound - 1 { out.append(range.upperBound - 1) }
        return out
    }
}
