import AppKit
import SwiftUI

let glassSecondary = Color.white.opacity(0.72)
let glassTertiary = Color.white.opacity(0.56)

// The material is visual only. Window-level dragging and control exclusions
// continue receiving the same mouse events through this entire surface.
struct GlassBackdrop: NSViewRepresentable {
    let cornerRadius: CGFloat
    func makeNSView(context: Context) -> NSView {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let view = NativeGlassBackdrop()
            view.style = .clear
            view.cornerRadius = cornerRadius
            view.tintColor = nil
            view.appearance = NSAppearance(named: .darkAqua)
            return view
        }
        #endif
        let view = FrostedBackdrop()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), let glass = view as? NativeGlassBackdrop {
            glass.cornerRadius = cornerRadius
            return
        }
        #endif
        view.layer?.cornerRadius = cornerRadius
    }
}
#if compiler(>=6.2)
@available(macOS 26.0, *)
final class NativeGlassBackdrop: NSGlassEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var mouseDownCanMoveWindow: Bool { false }
}
#endif
final class FrostedBackdrop: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var mouseDownCanMoveWindow: Bool { false }
}

struct GlassSurface: View {
    var cornerRadius: CGFloat = 23
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if reduceTransparency {
                shape.fill(Color(red: 0.12, green: 0.15, blue: 0.17))
            } else {
                GlassBackdrop(cornerRadius: cornerRadius)
                shape.fill(.black.opacity(0.42))
                shape.fill(LinearGradient(colors: [.white.opacity(0.075), .clear, .black.opacity(0.045)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.07), .white.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7)
        }
        .clipShape(shape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
struct GlassInset: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        shape.fill(LinearGradient(colors: [.white.opacity(0.075), .white.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(shape.strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
struct GlassCircle: View {
    var body: some View {
        Circle().fill(LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.045)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
