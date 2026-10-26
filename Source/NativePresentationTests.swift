import AppKit
import SwiftUI

@MainActor func testNativePresentation(model: QuotaModel) {
    func allViews(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(allViews) }
    let statusHost = NSHostingView(rootView: StatusMenuContent(model: model, height: 500))
    statusHost.frame = NSRect(x: 0, y: 0, width: 332, height: 500)
    let settingsHost = NSHostingView(rootView: SettingsPanel(model: model, close: {}))
    settingsHost.frame = NSRect(origin: .zero, size: settingsHost.fittingSize)
    let desktopHost = NSHostingView(rootView: QuotaCard(model: model, desktop: true))
    desktopHost.sizingOptions = []
    desktopHost.frame = NSRect(origin: .zero, size: desktopHost.fittingSize)
    for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
        for host in [statusHost as NSView, settingsHost, desktopHost] {
            host.appearance = NSAppearance(named: appearanceName)
            host.layoutSubtreeIfNeeded()
        }
        precondition(allViews(statusHost).allSatisfy { !($0 is FrostedBackdrop) }, "Native status popover must not contain a second custom backdrop")
        precondition(allViews(settingsHost).allSatisfy { !($0 is FrostedBackdrop) }, "Native settings popover must not contain a second custom backdrop")
        let materials = allViews(desktopHost).compactMap { $0 as? FrostedBackdrop }
        precondition(materials.count == 1, "Desktop needs exactly one system material")
        precondition(materials[0].material == .popover && materials[0].appearance == nil, "Desktop material must inherit the native system appearance")
    }
    for host in [statusHost as NSView, settingsHost, desktopHost] { host.appearance = nil }
    // A native popover owns the visible window and its animation; the anchored
    // desktop window must keep its position throughout presentation and close.
    let anchorWindow = DesktopPanel(cardFrame: NSRect(x: 200, y: 180, width: 332, height: 500))
    anchorWindow.contentView = desktopHost
    anchorWindow.orderBack(nil)
    let frame = anchorWindow.frame
    let popover = makeNativePopover()
    popover.contentViewController = NSHostingController(rootView: SettingsPanel(model: model, close: {}))
    var didShow = false, didClose = false
    let observer = NotificationCenter.default.addObserver(forName: NSPopover.didShowNotification, object: popover, queue: .main) { _ in didShow = true }
    let closeObserver = NotificationCenter.default.addObserver(forName: NSPopover.didCloseNotification, object: popover, queue: .main) { _ in didClose = true }
    defer { NotificationCenter.default.removeObserver(observer); NotificationCenter.default.removeObserver(closeObserver) }
    popover.show(relativeTo: NSRect(x: 160, y: 240, width: 1, height: 1), of: desktopHost, preferredEdge: .minX)
    precondition(popover.isShown && popover.animates, "Presentation must use the animated native popover")
    let showDeadline = Date().addingTimeInterval(3)
    while !didShow && Date() < showDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    precondition(didShow, "Native popover did not complete presentation")
    precondition(anchorWindow.frame == frame, "Showing a popover must not move the desktop card")
    popover.performClose(nil)
    let deadline = Date().addingTimeInterval(3)
    while !didClose && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    precondition(didClose && !popover.isShown, "Native popover did not finish closing")
    precondition(anchorWindow.frame == frame, "Closing a popover must not move the desktop card")
    anchorWindow.orderOut(nil)
    print("PASS: system appearance, single material layer, native animated presentation and stable desktop position")
}
