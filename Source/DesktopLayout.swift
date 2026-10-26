import AppKit
import SwiftUI

struct DesktopCardLayout {
    let scale: CGFloat
    let visibleHeight: CGFloat
    let frame: NSRect
}
func desktopCardLayout(naturalHeight: CGFloat, requestedScale: Double, visibleFrame area: NSRect, currentFrame: NSRect) -> DesktopCardLayout {
    let availableWidth = max(1, area.width - 16), availableHeight = max(1, area.height - 16)
    let desired = max(0.75, min(1.6, requestedScale))
    let scale = min(desired, availableWidth / 332, max(0.75, availableHeight / max(1, naturalHeight)))
    let height = min(naturalHeight, availableHeight / scale)
    let size = NSSize(width: 332 * scale, height: height * scale)
    let x = max(area.minX + 8, min(currentFrame.minX, area.maxX - size.width - 8))
    let top = min(area.maxY - 8, max(area.minY + size.height + 8, currentFrame.maxY))
    return DesktopCardLayout(scale: scale, visibleHeight: height, frame: NSRect(x: x, y: top - size.height, width: size.width, height: size.height))
}

// Explicit native drag handling works inside SwiftUI hosting views and scroll views.
struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragView { WindowDragView() }
    func updateNSView(_ view: WindowDragView, context: Context) {}
}
final class WindowDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let panel = window as? DesktopPanel
        panel?.userDragging = true
        defer { panel?.userDragging = false; panel?.dragEnded?() }
        window.performDrag(with: event)
    }
}
func testDesktopCardLayout() {
    for area in [NSRect(x: 0, y: 25, width: 1440, height: 850), NSRect(x: -1440, y: 0, width: 1024, height: 600)] {
        for height in [420.0, 560.0, 900.0, 1800.0] {
            for scale in [0.75, 1, 1.25, 1.6] {
                let fit = desktopCardLayout(naturalHeight: height, requestedScale: scale, visibleFrame: area, currentFrame: NSRect(x: area.maxX - 30, y: area.maxY - 20, width: 332, height: 274))
                precondition(area.insetBy(dx: 7.9, dy: 7.9).contains(fit.frame))
                precondition(fit.visibleHeight <= height && fit.scale <= scale)
            }
        }
    }
    print("PASS: native desktop fit, Plus/Pro heights, overflow and multiple displays")
}
