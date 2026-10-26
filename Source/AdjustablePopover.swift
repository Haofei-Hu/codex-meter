import AppKit

// Keep NSPopover's positioning, arrow, dismissal and animation. Only its
// decorative background is faded; never change the window/hosting-view alpha.
final class AdjustablePopover: NSPopover, NSPopoverDelegate {
    var glassAppearance = GlassAppearance.system {
        didSet { if oldValue != glassAppearance { refreshGlassAppearance() } }
    }
    private var backdrop: PopoverBackdropState?
    override init() {
        super.init()
        delegate = self
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }
    func popoverWillShow(_ notification: Notification) { refreshGlassAppearance(force: true) }
    func popoverDidShow(_ notification: Notification) { refreshGlassAppearance(force: true) }
    @discardableResult func refreshGlassAppearance(force: Bool = false) -> Bool {
        guard let content = contentViewController?.view, content.window != nil else { return false }
        var ancestor = content.superview
        var effect: NSVisualEffectView?
        while let view = ancestor {
            if let visual = view as? NSVisualEffectView { effect = visual; break }
            ancestor = view.superview
        }
        guard let effect else { return false }
        if backdrop?.effect !== effect { backdrop = PopoverBackdropState(effect: effect, content: content) }
        backdrop?.apply(frost: glassAppearance.frost, content: content, force: force)
        return true
    }
}

private final class PopoverDecoration {
    weak var view: NSView?
    let alpha: CGFloat
    init(_ view: NSView) { self.view = view; alpha = view.alphaValue }
}
private final class PopoverBackdropState {
    weak var effect: NSVisualEffectView?
    let originalMask: NSImage?
    var decorations: [PopoverDecoration]
    private var lastFrost: Double?
    init(effect: NSVisualEffectView, content: NSView) {
        self.effect = effect
        originalMask = effect.maskImage
        // AppKit's effect view may have separate glass/arrow decoration views.
        // Locate those through public view relationships, without class names,
        // KVC, private filters, or touching the subtree that contains content.
        decorations = effect.subviews.filter { $0 !== content && !content.isDescendant(of: $0) }.map(PopoverDecoration.init)
    }
    func apply(frost: Double, content: NSView, force: Bool) {
        guard let effect else { return }
        let children = effect.subviews.filter { $0 !== content && !content.isDescendant(of: $0) }
        let added = children.filter { child in !decorations.contains { $0.view === child } }
        decorations.append(contentsOf: added.map(PopoverDecoration.init))
        guard force || !added.isEmpty || lastFrost != frost else { return }
        lastFrost = frost
        for decoration in decorations { decoration.view?.alphaValue = decoration.alpha * frost }
        if frost == 1 { effect.maskImage = originalMask; return }
        let original = originalMask
        let size = original?.size ?? NSSize(width: 1, height: 1)
        effect.maskImage = NSImage(size: size, flipped: false) { rect in
            if let original { original.draw(in: rect, from: .zero, operation: .sourceOver, fraction: frost) }
            else { NSColor.white.withAlphaComponent(frost).setFill(); rect.fill() }
            return true
        }
    }
}
