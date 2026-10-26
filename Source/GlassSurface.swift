import AppKit
import SwiftUI

let glassSecondary = Color.secondary
let glassTertiary = Color(nsColor: .tertiaryLabelColor)
var nativeLiquidGlassAvailable: Bool {
    #if compiler(>=6.2)
    if #available(macOS 26.0, *) { return true }
    #endif
    return false
}

// Never fade a behind-window blur: doing so exposes sharp underlying text.
struct GlassBackdrop: NSViewRepresentable {
    let cornerRadius: CGFloat
    let appearance: GlassAppearance
    func makeNSView(context: Context) -> GlassBackdropContainer {
        let container = GlassBackdropContainer()
        let view = container.backdrop
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return container
    }
    func updateNSView(_ container: GlassBackdropContainer, context: Context) {
        let view = container.backdrop
        view.layer?.cornerRadius = cornerRadius
        view.alphaValue = 1
        view.appearance = appearance.theme.nativeAppearance
        view.density.alphaValue = appearance.densityOpacity
        view.matte.alphaValue = appearance.toneOpacity
        view.matte.needsDisplay = true
        view.needsLayout = true
        container.needsLayout = true
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), let glass = view.liquidGlass as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
            glass.style = appearance.transparency > 1 ? .clear : .regular
            glass.tintColor = nil
        }
        #endif
    }
}
final class FrostedBackdrop: NSVisualEffectView {
    let density = DensityBackdrop()
    let matte = MatteBackdrop()
    private(set) var liquidGlass: NSView?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        density.frame = bounds
        density.autoresizingMask = [.width, .height]
        density.material = .popover
        density.blendingMode = .behindWindow
        density.state = .active
        addSubview(density)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 23
            glass.style = .regular
            // The matte veil belongs inside the native effect. This keeps
            // Apple's rim lighting/refraction above it instead of painting
            // a synthetic gradient or opaque layer over the glass highlights.
            glass.contentView = matte
            liquidGlass = glass
        } else { addSubview(matte) }
        #else
        addSubview(matte)
        #endif
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }
    override func layout() {
        super.layout()
        density.frame = bounds
        if liquidGlass == nil { matte.frame = bounds }
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var mouseDownCanMoveWindow: Bool { false }
}
final class GlassBackdropContainer: NSView {
    let backdrop = FrostedBackdrop()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(backdrop)
        // The native glass is a sibling of the clipped blur, so its system
        // rim/refraction isn't flattened by a custom material clipping mask.
        if let glass = backdrop.liquidGlass { addSubview(glass) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }
    override func layout() {
        super.layout()
        backdrop.frame = bounds
        backdrop.liquidGlass?.frame = bounds
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var mouseDownCanMoveWindow: Bool { false }
}
final class MatteBackdrop: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var mouseDownCanMoveWindow: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 23, yRadius: 23).fill()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
final class DensityBackdrop: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var mouseDownCanMoveWindow: Bool { false }
}
struct GlassSurface: View {
    var cornerRadius: CGFloat = 23
    var appearance: GlassAppearance = .system
    var body: some View {
        GlassBackdrop(cornerRadius: cornerRadius, appearance: appearance)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
struct GlassInset: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(Color(nsColor: .quaternaryLabelColor))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
struct NativeIconButtonStyle: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.small)
        } else {
            content.buttonStyle(.borderless)
        }
        #else
        content.buttonStyle(.borderless)
        #endif
    }
}
