import SwiftUI
import Localization

/// 界面语言的唯一真值来源。UserDefaults 只是它的持久化投影，不是第二份真值。
@MainActor
final class L10n: ObservableObject {
    static let shared = L10n()

    private static let defaultsKey = "SeisViewLanguage"

    @Published private(set) var lang: Lang

    private init() {
        lang = Lang.resolve(stored: UserDefaults.standard.string(forKey: Self.defaultsKey))
    }

    /// 切换语言：写盘、发 objectWillChange 让 SwiftUI 重绘、再刷整条菜单栏。
    /// 菜单栏必须单独刷——SwiftUI 的 .commands 在 macOS 13 上不保证响应 @Published 重建。
    func set(_ l: Lang) {
        guard l != lang else { return }
        lang = l
        UserDefaults.standard.set(l.rawValue, forKey: Self.defaultsKey)
        MainMenuLocalizer.apply(l)
    }

    /// 视图里写作 l10n(.menuFileOpen)。
    func callAsFunction(_ k: S) -> String { string(k, lang) }

    /// 带占位符的文案。
    func f(_ k: S, _ args: [String]) -> String { format(k, lang, args) }
}

/// 把任意错误渲染成当前语言的文案。AppError 走自带 key，其余交给 Localization.userMessage。
@MainActor
func errorMessage(_ e: Error, _ l10n: L10n) -> String {
    if let a = e as? AppError { return l10n.f(a.key, a.args) }
    return userMessage(for: e, l10n.lang)
}
