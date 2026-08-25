import AppKit
import Localization

/// 把整条菜单栏（含 macOS 自动生成的系统项）重命名到目标语言。
///
/// 为什么不靠 SwiftUI：`.commands` 在 macOS 13 上响应 @Published 重建菜单并不可靠。
/// 既然系统项本来就只能从 AppKit 这边改，索性我们自己的菜单项也走同一条路，
/// 一套机制覆盖整条菜单栏，不赌 SwiftUI 的重建行为。
///
/// 识别策略分两类：
///   1. 系统项按 `action` selector 认——selector 不随语言变，任何系统语言下都认得出来。
///   2. 其余项按「当前标题在中英任一表中匹配到某 key」反查（纯函数在 Localization，已被测试覆盖）。
/// 两类都认不出的项一律**不动**，避免误改第三方或未来新增的菜单项。
@MainActor
enum MainMenuLocalizer {

    /// selector → key。系统项靠这张表定位，与语言无关。
    private static let bySelector: [Selector: S] = [
        #selector(NSApplication.orderFrontStandardAboutPanel(_:)): .sysAbout,
        #selector(NSApplication.hide(_:)): .sysHide,
        #selector(NSApplication.hideOtherApplications(_:)): .sysHideOthers,
        #selector(NSApplication.unhideAllApplications(_:)): .sysShowAll,
        #selector(NSApplication.terminate(_:)): .sysQuit,
        // 撤销/重做的菜单动作是 undo:/redo:（带冒号，发给 first responder）。
        // 写成 #selector(UndoManager.undo) 会得到不带冒号的 "undo"，匹配不上，必须用字符串字面量。
        Selector(("undo:")): .sysUndo,
        Selector(("redo:")): .sysRedo,
        #selector(NSText.cut(_:)): .sysCut,
        #selector(NSText.copy(_:)): .sysCopy,
        #selector(NSText.paste(_:)): .sysPaste,
        #selector(NSText.delete(_:)): .sysDelete,
        #selector(NSText.selectAll(_:)): .sysSelectAll,
        #selector(NSWindow.performClose(_:)): .sysCloseWindow,
        #selector(NSWindow.performMiniaturize(_:)): .sysMinimize,
        #selector(NSWindow.performZoom(_:)): .sysZoom,
        #selector(NSApplication.arrangeInFront(_:)): .sysBringAllToFront,
    ]

    static func apply(_ lang: Lang) {
        guard let main = NSApp.mainMenu else { return }
        for item in main.items {
            relabelSubmenuTitle(item, lang)
            if let sub = item.submenu { walk(sub, lang) }
        }
    }

    /// 顶层子菜单的标题：先按其内部的已知 selector 定位是哪个菜单，再改标题。
    /// App 菜单（含 terminate:）的标题是应用名，语言无关，不动。
    private static func relabelSubmenuTitle(_ item: NSMenuItem, _ lang: Lang) {
        guard let sub = item.submenu else { return }
        if contains(sub, #selector(NSApplication.terminate(_:))) { return }   // App 菜单，标题=应用名
        let key: S?
        if contains(sub, #selector(NSText.selectAll(_:))) {
            key = .sysMenuEdit
        } else if contains(sub, #selector(NSWindow.performMiniaturize(_:))) {
            key = .sysMenuWindow
        } else if sub === NSApp.helpMenu {   // 身份比较，不是值比较
            key = .sysMenuHelp
        } else if contains(sub, #selector(NSWindow.performClose(_:))) {
            key = .sysMenuFile
        } else {
            // 我们自己的菜单（视图 / 导航）：按当前标题反查。
            key = nil
            if let t = retitledMenuTitle(current: item.title, to: lang) {
                item.title = t
                sub.title = t
            }
        }
        if let key {
            item.title = string(key, lang)
            sub.title = string(key, lang)
        }
    }

    private static func contains(_ menu: NSMenu, _ sel: Selector) -> Bool {
        menu.items.contains { $0.action == sel }
    }

    /// 递归重命名菜单项。系统项优先按 selector 认，其余按标题反查，都认不出就不动。
    private static func walk(_ menu: NSMenu, _ lang: Lang) {
        for item in menu.items {
            if let sel = item.action, let key = bySelector[sel] {
                item.title = string(key, lang)
            } else if let t = retitledMenuTitle(current: item.title, to: lang) {
                item.title = t
            }
            // 「服务」子菜单由系统填充，只改它自己的标题。
            // servicesMenu 是可选：先解包再比，避免 item.submenu 与 servicesMenu 同 nil 时
            // `===` 对两个 nil 返回 true，把每个叶子项都误判成「服务」。
            if let services = NSApp.servicesMenu, item.submenu === services {
                item.title = string(.sysServices, lang)
                continue
            }
            if let sub = item.submenu {
                if let t = retitledMenuTitle(current: sub.title, to: lang) { sub.title = t }
                walk(sub, lang)
            }
        }
        applyLanguageCheckmarks(menu, lang)
    }

    /// 语言子菜单的两项两语同形（中文 / English），不参与反查，这里直接按 key 设标题与勾选态。
    /// 勾选态自己维护，不依赖 SwiftUI Toggle 的重建。
    private static func applyLanguageCheckmarks(_ menu: NSMenu, _ lang: Lang) {
        for item in menu.items {
            guard let sub = item.submenu,
                  sub.items.count == 2,
                  retitledMenuTitle(current: item.title, to: lang) == string(.menuViewLanguage, lang)
            else { continue }
            sub.items[0].title = string(.menuLangChinese, lang)
            sub.items[1].title = string(.menuLangEnglish, lang)
            sub.items[0].state = lang == .zh ? .on : .off
            sub.items[1].state = lang == .en ? .on : .off
        }
    }
}
