import Foundation
import SegyKit

/// 把错误映射成当前语言的用户可见文案。
/// 非 SegyError 一律走 errUnknown 兜底，附上其技术描述，保证任何异常都有话可说。
public func userMessage(for error: Error, _ lang: Lang) -> String {
    guard let e = error as? SegyError else {
        return format(.errUnknown, lang, [String(describing: error)])
    }
    switch e {
    case .fileTooSmall:
        return string(.errFileTooSmall, lang)
    case .invalidFormatCode(let c):
        return format(.errInvalidFormatCode, lang, ["\(c)"])
    case .nonIntegerTraceCount(let s, let t, let r):
        return format(.errNonIntegerTraceCount, lang, ["\(s)", "\(t)", "\(r)"])
    case .badSampleCount(let b, let t):
        return format(.errBadSampleCount, lang, ["\(b)", "\(t)"])
    }
}
