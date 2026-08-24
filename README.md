# SeisView — macOS SEG-Y 地震数据查看器

对标 Windows 的 SeiSee，核心是超大 SEG-Y 文件（10 GB 级、数十万道）的高效显示。原生 Swift，零第三方依赖。

## 功能

- 变密度剖面显示（灰度 + seismic 蓝白红调色板）
- 横向平移、纵向缩放、增益（百分位 / AGC / 每道 / 最大幅值）
- 道头检查器（FFID / 道序 / CDP / 偏移距 / 采样数等，含字节位置）
- 按炮（FFID）导航
- 多文件对比：并排 + 叠加（如去噪前后、input + mask）
- 假 IBM 真 IEEE 自动校正

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
