import Foundation

/// 中英两张文案表并排放在一起，是为了改文案时同一屏能看到两语，不容易只改一边。
/// 完整性（无缺失、无空白、占位符数量一致）由 SegyKitTests 断言。
public let zhTable: [S: String] = [
    .menuFileOpen: "打开 SEG-Y…",
    .menuFileCompare: "对比…",
    .menuView: "视图",
    .menuViewReset: "重置视图",
    .menuViewHeaderToggle: "显示道头信息",
    .menuViewLanguage: "语言",
    .menuLangChinese: "中文",
    .menuLangEnglish: "English",
    .menuNav: "导航",
    .menuNavPrevShot: "上一炮",
    .menuNavNextShot: "下一炮",
    .menuHelpUsage: "SeisView 使用说明",

    .sysMenuFile: "文件",
    .sysMenuEdit: "编辑",
    .sysMenuWindow: "窗口",
    .sysMenuHelp: "帮助",
    .sysAbout: "关于 SeisView",
    .sysServices: "服务",
    .sysHide: "隐藏 SeisView",
    .sysHideOthers: "隐藏其他",
    .sysShowAll: "全部显示",
    .sysQuit: "退出 SeisView",
    .sysUndo: "撤销",
    .sysRedo: "重做",
    .sysCut: "剪切",
    .sysCopy: "拷贝",
    .sysPaste: "粘贴",
    .sysDelete: "删除",
    .sysSelectAll: "全选",
    .sysCloseWindow: "关闭窗口",
    .sysMinimize: "最小化",
    .sysZoom: "缩放",
    .sysBringAllToFront: "前置全部窗口",

    .tbGain: "增益",
    .gainPercentiles: "百分位",
    .gainAGC: "AGC",
    .gainPerTrace: "每道",
    .gainMaxAbs: "最大幅值",
    .tbGainHelp: "增益方式",
    .tbClipHelp: "百分位裁剪：保留中间百分比，越小对比越强",
    .tbPalette: "调色板",
    .paletteGray: "灰度",
    .paletteRedWhiteBlue: "红白蓝",
    .paletteRedWhiteBlack: "红白黑",
    .paletteBrownWhiteBlack: "棕白黑",
    .tbOrder: "排列",
    .orderByTrace: "按道号",
    .orderByOffset: "按偏移距",
    .tbHeaderToggle: "道头信息",
    .tbHeaderToggleHelp: "显示/隐藏右侧道头信息框",
    .tbZoomRect: "局部放大",
    .tbZoomRectHelp: "局部放大：双指点击（右键）拖动框选剖面区域，松开放大到该区域",
    .tbAlign: "对齐",
    .tbAlignHelp: "对齐：所有窗口回到相同道号/采样号起点",
    .tbReset: "重置视图",
    .tbResetHelp: "重置视图（⌘0）：位置与缩放回到初始窗口，保留增益与调色板",
    .tbPrevShot: "上一炮",
    .tbPrevShotHelp: "上一炮",
    .tbNextShot: "下一炮",
    .tbNextShotHelp: "下一炮",

    .zoomTraceAxis: "道方向",
    .zoomTraceAxisHelp: "道方向缩放：左拖=放大，右拖=显示更多道，松手回中",
    .zoomTimeAxis: "时间方向",
    .zoomTimeAxisHelp: "时间方向缩放：左拖=放大，右拖=显示更多采样，松手回中",

    .statusTraces: "道 %@–%@ / %@",
    .statusPositions: "位置 %@–%@ / %@",
    .statusSamples: "采样 %@–%@ / %@",
    .statusTraceSpan: "traceSpan %@",
    .statusCursor: "光标道 %@",
    .statusCursorNone: "—",
    .statusShotCount: "炮索引：%@ 炮",
    .statusShotCurrent: "炮 %@/%@",
    .statusShotBuilding: "炮索引：构建中…",

    .emptyOpenHint: "⌘O 打开 SEG-Y 文件",

    .hdrTitle: "道头",
    .hdrTraceLabel: "道 %@%@",
    .hdrEmptyHint: "点击剖面选择一道\n查看其道头字段",
    .hdrTraceSeq: "道序",
    .hdrFFID: "FFID",
    .hdrCDP: "CDP",
    .hdrOffset: "偏移距",
    .hdrNs: "ns",
    .hdrDt: "dt(μs)",

    .errFileTooSmall: "文件小于 3600 字节，不是合法的 SEG-Y 文件。",
    .errInvalidFormatCode: "不支持的采样格式码 %@。SeisView 支持 1（IBM32）、2（int32）、3（int16）、5（IEEE32）、8（int8）。",
    .errNonIntegerTraceCount: "道长不一致：文件 %@ 字节、道长 %@ 字节、余 %@ 字节。该文件疑似变长道，SeisView 不支持。",
    .errBadSampleCount: "采样点数不一致：二进制头 %@、道头 %@，且都与文件大小对不上。",
    .errUnknown: "打开失败：%@",
    .errAlreadyComparing: "已在对比中：%@",
    .errOpenFailed: "打开失败 %@：%@",

    .helpWindowTitle: "SeisView 使用说明",
]

