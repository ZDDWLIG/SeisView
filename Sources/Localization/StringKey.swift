import Foundation

/// 全部界面文案的 key。用枚举而非字符串：拼错编译不过，漏翻译由测试当场抓出。
/// 新增任何用户可见文案都必须先在这里加 case，再在 zhTable/enTable 两张表里补齐。
public enum S: String, CaseIterable, Sendable {
    // 菜单（我们自己的）
    case menuFileOpen, menuFileCompare
    case menuView, menuViewReset, menuViewHeaderToggle, menuViewLanguage
    case menuLangChinese, menuLangEnglish
    case menuNav, menuNavPrevShot, menuNavNextShot
    case menuHelpUsage

    // 菜单（macOS 系统生成，由 MainMenuLocalizer 重命名）
    case sysMenuFile, sysMenuEdit, sysMenuWindow, sysMenuHelp
    case sysAbout, sysServices, sysHide, sysHideOthers, sysShowAll, sysQuit
    case sysUndo, sysRedo, sysCut, sysCopy, sysPaste, sysDelete, sysSelectAll
    case sysCloseWindow, sysMinimize, sysZoom, sysBringAllToFront

    // 工具栏
    case tbGain, gainPercentiles, gainAGC, gainPerTrace, gainMaxAbs, tbGainHelp
    case tbClipHelp
    case tbPalette, paletteGray, paletteRedWhiteBlue, paletteRedWhiteBlack, paletteBrownWhiteBlack, paletteWiggle
    case tbOrder, orderByTrace, orderByOffset, orderByOffsetAbs
    case tbHeaderToggle, tbHeaderToggleHelp
    case tbZoomRect, tbZoomRectHelp
    case tbVelocity, tbVelocityHelp, velocityLabel
    case tbSingleTrace, tbSingleTraceHelp
    case tbAlign, tbAlignHelp
    case tbReset, tbResetHelp
    case tbPrevShot, tbPrevShotHelp, tbNextShot, tbNextShotHelp

    // 单道波形弹窗
    case singleTraceTitle, singleTraceAxisTime, singleTraceAxisAmp

    // 振幅谱弹窗
    case tbSpectrum, spectrumLocal, spectrumGlobal, spectrumTitle
    case spectrumXAxis, spectrumYAxis, spectrumXRange, spectrumYRange
    case spectrumNormalize, spectrumAuto, spectrumUnitHz

    // 缩放条
    case zoomTraceAxis, zoomTraceAxisHelp, zoomTimeAxis, zoomTimeAxisHelp

    // 状态栏（含占位符）
    case statusTraces, statusPositions, statusSamples, statusTraceSpan, statusCursor
    case statusShotCount, statusShotCurrent, statusShotBuilding, statusCursorNone

    // 空态
    case emptyOpenHint

    // 道头检查器
    case hdrTitle, hdrTraceLabel, hdrEmptyHint
    case hdrTraceSeq, hdrFFID, hdrCDP, hdrOffset, hdrNs, hdrDt

    // 错误
    case errFileTooSmall, errInvalidFormatCode, errNonIntegerTraceCount, errBadSampleCount
    case errUnknown, errAlreadyComparing, errOpenFailed

    // Help 窗口外壳
    case helpWindowTitle
}
