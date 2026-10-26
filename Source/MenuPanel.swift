import AppKit
import SwiftUI

// Both popovers use AppKit's native chrome, positioning and animation.
func makeNativePopover() -> AdjustablePopover {
    let popover = AdjustablePopover()
    popover.behavior = .transient
    popover.animates = true
    popover.appearance = NSApp.effectiveAppearance
    return popover
}
func statusPopoverContentSize(natural: NSSize, visibleFrame: NSRect) -> NSSize {
    NSSize(width: min(332, max(1, visibleFrame.width - 32)),
           height: min(natural.height, max(1, visibleFrame.height - 48)))
}
struct StatusMenuContent: View {
    @ObservedObject var model: QuotaModel
    let height: CGFloat
    var body: some View {
        ScrollView(.vertical) { QuotaCard(model: model, showsSurface: false) }
            .scrollIndicators(.automatic)
            .frame(width: 332, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
            .background { GlassSurface(appearance: model.popoverGlass) }
    }
}
func testStatusMenuPositioning() {
    for screen in [NSRect(x: 0, y: 25, width: 1440, height: 850), NSRect(x: -1920, y: 70, width: 1920, height: 980), NSRect(x: 0, y: 0, width: 300, height: 480)] {
        for height in [430.0, 680.0, 1600.0] {
            let size = statusPopoverContentSize(natural: NSSize(width: 332, height: height), visibleFrame: screen)
            precondition(size.width <= screen.width - 32 && size.height <= screen.height - 48)
            precondition(size.height <= height && size.height > 0)
        }
    }
    print("PASS: native popover content leaves room for system chrome on small and secondary screens")
}