public let enTable: [S: String] = [
    .menuFileOpen: "Open SEG-Y…",
    .menuFileCompare: "Compare…",
    .menuView: "View",
    .menuViewReset: "Reset View",
    .menuViewHeaderToggle: "Show Trace Headers",
    .menuViewLanguage: "Language",
    .menuLangChinese: "中文",
    .menuLangEnglish: "English",
    .menuNav: "Navigate",
    .menuNavPrevShot: "Previous Shot",
    .menuNavNextShot: "Next Shot",
    .menuHelpUsage: "SeisView Help",

    .sysMenuFile: "File",
    .sysMenuEdit: "Edit",
    .sysMenuWindow: "Window",
    .sysMenuHelp: "Help",
    .sysAbout: "About SeisView",
    .sysServices: "Services",
    .sysHide: "Hide SeisView",
    .sysHideOthers: "Hide Others",
    .sysShowAll: "Show All",
    .sysQuit: "Quit SeisView",
    .sysUndo: "Undo",
    .sysRedo: "Redo",
    .sysCut: "Cut",
    .sysCopy: "Copy",
    .sysPaste: "Paste",
    .sysDelete: "Delete",
    .sysSelectAll: "Select All",
    .sysCloseWindow: "Close Window",
    .sysMinimize: "Minimize",
    .sysZoom: "Zoom",
    .sysBringAllToFront: "Bring All to Front",

    .tbGain: "Gain",
    .gainPercentiles: "Percentiles",
    .gainAGC: "AGC",
    .gainPerTrace: "Per Trace",
    .gainMaxAbs: "Max Amplitude",
    .tbGainHelp: "Gain method",
    .tbClipHelp: "Percentile clip: keep the middle percentage — smaller means stronger contrast",
    .tbPalette: "Palette",
    .paletteGray: "Grayscale",
    .paletteRedWhiteBlue: "Red-White-Blue",
    .paletteRedWhiteBlack: "Red-White-Black",
    .paletteBrownWhiteBlack: "Brown-White-Black",
    .tbOrder: "Order",
    .orderByTrace: "By Trace",
    .orderByOffset: "By Offset",
    .tbHeaderToggle: "Trace Headers",
    .tbHeaderToggleHelp: "Show or hide the trace-header panel on the right",
    .tbZoomRect: "Zoom to Area",
    .tbZoomRectHelp: "Zoom to area: two-finger click (right-click) and drag a box over the section, release to zoom into it",
    .tbAlign: "Align",
    .tbAlignHelp: "Align: return every pane to the same starting trace and sample",
    .tbReset: "Reset View",
    .tbResetHelp: "Reset view (⌘0): position and zoom return to the initial window; gain and palette are kept",
    .tbPrevShot: "Previous Shot",
    .tbPrevShotHelp: "Previous shot",
    .tbNextShot: "Next Shot",
    .tbNextShotHelp: "Next shot",

    .zoomTraceAxis: "Trace axis",
    .zoomTraceAxisHelp: "Trace-axis zoom: drag left to zoom in, right to show more traces; the handle re-centres on release",
    .zoomTimeAxis: "Time axis",
    .zoomTimeAxisHelp: "Time-axis zoom: drag left to zoom in, right to show more samples; the handle re-centres on release",

    .statusTraces: "Traces %@–%@ / %@",
    .statusPositions: "Position %@–%@ / %@",
    .statusSamples: "Samples %@–%@ / %@",
    .statusTraceSpan: "traceSpan %@",
    .statusCursor: "Cursor trace %@",
    .statusCursorNone: "—",
    .statusShotCount: "Shot index: %@ shots",
    .statusShotCurrent: "Shot %@/%@",
    .statusShotBuilding: "Shot index: building…",

    .emptyOpenHint: "Press ⌘O to open a SEG-Y file",

    .hdrTitle: "Trace Header",
    .hdrTraceLabel: "Trace %@%@",
    .hdrEmptyHint: "Click a trace in the section\nto inspect its header fields",
    .hdrTraceSeq: "Trace seq",
    .hdrFFID: "FFID",
    .hdrCDP: "CDP",
    .hdrOffset: "Offset",
    .hdrNs: "ns",
    .hdrDt: "dt(μs)",

    .errFileTooSmall: "File is smaller than 3600 bytes; it is not a valid SEG-Y file.",
    .errInvalidFormatCode: "Unsupported sample format code %@. SeisView supports 1 (IBM32), 2 (int32), 3 (int16), 5 (IEEE32) and 8 (int8).",
    .errNonIntegerTraceCount: "Trace length mismatch: file %@ bytes, trace %@ bytes, remainder %@ bytes. This file appears to use variable-length traces, which SeisView does not support.",
    .errBadSampleCount: "Sample-count mismatch: binary header says %@, trace header says %@, and neither agrees with the file size.",
    .errUnknown: "Could not open the file: %@",
    .errAlreadyComparing: "Already comparing: %@",
    .errOpenFailed: "Could not open %@: %@",

    .helpWindowTitle: "SeisView Help",
]

/// 取一条文案。key 缺失时回落成 key 名本身——测试会先一步抓住缺失，这里只保证不崩。
public func string(_ k: S, _ lang: Lang) -> String {
    let table = lang == .zh ? zhTable : enTable
    return table[k] ?? k.rawValue
}

/// 按顺序把文案里的 %@ 替换成 args。多余参数忽略；参数不足时剩余 %@ 原样保留。
public func format(_ k: S, _ lang: Lang, _ args: [String]) -> String {
    var out = string(k, lang)
    for a in args {
        guard let r = out.range(of: "%@") else { break }
        out.replaceSubrange(r, with: a)
    }
    return out
}

/// 文案里 %@ 的个数。供测试断言中英占位符一致。
public func placeholderCount(_ s: String) -> Int {
    s.components(separatedBy: "%@").count - 1
}
