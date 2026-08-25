import Foundation

/// 参与「按当前标题反查」的 key 子集：只有菜单标题在内。
/// 刻意不放工具栏文案——`调色板`/`缩放` 这类词在别处也出现，全表反查会误伤。
public let menuTitleKeys: Set<S> = [
    .menuFileOpen, .menuFileCompare,
    .menuView, .menuViewReset, .menuViewHeaderToggle, .menuViewLanguage,
    .menuNav, .menuNavPrevShot, .menuNavNextShot,
    .menuHelpUsage,
    .sysMenuFile, .sysMenuEdit, .sysMenuWindow, .sysMenuHelp,
    .sysAbout, .sysServices, .sysHide, .sysHideOthers, .sysShowAll, .sysQuit,
    .sysUndo, .sysRedo, .sysCut, .sysCopy, .sysPaste, .sysDelete, .sysSelectAll,
    .sysCloseWindow, .sysMinimize, .sysZoom, .sysBringAllToFront,
]

/// 按标题反查 key：中英两张表都比对，所以在我们支持的任一语言下都认得出来。
/// 注意 menuLangChinese/menuLangEnglish 不在子集里——它们两语同形（中文 / English），
/// 反查无意义，其标题由 MainMenuLocalizer 直接按 key 设。
public func menuKey(forTitle title: String) -> S? {
    guard !title.isEmpty else { return nil }
    for k in menuTitleKeys where zhTable[k] == title || enTable[k] == title {
        return k
    }
    return nil
}

/// 给定菜单项当前标题，返回它在目标语言下应有的标题。认不出则返回 nil（调用方不得改动该项）。
public func retitledMenuTitle(current: String, to lang: Lang) -> String? {
    guard let k = menuKey(forTitle: current) else { return nil }
    return string(k, lang)
}
