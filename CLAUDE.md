# SeisView — 开发与维护手册

macOS 原生 SEG-Y / SGY 地震数据查看器，对标 Windows 的 SeiSee，核心是超大文件（10 GB 级、数十万道）的**即时显示**。纯 Swift，零第三方依赖。界面支持中文（简体）与 English，首次启动跟随系统语言，可在 View → Language 切换（即时生效、持久记忆），并内置双语使用说明（⌘?）。

---

## ⚠️ 先读：开源与保密约束（最高优先级）

本仓库已公开到 GitHub（MIT License，**仅个人署名**）。因此**仓库内容（含提交信息与全部历史）绝对禁止出现**：

- 单位 / 研究院 / 国企名称
- 真实数据文件名与目录名
- 本机绝对路径（含用户主目录）

**这些关键词的确切清单与「推送前扫描命令」保存在本地项目 memory（`seisview-github-repo`）里，刻意不写进本仓库**——写进来等于再次泄露。每次改动后、`git push` 前，务必按 memory 里的命令全量扫描（工作树 + 全部历史），输出为空才推。

其他约定：

- `docs/` 已加入 `.gitignore`：设计文档 / 实现计划（含实测性能数据、训练口径）刻意不公开，本地保留。
- 大文件黄金测试 / 性能回归读 `SEGY_BIG_FILE` 环境变量，未设置则**跳过**。**任何代码都不得硬编码数据路径。**
- 提交作者统一为个人署名 + 个人邮箱（勿用本机自动生成的 `.local` 假邮箱）。

---

## 架构

```
SegyKit（纯核心，零 UI 依赖，可独立测试）
├── Types.swift        SampleFormat / ByteOrder / Geometry / BinaryHeader / TraceHeader
├── ByteOrder.swift    ByteOrderReader.u16/u32（大/小端读取）
├── IBM.swift          IBM→IEEE 解码（指数查找表）
├── Decoder.swift      按 SampleFormat 解码原始字节 → [Float]
├── SegyFile.swift     打开、头解析、几何推断与校验、假 IBM 自动校正
├── TraceReader.swift  并行 pread + 解码（每线程独立 fd，整道大块读）
├── Decimator.swift    min/max 分箱降采样
├── Gain.swift         百分位 / AGC / 每道 / maxAbs 标定 + GainKind（去载荷的种类）
├── Rasterizer.swift   振幅 → CGImage（灰度/红白蓝/红白黑/棕白黑 4 配色，256×3 LUT）
├── Viewport.swift     纯值类型视口状态 + 平移/缩放/重置/百分比换算 + decodePlan + 中心锚缩放 + 缩放映射 + maxTraceSpan 上限
├── ScrollMetrics.swift 滚动条滑块几何（长度/偏移/像素↔索引反算）
├── ShotIndex.swift    FFID 炮索引（抽样 + 二分）
├── TraceOrder.swift  剖面排列方式（byTrace / byOffset）
└── OffsetIndex.swift 炮内 offset 排序置换 + 每炮起始位置

Localization（纯文案库，依赖 SegyKit，被 SeisView 与 SegyKitTests 共用）
├── Lang.swift         语言状态（系统检测 + 用户覆盖）
├── StringKey.swift    S 枚举（87 个界面文案 key）
├── Tables.swift       zh/en 两张文案表 + string/format
├── ErrorText.swift    SegyError → 本地化用户文案
├── MenuTitles.swift   菜单标题中英反查（纯函数）
└── HelpContent.swift  双语使用说明九章（结构化数据，中英严格对应）

SeisView（AppKit + SwiftUI）
├── SeisViewApp.swift  入口 + 工具栏（增益/百分比/调色板/局部放大/道头开关/重置/对齐/炮导航）+ ZoomBar 缩放条 + LineSlider 单线滑块 + onOpenURL + ContentView/StatusBar
├── DocumentModel.swift 已开文件 + 视口状态 + 渲染管线 + showHeaderInspector/zoomRectMode/zoomToRect（@MainActor ObservableObject）
├── SectionView.swift   剖面显示（NSViewRepresentable + 双向滚轮平移/捏合/点击选道/右键框选缩放/光标）
├── ScrollBar.swift     自绘水平/垂直滚动条 + ScrolledSection 包裹布局
├── HeaderInspector.swift 道头表格（字节位置 + 值）
├── L10n.swift           语言状态（UserDefaults 持久化）+ errorMessage 渲染
├── MainMenuLocalizer.swift 遍历 NSApp.mainMenu 重命名（系统项按 selector、其余按标题反查）
├── HelpWindow.swift     双语使用说明窗口（HelpView + HelpMenuButton，⌘?）
└── CompareLayout.swift  多文件并排（HSplitView 可拖动分隔）

SegyKitTests（自定义 harness 可执行目标，非 XCTest）
├── Harness.swift      @MainActor 断言工具（check/checkClose/checkRel/finish）
└── main.swift         全部测试入口
```

