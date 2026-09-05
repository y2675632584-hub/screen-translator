import AppKit

struct TranslatedRegion: Equatable {
    let region: TextRegion
    let translation: String
}

final class OverlayView: NSView {
    var regions: [TranslatedRegion] = [] {
        didSet { if oldValue != regions { needsDisplay = true } }
    }
    var fontScale: CGFloat = 1
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        for item in regions {
            let original = TextAnalysis.screenRect(item.region.bounds, size: bounds.size)
            let box = original.insetBy(dx: -2, dy: -2).intersection(bounds)
            guard box.width > 4, box.height > 4 else { continue }
            NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
            NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2).fill()
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            let text = item.translation as NSString
            var size = min(24, max(10, original.height * 0.78)) * fontScale
            var attributes: [NSAttributedString.Key: Any] = [:]
            let textBox = box.insetBy(dx: 2, dy: 1)
            while true {
                attributes = [.font: NSFont.systemFont(ofSize: size, weight: .medium),
                              .foregroundColor: NSColor.white, .paragraphStyle: paragraph]
                let measurement = text.boundingRect(with: CGSize(width: textBox.width, height: 1000),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
                if measurement.height <= textBox.height || size <= 8 { break }
                size -= 0.5
            }
            NSGraphicsContext.saveGraphicsState()
            textBox.clip()
            text.draw(with: textBox, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

@MainActor
final class OverlayController {
    private var panel: NSPanel?
    private var canvas: OverlayView?

    func prepare(screen: NSScreen, fontScale: Double) {
        close()
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let view = OverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.fontScale = fontScale
        panel.contentView = view
        self.panel = panel
        self.canvas = view
        // Register the empty transparent window before enumerating capture sources.
        panel.orderFrontRegardless()
    }

    func show(_ regions: [TranslatedRegion]) {
        canvas?.regions = regions
        if regions.isEmpty {
            if panel?.isVisible == true { panel?.orderOut(nil) }
        } else if panel?.isVisible != true {
            panel?.orderFrontRegardless()
        }
    }
    func clear() { canvas?.regions = []; panel?.orderOut(nil) }
    func close() { panel?.close(); panel = nil; canvas = nil }
}
