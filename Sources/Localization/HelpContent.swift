import Foundation

public struct HelpShortcut: Sendable {
    public let keys: String
    public let desc: String
    public init(_ keys: String, _ desc: String) { self.keys = keys; self.desc = desc }
}

public enum HelpBlock: Sendable {
    case paragraph(String)
    case bullets([String])
    case keyTable([HelpShortcut])
}

public struct HelpSection: Sendable, Identifiable {
    public let id: Int
    public let title: String
    public let blocks: [HelpBlock]
    public init(id: Int, title: String, blocks: [HelpBlock]) {
        self.id = id; self.title = title; self.blocks = blocks
    }
}

/// 九章使用说明。中英结构严格一一对应（章节数、每章 block 数与类型、列表长度），
/// 由 SegyKitTests 断言——漏译一段会当场变红。
/// 文案里举例一律用中性文件名，不得出现任何真实数据文件名或本机路径。
public func helpSections(_ lang: Lang) -> [HelpSection] {
    lang == .zh ? zhHelp() : enHelp()
}

private func zhHelp() -> [HelpSection] {
    [
        HelpSection(id: 0, title: "快速上手", blocks: [
            .paragraph("SeisView 是 macOS 上的 SEG-Y 地震数据查看器，以变密度方式显示剖面，专为超大文件设计——十 GB 级、数十万道也能即时打开、即时浏览。"),
            .bullets([
                "⌘O 打开一个 .sgy / .segy 文件。",
                "在剖面上横向滑动浏览道号，纵向滑动浏览时间（需先在时间方向放大）。",
                "用正文顶部的两个滑块调整道方向 / 时间方向的缩放。",
                "⌘← / ⌘→ 逐炮翻看。",
                "⌘0 随时回到初始视图。",
            ]),
            .paragraph("SeisView 只读文件，从不写回或修改你的数据。"),
        ]),
        HelpSection(id: 1, title: "打开与对比", blocks: [
            .paragraph("⌘O 选择文件，或在访达里双击 .sgy / .segy 文件。打开面板不做扩展名过滤——自定义扩展名的地震文件也能选中，能否打开由 SeisView 实际解析文件头决定。"),
            .paragraph("⇧⌘O 追加一个文件进入并排对比。两个剖面共享同一个视口，缩放、平移、翻炮天然联动，便于逐道比对处理前后的差异。"),
            .bullets([
                "中间的分隔条可以拖动，调整左右宽度。",
                "工具栏的「对齐」让所有窗格回到相同的道号 / 采样号起点。",
                "重复添加同一个文件会被忽略，避免与自身对比。",
            ]),
        ]),
        HelpSection(id: 2, title: "鼠标与手势", blocks: [
            .bullets([
                "触控板横向滑动：沿道号平移。",
                "触控板纵向滑动：沿时间平移。仅在时间方向放大后可用——全采样铺满时纵向没有可滚动的余量。",
                "捏合：缩放。",
                "单击剖面：选中该道，右侧道头信息框随即显示它的道头字段。",
                "双指点击（即右键）拖动：框选一块区域，松开后放大到该区域。需先打开工具栏的「局部放大」。",
            ]),
            .paragraph("向左滚动会比向右略慢一些。向右是顺序读取、能吃到系统预取；向左要回头读已经冷掉的页。这是磁盘 I/O 的固有差异，不是卡顿。"),
        ]),
        HelpSection(id: 3, title: "工具栏", blocks: [
            .bullets([
                "增益：决定振幅如何映射到颜色。「百分位」按分位数裁剪（最常用）；「AGC」自动增益控制，弱信号也能看清；「每道」逐道独立标定；「最大幅值」按全局最大绝对值标定。",
                "百分位滑块：选「百分位」时出现，表示保留中间多大比例的振幅，数值越小对比越强。",
                "调色板：灰度、红白蓝、红白黑、棕白黑四种。",
                "道头信息：显示 / 隐藏右侧道头信息框。",
                "局部放大：打开后用双指点击（右键）拖框选择区域，松开即放大并自动退出该模式。",
                "对齐：仅在对比模式下出现，让所有窗格回到相同起点。",
                "重置视图：位置与缩放回到初始窗口，增益与调色板保持不变。",
                "上一炮 / 下一炮：在炮之间跳转，需炮索引构建完成。",
            ]),
        ]),
        HelpSection(id: 4, title: "缩放与导航", blocks: [
            .paragraph("正文顶部有「道方向」和「时间方向」两个滑块。它们是相对缩放：向左拖放大、向右拖显示更多，松手后把手自动回到中点，缩放效果保留。拖动过程中不会重新渲染，松手才应用一次——这样拖动始终跟手。"),
            .bullets([
                "水平滚动条：在整个文件的道号范围内定位。",
                "垂直滚动条：仅在时间方向放大后可用。全采样铺满时没有可滚动的余量，它会呈禁用状态。",
                "⌘0 重置视图：只把位置与缩放归位，保留你调好的增益与调色板。",
            ]),
            .paragraph("炮索引在打开文件后于后台构建，状态栏会显示「构建中…」，完成后显示总炮数。构建期间其余功能照常可用。"),
        ]),
        HelpSection(id: 5, title: "道头信息", blocks: [
            .paragraph("单击剖面上任意一道，右侧面板即显示该道的 SEG-Y 道头字段，同时标出各字段在道头中的字节位置（1-indexed），便于与规范或其他软件核对。若该道落在当前炮范围内，还会附上它的 FFID。"),
            .bullets([
                "道序：字节 1–4",
                "FFID（原始炮号）：字节 9–12",
                "CDP：字节 21–24",
                "偏移距：字节 37–40",
                "ns（每道采样数）：字节 115–116",
                "dt（采样间隔，微秒）：字节 117–118",
            ]),
            .paragraph("⇧⌘H 可随时开关这个面板。"),
        ]),
        HelpSection(id: 6, title: "快捷键", blocks: [
            .keyTable([
                HelpShortcut("⌘O", "打开 SEG-Y 文件"),
                HelpShortcut("⇧⌘O", "追加一个文件并排对比"),
                HelpShortcut("⌘0", "重置视图"),
                HelpShortcut("⇧⌘H", "显示 / 隐藏道头信息"),
                HelpShortcut("⌘←", "上一炮"),
                HelpShortcut("⌘→", "下一炮"),
                HelpShortcut("⌘?", "打开本使用说明"),
                HelpShortcut("⌘W", "关闭窗口"),
                HelpShortcut("⌘Q", "退出 SeisView"),
            ]),
        ]),
        HelpSection(id: 7, title: "支持的 SEG-Y 格式", blocks: [
            .bullets([
                "采样格式码：1（IBM 32 位浮点）、2（32 位整型）、3（16 位整型）、5（IEEE 32 位浮点）、8（8 位整型）。",
                "字节序：大端；格式码带 rev2 小端标志时按小端解析。",
                "扩展文本头：按二进制头声明的数量正确跳过。",
            ]),
            .paragraph("有些文件二进制头声明为 IBM 浮点，实际存的却是 IEEE。SeisView 会用首道样本按两种方式各解一遍，比较结果的合理性，若 IEEE 明显更合理就自动改用 IEEE 解码，无需你手动干预。"),
            .paragraph("当二进制头里的采样点数与首道道头不一致时，SeisView 取与文件大小整除吻合的那个；两者都吻合或都不吻合时以二进制头为准。真实数据的道头采样点数经常不可靠，这条判据比盲信任一方更稳妥。"),
        ]),
        HelpSection(id: 8, title: "已知限制", blocks: [
            .paragraph("这一节如实列出 SeisView 现在做不到的事，免得你花时间找不存在的功能。"),
            .bullets([
                "只有变密度显示，没有 Wiggle 波形。",
                "没有频谱分析、图片导出，也不支持把数据写回文件。",
                "变长道文件不支持：道长除不尽时会明确报错，而不是静默显示出错乱的剖面。",
                "对比模式只有并排，没有叠加模式。",
                "垂直滚动条仅在时间方向放大后可用。",
                "向左滚动比向右略慢，属于磁盘读取的固有差异。",
                "应用未经 Apple 公证。首次打开需在访达里右键点击图标、选择「打开」。",
            ]),
        ]),
    ]
}