关键设计：渲染是纯函数 `(SegyFile, Viewport) → CGImage`；`Viewport` 是 `Equatable + Sendable` 纯值类型。

---

## 构建 / 测试 / 运行 / 发布

```bash
swift build                       # 构建 4 个 target（SegyKit / Localization / SegyKitTests / SeisView）
swift run SeisView                # 直接运行
swift run SegyKitTests            # 跑测试（当前 207 断言，非零退出码 = 失败）

./scripts/make_app.sh             # 快速打当前架构的 .app
./scripts/release.sh [版本号]      # 通用二进制 + dmg + zip（产出在 dist/）

# 真实文件黄金测试 + 性能回归（未设则跳过）：
SEGY_BIG_FILE=/path/to/big.segy swift run SegyKitTests

# 重新生成图标：
swift scripts/make_icon.swift && iconutil -c icns Resources/SeisView.iconset -o Resources/SeisView.icns
```

环境：macOS 13+，Swift 6.0+。**只需 Command Line Tools，不需要完整 Xcode**（纯 Swift + SwiftPM、零第三方依赖，无 Xcode 工程与资源 bundle，构建/测试/打包全走命令行；`notarytool`/`stapler`/`hdiutil` 都可用）。

---

## 关键技术事实（改代码前必读）

### SEG-Y 字节偏移（二进制头 slice `raw[0]` = 文件字节 3200，即 1-indexed 字节 − 3201）

| 字段 | 1-indexed | raw 下标 |
|---|---|---|
| dt（微秒） | 3217–3218 | raw[16..17] |
| ns（每道采样数） | 3221–3222 | raw[20..21] |
| 数据格式码 | 3225–3226 | raw[24..25] |
| SEG-Y 版本 | 3501–3502 | raw[300..301] |
| 定长道标志 | 3503–3504 | raw[302..303] |
| 扩展文本头数 | 3505–3506 | raw[304..305] |

道头（`p` 指向 240 字节道头起始）：道序 = u32(p+0)、FFID = u32(p+8)、CDP = u32(p+20)、偏移距 = u32(p+36)、ns = u16(p+114)、dt = u16(p+116)。

> 坑：`raw[300..305]` 曾错写成 `raw[100..105]`（3501−3201=300 算成 100），导致扩展头文件几何错乱。这是最容易再犯的错误。

### IBM 浮点解码

`value = sign × mantissa × 2^(4E − 280)`，其中 E = 7 位指数、mantissa = 24 位尾数；mantissa==0 → 0。用 128 项 `expTable` 预计算 2^(4e−280)。

### 格式码与字节序

支持 1=IBM32、2=int32、3=int16、5=IEEE32、8=int8。格式码高字节 0x8000 表示 rev2 小端。**假 IBM 真 IEEE**：声明 IBM 但实际存 IEEE 时，首道样本按两种方式各解一遍、比较「有限且在 [1e-6,1e6] 内」的比例，IEEE 明显更合理（>3×）则自动校正，存 `formatWasCorrected`。

### ns 冲突启发式

二进制头 ns 与首道道头 ns 不一致时，**取与文件大小整除吻合的那个**，都吻合/都不吻合时以二进制头为准（SEG-Y rev1 权威字段）。真实文件道头 ns 可能不可靠。

### min/max 分箱是「正确性」不是「性能」

4000 采样点压进 800 px 时若隔点取样会混叠、剖面严重失真。每个像素 bin 必须取 (min, max)（Decimator），Rasterizer 用**主振幅** `abs(mx)>=abs(mn) ? mx : mn` 而非中点。

### 变长道检测

道数 = (文件大小 − 首道偏移) / 道长，**必须整除**；除不尽 → 明确报错（修掉 SeiSee 静默错乱的缺陷）。`extOffset` 之前必须 `guard size >= extOffset`（防 UInt64 下溢）。

---

## Swift 6 严格并发 / 测试约定

