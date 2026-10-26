import AppKit
import SwiftUI

let glassSecondary = Color.secondary
let glassTertiary = Color(nsColor: .tertiaryLabelColor)

// Never fade a behind-window blur: doing so exposes sharp underlying text.
struct GlassBackdrop: NSViewRepresentable {
    let cornerRadius: CGFloat
    let appearance: GlassAppearance
    func makeNSView(context: Context) -> FrostedBackdrop {
        let view = FrostedBackdrop()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }
    func updateNSView(_ view: FrostedBackdrop, context: Context) {
        view.layer?.cornerRadius = cornerRadius
        view.alphaValue = 1
        view.appearance = appearance.theme.nativeAppearance
        view.density.alphaValue = appearance.densityOpacity
    }
}
final class FrostedBackdrop: NSVisualEffectView {
    let density = DensityBackdrop()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        density.frame = bounds
        density.autoresizingMask = [.width, .height]
        density.material = .popover
        density.blendingMode = .behindWindow
        density.state = .active
        addSubview(density)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var mouseDownCanMoveWindow: Bool { false }
}
final class DensityBackdrop: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var mouseDownCanMoveWindow: Bool { false }
}
struct GlassSurface: View {
    var cornerRadius: CGFloat = 23
    var appearance: GlassAppearance = .system
    var body: some View {
        ZStack {
            GlassBackdrop(cornerRadius: cornerRadius, appearance: appearance)
            GlassTone(appearance: appearance)
        }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
