import AppKit
import SwiftUI

struct ResizeGrip: NSViewRepresentable {
    @ObservedObject var model: QuotaModel
    func makeNSView(context: Context) -> CornerResizeView { CornerResizeView() }
    func updateNSView(_ view: CornerResizeView, context: Context) {
        view.currentScale = { model.cardScale }
        view.onResize = { model.setScale($0) }
    }
}
final class CornerResizeView: NSView {
    var currentScale: () -> Double = { 1 }
    var onResize: (Double) -> Void = { _ in }
    private var startMouse = NSPoint.zero
    private var startScale = 1.0
    private var baseHeight = 274.0
    override var mouseDownCanMoveWindow: Bool { false }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        toolTip = "拖动右下角调整大小"
        setAccessibilityElement(true)
        setAccessibilityLabel("拖动右下角调整大小")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.5).setStroke()
        for offset in [0.0, 5.0, 10.0] {
            let path = NSBezierPath()
            path.lineWidth = 1.5; path.lineCapStyle = .round
            path.move(to: NSPoint(x: bounds.maxX - 7 - offset, y: bounds.maxY - 6))
            path.line(to: NSPoint(x: bounds.maxX - 6, y: bounds.maxY - 7 - offset))
            path.stroke()
        }
    }
    override func mouseDown(with event: NSEvent) {
        startMouse = NSEvent.mouseLocation
        startScale = currentScale()
        baseHeight = (window?.frame.height ?? 274) / startScale
    }
    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        let dx = (point.x - startMouse.x) / 332
        let dy = (startMouse.y - point.y) / baseHeight
        onResize(startScale + (abs(dx) >= abs(dy) ? dx : dy))
    }
}
