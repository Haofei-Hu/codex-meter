import AppKit
import SwiftUI

func statusMenuFrame(anchor: NSRect, contentSize: NSSize, visibleFrame: NSRect) -> NSRect {
    let margin: CGFloat = 8
    let size = NSSize(width: min(contentSize.width, visibleFrame.width - 2 * margin),
                      height: min(contentSize.height, visibleFrame.height - 2 * margin))
    let top = min(anchor.minY - 4, visibleFrame.maxY - margin)
    let x = max(visibleFrame.minX + margin, min(anchor.midX - size.width / 2, visibleFrame.maxX - margin - size.width))
    let y = max(visibleFrame.minY + margin, min(top - size.height, visibleFrame.maxY - margin - size.height))
    return NSRect(origin: NSPoint(x: x, y: y), size: size)
}
final class StatusMenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
struct StatusMenuContent: View {
    @ObservedObject var model: QuotaModel
    let height: CGFloat
    var body: some View {
        ScrollView(.vertical) { QuotaCard(model: model) }
            .scrollIndicators(.automatic)
            .frame(width: 332, height: height)
            .background(Color(red: 0.065, green: 0.08, blue: 0.095))
            .clipShape(RoundedRectangle(cornerRadius: 23))
            .environment(\.colorScheme, .dark)
    }
}
func testStatusMenuPositioning() {
    let screens = [NSRect(x: 0, y: 25, width: 1440, height: 850), NSRect(x: -1920, y: 70, width: 1920, height: 980)]
    for screen in screens {
        for x in [screen.minX, screen.midX, screen.maxX - 20] {
            for height in [430.0, 680.0, 1600.0] {
                let frame = statusMenuFrame(anchor: NSRect(x: x, y: screen.maxY, width: 100, height: 25), contentSize: NSSize(width: 332, height: height), visibleFrame: screen)
                precondition(screen.contains(frame))
                precondition(frame.maxY <= screen.maxY - 8)
            }
        }
    }
    print("PASS: menu stays below menu bar and inside primary/secondary screens, including tall content")
}
