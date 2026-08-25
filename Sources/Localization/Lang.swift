import Foundation

/// 界面语言。rawValue 即写进 UserDefaults 的值。
public enum Lang: String, CaseIterable, Sendable {
    case zh
    case en

    /// 按系统偏好语言推断：前缀 zh（zh-Hans / zh-Hant / zh-HK …）→ 中文，其余一律英文。
    /// `preferred` 带默认值是为了让测试能注入固定列表，不依赖运行环境。
    public static func fromSystem(preferred: [String] = Locale.preferredLanguages) -> Lang {
        guard let first = preferred.first else { return .en }
        return first.hasPrefix("zh") ? .zh : .en
    }

    /// 语言真值解析：用户显式选过就用用户的，否则跟随系统。
    /// stored 是 UserDefaults 里的原始字符串，可能为 nil 或非法值。
    public static func resolve(stored: String?, preferred: [String] = Locale.preferredLanguages) -> Lang {
        if let stored, let l = Lang(rawValue: stored) { return l }
        return fromSystem(preferred: preferred)
    }
}
