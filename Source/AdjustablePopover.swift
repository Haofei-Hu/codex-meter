import AppKit

// Keep the complete native blur, chrome and mask at every slider value.
// Appearance controls change the content's matte veil, never effect alpha.
final class AdjustablePopover: NSPopover, NSPopoverDelegate {
    var glassAppearance = GlassAppearance.system {
        didSet { if oldValue != glassAppearance { refreshGlassAppearance() } }
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
        appearance = glassAppearance.theme.nativeAppearance ?? NSApp.effectiveAppearance
        guard let content = contentViewController?.view, content.window != nil else { return false }
        var ancestor = content.superview
        while let view = ancestor {
            if let effect = view as? NSVisualEffectView {
                effect.state = .active
                return true
            }
            ancestor = view.superview
        }
        return false
    }
}