private func enHelp() -> [HelpSection] {
    [
        HelpSection(id: 0, title: "Getting Started", blocks: [
            .paragraph("SeisView is a SEG-Y seismic data viewer for macOS. It renders sections in variable-density form and is built for very large files — tens of gigabytes and hundreds of thousands of traces open and scroll instantly."),
            .bullets([
                "Press ⌘O to open a .sgy or .segy file.",
                "Swipe horizontally to move along traces, vertically to move through time (zoom the time axis first).",
                "Use the two sliders above the section to zoom the trace and time axes.",
                "Press ⌘← / ⌘→ to step through shots.",
                "Press ⌘0 at any time to return to the initial view.",
            ]),
            .paragraph("SeisView only ever reads your files. It never writes back or modifies your data."),
        ]),
        HelpSection(id: 1, title: "Opening and Comparing", blocks: [
            .paragraph("Press ⌘O to choose a file, or double-click a .sgy / .segy file in Finder. The open panel does not filter by extension — seismic files with unusual extensions can still be selected, and whether a file opens is decided by actually parsing its headers."),
            .paragraph("Press ⇧⌘O to add a second file side by side. Both sections share one viewport, so zooming, panning and shot navigation stay in lockstep — which is what you want when comparing a section before and after processing."),
            .bullets([
                "Drag the divider between panes to change their widths.",
                "The Align button returns every pane to the same starting trace and sample.",
                "Adding the same file twice is ignored, so a file is never compared against itself.",
            ]),
        ]),
        HelpSection(id: 2, title: "Mouse and Gestures", blocks: [
            .bullets([
                "Trackpad, horizontal swipe: pan along traces.",
                "Trackpad, vertical swipe: pan through time. Available only after zooming the time axis — with all samples on screen there is nothing left to scroll.",
                "Pinch: zoom.",
                "Click the section: select that trace; the header panel on the right updates to show its fields.",
                "Two-finger click (right-click) and drag: draw a box, release to zoom into it. Turn on Zoom to Area in the toolbar first.",
            ]),
            .paragraph("Scrolling left is slightly slower than scrolling right. Rightward scrolling reads the file forward and benefits from the operating system's read-ahead; leftward scrolling has to revisit pages that have gone cold. This is inherent to disk I/O, not a stall."),
        ]),
        HelpSection(id: 3, title: "Toolbar", blocks: [
            .bullets([
                "Gain: how amplitudes map to colour. Percentiles clips at a quantile (the usual choice); AGC applies automatic gain control so weak signal stays visible; Per Trace scales each trace independently; Max Amplitude scales by the global maximum absolute value.",
                "Percentile slider: appears with Percentiles gain. It sets how much of the amplitude range to keep in the middle — smaller values give stronger contrast.",
                "Palette: Grayscale, Red-White-Blue, Red-White-Black, Brown-White-Black.",
                "Trace Headers: show or hide the header panel on the right.",
                "Zoom to Area: once on, two-finger click (right-click) and drag a box; release to zoom in and leave the mode automatically.",
                "Align: appears in compare mode; returns every pane to the same starting point.",
                "Reset View: position and zoom return to the initial window; gain and palette are left untouched.",
                "Previous / Next Shot: jump between shots once the shot index has finished building.",
            ]),
        ]),
        HelpSection(id: 4, title: "Zooming and Navigation", blocks: [
            .paragraph("Above the section are two sliders, Trace axis and Time axis. They are relative: drag left to zoom in, drag right to show more, and the handle returns to the centre when you release while the zoom is kept. Nothing re-renders while you drag — the zoom is applied once on release, which is what keeps dragging responsive."),
            .bullets([
                "Horizontal scroll bar: jump anywhere in the file's trace range.",
                "Vertical scroll bar: available only after zooming the time axis. With all samples on screen there is nothing to scroll and the bar is disabled.",
                "⌘0 Reset View: restores position and zoom only, keeping the gain and palette you set.",
            ]),
            .paragraph("The shot index is built in the background after a file opens. The status bar shows \"building…\" while it works and the shot count when it finishes. Everything else stays usable in the meantime."),
        ]),
        HelpSection(id: 5, title: "Trace Headers", blocks: [
            .paragraph("Click any trace in the section and the panel on the right shows that trace's SEG-Y header fields, along with each field's byte position in the trace header (1-indexed) so you can cross-check against the specification or another package. If the trace falls inside the current shot, its FFID is shown too."),
            .bullets([
                "Trace sequence number: bytes 1–4",
                "FFID (original field record number): bytes 9–12",
                "CDP: bytes 21–24",
                "Offset: bytes 37–40",
                "ns (samples per trace): bytes 115–116",
                "dt (sample interval, microseconds): bytes 117–118",
            ]),
            .paragraph("Press ⇧⌘H to show or hide this panel at any time."),
        ]),
        HelpSection(id: 6, title: "Keyboard Shortcuts", blocks: [
            .keyTable([
                HelpShortcut("⌘O", "Open a SEG-Y file"),
                HelpShortcut("⇧⌘O", "Add a file for side-by-side comparison"),
                HelpShortcut("⌘0", "Reset view"),
                HelpShortcut("⇧⌘H", "Show / hide trace headers"),
                HelpShortcut("⌘←", "Previous shot"),
                HelpShortcut("⌘→", "Next shot"),
                HelpShortcut("⌘?", "Open this help"),
                HelpShortcut("⌘W", "Close window"),
                HelpShortcut("⌘Q", "Quit SeisView"),
            ]),
        ]),
        HelpSection(id: 7, title: "Supported SEG-Y Formats", blocks: [
            .bullets([
                "Sample format codes: 1 (IBM 32-bit float), 2 (32-bit integer), 3 (16-bit integer), 5 (IEEE 32-bit float), 8 (8-bit integer).",
                "Byte order: big-endian; files flagged as rev2 little-endian are parsed as little-endian.",
                "Extended textual headers are skipped correctly according to the count declared in the binary header.",
            ]),
            .paragraph("Some files declare IBM floating point in the binary header but actually store IEEE. SeisView decodes the first trace both ways, compares how plausible each result is, and switches to IEEE automatically when it is clearly the better fit — no manual intervention needed."),
            .paragraph("When the sample count in the binary header disagrees with the first trace header, SeisView takes whichever one divides evenly into the file size; if both or neither agree, the binary header wins. Sample counts in real-world trace headers are often unreliable, and this test is more dependable than trusting either field outright."),
        ]),
        HelpSection(id: 8, title: "Known Limitations", blocks: [
            .paragraph("This section lists honestly what SeisView cannot do, so you don't spend time looking for features that aren't there."),
            .bullets([
                "Variable-density display only — there is no wiggle-trace mode.",
                "No spectrum analysis, no image export, and no writing data back to file.",
                "Variable-length trace files are not supported: when the trace length does not divide evenly, SeisView reports a clear error instead of silently showing a scrambled section.",
                "Compare mode is side-by-side only; there is no overlay mode.",
                "The vertical scroll bar is available only after zooming the time axis.",
                "Scrolling left is slightly slower than scrolling right, which is inherent to disk reads.",
                "The app is not notarized by Apple. The first time you open it, right-click the icon in Finder and choose Open.",
            ]),
        ]),
    ]
}
