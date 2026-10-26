import AppKit

// Let AppKit keep native positioning, dismissal and animation. The hosting
// view draws the same complete blur as the desktop card. Suppress AppKit's
// additional background so it cannot cap the custom transparency range.
final class AdjustablePopover: NSPopover, NSPopoverDelegate {
    var glassAppearance = GlassAppearance.system {
        didSet { refreshGlassAppearance() }
    }
    private let clearMask = NSImage(size: NSSize(width: 1, height: 1), flipped: false) { rect in
        NSColor.clear.setFill(); rect.fill(using: .copy); return true
    }
    override init() {
        super.init()
        delegate = self
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }
    func popoverWillShow(_ notification: Notification) { refreshGlassAppearance() }
    func popoverDidShow(_ notification: Notification) { refreshGlassAppearance() }
    @discardableResult func refreshGlassAppearance() -> Bool {
        let desired = glassAppearance.theme.nativeAppearance ?? NSApp.effectiveAppearance
        if appearance?.name != desired.name { appearance = desired }
        guard let content = contentViewController?.view, let window = content.window else { return false }
        var ancestor = content.superview
        while let view = ancestor {
            if let effect = view as? NSVisualEffectView {
                // This masks only the native material, not the content. The
                // content owns a permanently opaque-alpha HUD blur beneath its
                // entire visible surface, including at 200% transparency.
                effect.maskImage = clearMask
                for decoration in effect.subviews where decoration !== content && !content.isDescendant(of: decoration) {
                    decoration.isHidden = true
                }
                window.hasShadow = false
                return true
            }
            ancestor = view.superview
        }
        return false
    }
}
