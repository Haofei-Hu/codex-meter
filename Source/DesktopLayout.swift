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

// Layout markers do not consume clicks. The panel routes dragging before
// SwiftUI/NSScrollView can swallow a background mouse-down in an inactive app.
struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragView { WindowDragView() }
    func updateNSView(_ view: WindowDragView, context: Context) {}
}
struct WindowControlRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowControlView { WindowControlView() }
    func updateNSView(_ view: WindowControlView, context: Context) {}
}
class WindowRegionView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func containsWindowPoint(_ point: NSPoint) -> Bool {
        let local = convert(point, from: nil)
        return !isHiddenOrHasHiddenAncestor && bounds.contains(local) && visibleRect.contains(local)
    }
}
final class WindowDragView: WindowRegionView {}
final class WindowControlView: WindowRegionView {}

final class DesktopPanel: NSPanel {
    private var startPointer: NSPoint?
    private var startOrigin: NSPoint?
    private(set) var userDragging = false
    var dragEnded: (() -> Void)?
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    init(cardFrame: NSRect) {
        super.init(contentRect: cardFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "Codex Meter"; isOpaque = false; backgroundColor = .clear; hasShadow = true
        hidesOnDeactivate = false; isReleasedWhenClosed = false
        // Use a normal window behind apps, above Finder's desktop surfaces.
        // Moving uses our own event sequence, not AppKit's background drag path.
        level = .normal; isMovable = false; isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func canDragDesktop(at point: NSPoint) -> Bool {
        guard let contentView, contentView.bounds.contains(contentView.convert(point, from: nil)) else { return false }
        var hit = contentView.hitTest(contentView.convert(point, from: nil))
        while let view = hit {
            if view is NSControl || view is CornerResizeView { return false }
            hit = view.superview
        }
        var draggable = false, blocked = false
        func visit(_ view: NSView) {
            if let region = view as? WindowRegionView, region.containsWindowPoint(point) {
                if region is WindowControlView { blocked = true }
                if region is WindowDragView { draggable = true }
            }
            if let grip = view as? CornerResizeView, !grip.isHiddenOrHasHiddenAncestor,
               grip.bounds.contains(grip.convert(point, from: nil)), grip.visibleRect.contains(grip.convert(point, from: nil)) { blocked = true }
            for child in view.subviews { visit(child) }
        }
        visit(contentView)
        return draggable && !blocked
    }
    func beginDesktopDrag(at screenPoint: NSPoint) {
        startPointer = screenPoint; startOrigin = frame.origin; userDragging = true
    }
    func moveDesktopDrag(to screenPoint: NSPoint) {
        guard userDragging, let startPointer, let startOrigin else { return }
        setFrameOrigin(NSPoint(x: startOrigin.x + screenPoint.x - startPointer.x,
                               y: startOrigin.y + screenPoint.y - startPointer.y))
    }
    func endDesktopDrag() {
        guard userDragging else { return }
        userDragging = false; startPointer = nil; startOrigin = nil
        if !frameAutosaveName.isEmpty { saveFrame(usingName: frameAutosaveName) }
        dragEnded?()
    }
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown where canDragDesktop(at: event.locationInWindow):
            beginDesktopDrag(at: convertPoint(toScreen: event.locationInWindow)); return
        case .leftMouseDragged where userDragging:
            moveDesktopDrag(to: convertPoint(toScreen: event.locationInWindow)); return
        case .leftMouseUp where userDragging:
            moveDesktopDrag(to: convertPoint(toScreen: event.locationInWindow)); endDesktopDrag(); return
        default: super.sendEvent(event)
        }
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