- **本机只有 Command Line Tools，无 XCTest / Swift Testing**，测试用自定义 `SegyKitTests` 可执行目标。勿 `import XCTest`/`import Testing`。
- 顶层可变全局状态必须封在 `@MainActor` 类型里（`Harness`）。
- `TraceReader` 并行读用 `@unchecked Sendable BufferRef` 包装输出指针（各线程只写互不重叠的道区间，构造上安全）；`SegyFile` 未标 `Sendable`（init 后不可变，但跨并发域传不过去），`buildShots` 在 `Task.detached` 里重新 open 文件以绕开严格并发限制。
- `DocumentModel` 是 `@MainActor`；炮索引构建 `buildShots` 用 `Task.detached` 后台跑（`ShotIndex.build` 是 SegyKit 非 actor 类型的 static 纯函数），渲染仍在主线程同步做。
- `Viewport` 必须**整体重新赋值**触发 `@Published`（`var v = viewport; v.pan(...); viewport = v`），原地改字段不会发 objectWillChange。

---

## 渲染与性能

- **viewport-only I/O**：`renderDecode` 钳 `span = min(max(1, traceSpan), n)`、`traceSpan` 默认 1200，绝不一次解码整文件/整炮。
- **整道大块读**：`readDecoded` 在 `sampleRange == nil`（横向平移常态）时，一次 `pread` 读整个分区（含 240 道头）再逐道解码；纵向缩放（`sampleRange != nil`）仍按道 `pread`。
- **两级缓存**（`DocumentModel`）：`imageCache` 按 url 分桶、键为完整 viewport；`binnedCache` 键只含几何（`firstTrace/traceSpan/firstSample/sampleSpan`），**不含增益**。拖百分比滑块时几何未变，直接复用分箱结果，跳过 pread + 解码。按 url 分桶还修掉了对比模式下单条缓存被多个文件互相顶掉、永远 miss 的抖动。
- **渲染是同步的、在 SwiftUI body 里**。曾尝试异步 + 防抖（`3123494`），因图像追不上手势、左右都变卡而被 `git revert`（`567016e`）回退。**不要轻易再上异步渲染**。
- 左右滚动不对称：向右 = 文件向后顺序读 + OS readahead 预取，快；向左 = 向回读冷页，慢。大块读已缩小差距，但向左客观上仍稍慢，属已知。
- 性能实测（M5/16GB，9.57GB 文件）：8 线程冷读 21.6ms、热读 2.5ms、IBM 解码 1.2ms(≈1.6GB/s)。瓶颈在 I/O，不在解码。

---

## 已知限制 / 未做（保持诚实，README 别写过头）

- 无 Wiggle 波形显示（仅变密度）
- ShotIndex 无 spec 里的「多炮区间退化为线性全扫」回退——单炮 < 256 道的文件会漏边界（目标数据单炮 ~2 万道，安全）
- 触控板滚动：横向→道号平移、纵向→采样平移（方向符号已按用户习惯反转）；采样平移仅纵向缩放（`sampleSpan>0`）后可用，全采样铺满时纵向无可滚余量
- 垂直滚动条只在纵向缩放后（`sampleSpan>0`）可用；默认全采样铺满时无可滚余量，呈禁用态
- 对比模式渲染仍是同步的（未异步）
- 对比 = 单文件打开后，「对比…」**单选追加**一个文件、并排显示（**无叠加模式**，`CompareMode` 只有 `.single`/`.sideBySide`）；所有 pane 共享 viewport，滚动/缩放/对齐天然联动；并排 pane 用 `HSplitView`（分隔条可拖动调整宽度）
- 道/时间缩放滑块是**相对缩放 + 松手回中**：左拖放大、右拖缩小，效果保留、把手回中点；跨 `sampleSpan==0`（全采样）与窗口化时用连续乘算避免跳变
- 缩放滑块在**正文顶部 `ZoomBar`**（不在工具栏，避免两个 Slider 被并进同一工具栏槽）；**拖动期间只动把手、不触发渲染，松手才应用一次缩放**——否则拖动时每个 tick 都改 viewport → 整段重解码，卡死主线程
- 无频谱、图片导出、数据写回
- 未 Apple 公证（免费路，ad-hoc 签名；接收方首次右键→打开）

---

## 常见坑（future dev 备忘）

