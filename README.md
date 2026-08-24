# SeisView — macOS SEG-Y 地震数据查看器

对标 Windows 的 SeiSee，核心是超大 SEG-Y 文件（10 GB 级、数十万道）的高效显示。原生 Swift，零第三方依赖。

## 功能

- 变密度剖面显示（灰度 + seismic 蓝白红调色板）
- 横向平移、纵向缩放、增益（百分位 / AGC / 每道 / 最大幅值）
- 道头检查器（FFID / 道序 / CDP / 偏移距 / 采样数等，含字节位置）
- 按炮（FFID）导航
- 多文件对比：并排 + 叠加（如去噪前后、input + mask）
- 假 IBM 真 IEEE 自动校正

## 为什么快

快的根本原因不是算得快，而是**几乎什么都不读**：

- **O(1) 随机寻址** —— SEG-Y 定长记录布局下第 i 道偏移可直接算出，打开 10 GB 文件只需读 3600 字节头部，道数由文件大小推算，不做全文件扫描
- **只读视口内的道** —— 屏幕宽 1200 px 就最多取 1200 道，与文件总道数无关
- **并行 pread** —— 每线程独立 fd，`pread` 无状态天生线程安全，8 线程近线性加速
- **缩放交给系统** —— 8 位索引位图 + 调色板 LUT，缩放走纹理采样不重算数据

实测（Apple M5 / 16 GB，9.57 GB 文件、589,248 道、ns=4000、IBM 格式，`F_NOCACHE` 强制冷读）：

| 场景 | 耗时 |
|---|---|
| 1 线程冷读一屏 | 116.7 ms |
| 8 线程冷读一屏 | **21.6 ms** |
| 8 线程页缓存命中 | **2.5 ms** |
| 纯 IBM 解码（200 万采样） | 1.2 ms（≈1.6 GB/s） |

解码耗时占比不足 2%，瓶颈完全在 I/O —— 所以不需要预转换文件，也不需要 GPU 解码。

炮索引另有优化：朴素线性扫描 589,248 个道头需约 57 秒，改用跳跃抽样 + 边界二分后读取次数降约 30 倍，8 线程下 < 1 秒，结果按 `路径+大小+mtime` 落盘缓存。

**纵向 min/max 分箱是正确性要求，不是性能优化** —— 4000 采样点压入 800 px 时若隔点取样会产生混叠，剖面形态严重失真。

## 健壮性

与 SeiSee 的关键差异：**遇到畸形文件明确报错，绝不静默显示错误图像。**

- **变长道** —— 整除校验 + 抽样一致性检查（定长道标志常被写方疏于维护，故不盲信），不一致则报错而非错乱显示
- **假 IBM 真 IEEE** —— 两种格式各试解一批采样比较分布合理性，自动择优并在状态栏标注「格式已自动校正」
- **扩展文本头** —— 按字节 3505–3506 修正首道偏移
- **小端变体** —— 格式码非法时尝试小端解析
- **手动覆盖** —— 可强制指定 ns / 格式码 / 字节序

支持的数据样本格式码：1（4 字节 IBM 浮点）、2（4 字节整型）、3（2 字节整型）、5（4 字节 IEEE 浮点）、8（1 字节整型）。

## 架构

`SegyKit` 零 UI 依赖，可用命令行跑真实文件回归测试，不必靠肉眼验证界面。渲染是 `(SegyFile, Viewport) → Image` 的纯函数，任意一帧可在测试中精确复现。

```
SegyKit（纯核心，可独立测试）
├── SegyFile      文件打开、头解析、几何推断与校验
├── TraceReader   并行 pread + 样本解码
├── ShotIndex     FFID 炮索引构建与磁盘缓存
├── Decimator     LOD 降采样（min/max 分箱）
└── Rasterizer    振幅 → 8bit 索引 → 调色板 LUT → CGImage

SeisView.app（AppKit + SwiftUI）
├── DocumentModel   已开文件集合 + 视口状态
├── SectionView     剖面绘制
├── HeaderInspector 道头表格
└── CompareLayout   并排 / 叠加
```

需要 macOS 13+ 和 Swift 6.0+（Command Line Tools 即可，**不需要完整 Xcode**）。着色器为运行时编译，代价仅启动时数十毫秒。

## 开发构建

```bash
swift run SeisView           # 直接运行
./scripts/make_app.sh        # 快速打当前架构的 .app
```

## 发布打包（通用二进制）

```bash
./scripts/release.sh [版本号]   # 默认 0.1.0
```

产出在 `dist/`：

- `SeisView.app` — 通用二进制（Apple Silicon + Intel 都能跑）
- `SeisView-<版本>.dmg` — 磁盘映像，推荐分发
- `SeisView-<版本>.zip`

重新生成图标：`swift scripts/make_icon.swift && iconutil -c icns Resources/SeisView.iconset -o Resources/SeisView.icns`

## 安装（接收方）

1. 打开 `.dmg`，把 `SeisView.app` 拖进「应用程序」。
2. **首次打开**：由于未做 Apple 公证（免费构建，无 Developer ID），macOS Gatekeeper 会拦截。右键点击 app →「打开」→ 再点「打开」即可；之后正常双击打开。

   或者用命令去除隔离标记：`xattr -d com.apple.quarantine /Applications/SeisView.app`

> 若要彻底免去首次拦截，需 Apple 开发者账号（$99/年）做签名 + 公证。届时在 `scripts/release.sh` 里把 `codesign --sign -` 换成 Developer ID 签名，再加 `notarytool submit` + `stapler staple`。

## 已知限制

- 无 Wiggle 波形显示（仅变密度）
- 炮索引对「单炮小于 256 道」的文件可能漏边界（目标数据炮道数远大于 256，安全）
- 无频谱、图片导出、数据写回

## 许可证

[MIT License](LICENSE.md) © 2026 Tianxiang Gao

可自由使用、修改、分发、商用，唯一义务是保留版权声明与许可声明。
