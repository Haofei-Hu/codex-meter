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
        view.material = .popover
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
    }
}
final class FrostedBackdrop: NSVisualEffectView {
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
