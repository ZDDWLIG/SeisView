import Foundation

/// 剖面横向排列方式。放进 Viewport，参与缓存区分与渲染路径选择。
public enum TraceOrder: Equatable, Sendable {
    case byTrace    // 文件顺序 / 道号（现状）
    case byOffset   // 炮间炮序、炮内 offset 升序
}
