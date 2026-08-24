import SwiftUI
import AppKit

struct SectionView: NSViewRepresentable {
    let image: CGImage?
    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.imageScaling = .scaleAxesIndependently
        return v
    }
    func updateNSView(_ v: NSImageView, context: Context) {
        v.image = image.map { NSImage(cgImage: $0, size: NSSize(width: CGFloat($0.width), height: CGFloat($0.height))) }
    }
}