- **NSOpenPanel 别用 `allowedContentTypes = [UTType(filenameExtension: "sgy")...]`**：自定义扩展名的动态 UTType 跟文件实际类型对不上，会把 .sgy/.segy 全部置灰。干脆不设过滤，靠 `SegyFile.open` 校验。
- **Finder 双击打开靠 `.onOpenURL`**（挂在 WindowGroup 内容上）。`Info.plist` 的 `CFBundleDocumentTypes` 只是声明「能打开」，真正接文件的是 `.onOpenURL`；没有它，双击/`open -a` 都会静默无效。别用 `DocumentGroup`——那会改整个文件模型。
- `Package.swift` 声明了 `SeisView` 可执行 target，但 `@main` 在 `SeisViewApp.swift`——模块里不能同时有 `main.swift` 顶层代码。
- 增益/调色板在 `Viewport` 里，改它们也要整体重赋值 `viewport` 才能触发重渲染。
- **Picker 的 tag 绝不能写死带载荷的 enum case**。曾经 `.tag(GainMode.percentiles(0.01, 0.99))`，百分比一可调，`selection` 就匹配不上任何 tag、控件变空白。改为绑 `GainKind`（去掉载荷的种类），载荷由 `Viewport.setGainKind` 用记住的参数重建。
- 百分比的真值只有 `Viewport.clipPercent` 一个，`gain` 的百分位载荷由它派生（`setClipPercent`）。别再单独改 `gain` 的载荷，否则两者漂移。
- 视口越界钳制统一在 `Viewport.decodePlan` 里（纯函数、有测试）。别在 `DocumentModel` 里另写一份。
- **NSViewRepresentable 的 `@Published` 状态要作为值参数传入**（如 `SectionView.zoomRectMode`）：只在 `updateNSView` 里读 `model.xxx`，SwiftUI 会因「输入没变」跳过 `updateNSView`，视图层收不到状态变化。
- **双指点击 = 右键**：`rightMouseDown/rightMouseDragged/rightMouseUp`（macOS 触控板「辅助点按」即右键）。
- **`traceSpan` 上限 1200 统一在 `Viewport` 层夹**（`decodePlan` 与 `zoomTraces(to:)` 都要夹）；漏夹会让缩放滑块松手整文件解码、卡死主线程。
- 配色是 256×3 LUT（对照标准 `seismic(iop)`），端点颜色有测试；加配色别只改 `color(for:t:)` 的线性分支，要同步加 LUT。
- 提交信息也要遵守保密约束（扫历史、不只扫工作树）。
- **新增任何用户可见文案必须先在 `S` 枚举里加 case，再补齐 `zhTable`/`enTable` 两张表**。漏一边会被 `SegyKitTests` 的完整性断言当场抓住；带占位符的文案两语 `%@` 个数必须相同，否则状态栏参数错位。
- **菜单栏本地化走 AppKit 而非 SwiftUI**：`.commands` 在 macOS 13 上响应 `@Published` 重建菜单并不可靠，改由 `MainMenuLocalizer` 遍历 `NSApp.mainMenu` 重命名。系统项按 `action` selector 认（selector 不随语言变），其余按标题在中英两表里反查；两类都认不出的项一律不动。启动时的那次 `apply` 必须 `DispatchQueue.main.async` 延后一轮，否则菜单栏还没建好。
- **`DocumentModel.error` 存的是错误值不是字符串**：文案在视图层按当前语言渲染。别图省事改回存成品字符串——那样切语言时已显示的报错不会跟着变。

---

## 决策记录（精简）

历史关键决策（完整 18 条见已清理的 SDD ledger，此处只留对后续开发有影响的）：

1. 仓库根 = `SeisView/`，SwiftPM 包名 SeisView，分支 `main`。
2. 测试用自定义 harness（非 XCTest，CLT 无测试框架）。
3. 修过 3 处 SEG-Y 字节偏移 bug（dt/ns 读反、定长标志偏移、rev/fixed/ext 短 200 字节）。
4. ns 冲突用「文件大小整除」判据（真实文件道头 ns 不可靠）。
5. `renderDecode` 钳 traceSpan≤1200（修复默认解码全文件 OOM）。
6. 整道大块读优化（修复左滚慢）。
7. 异步渲染尝试后回退（图像追不上手势）。
8. 假 IBM 自动校正用 sanity 阈值（小振幅才能触发，测试数据需用 `Float(s)*1e-4` 而非 `Float(s)`）。
9. 打包走免费路：通用二进制 + ad-hoc 签名 + dmg/zip；公证留待有 Developer ID 后再加。
10. 对比 pane 改 `HSplitView` 可拖动分隔（替换 GeometryReader 均分，修宽度被图像内在尺寸撑偏）。
11. 配色收敛为 4 种 LUT：灰度 / 红白蓝 / 红白黑 / 棕白黑（删去旧「地震/自定义」名）。
12. 局部放大用右键（双指点击）框选；`zoomRectMode` 作为 `SectionView` 值参数传入，松手 `zoomToRect` 放大并退出。
13. 触控板滚动改双向平移（横向→道号、纵向→采样），方向按用户习惯反号。
