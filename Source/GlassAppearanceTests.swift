import AppKit
import SwiftUI

@MainActor func testGlassAppearance(directory: URL) {
    let suite = "local.codexquota.glass-test." + UUID().uuidString
    let preferences = UserDefaults(suiteName: suite)!
    defer { preferences.removePersistentDomain(forName: suite) }
    let model = QuotaModel(executableOverride: "/usr/bin/false", preferences: preferences)
    precondition(model.desktopGlass == .system && model.popoverGlass == .system)
    var updates = 0
    model.onChange = { updates += 1 }
    model.setGlassAppearance(GlassAppearance(transparency: 0.65, frost: 0.3), for: .desktop)
    precondition(updates == 1 && model.popoverGlass == .system, "Targets must have independent controls")
    model.setGlassAppearance(model.desktopGlass, for: .popover)
    precondition(model.desktopGlass == model.popoverGlass, "Sync must copy both values")
    let relaunched = QuotaModel(executableOverride: "/usr/bin/false", preferences: preferences)
    precondition(relaunched.desktopGlass == model.desktopGlass && relaunched.popoverGlass == model.popoverGlass, "Appearance must survive restart")
    model.setGlassAppearance(.system, for: .popover)
    precondition(model.popoverGlass == .system && model.desktopGlass.frost == 0.3, "Reset must affect only the selected target")
    let invalid = GlassAppearance(transparency: -.infinity, frost: 4)
    precondition(invalid == .system)
    precondition(GlassAppearance(transparency: -2, frost: -1) == GlassAppearance(transparency: 0, frost: 0))
    let settings = NSHostingView(rootView: SettingsPanel(model: model, close: {}).background(Color(nsColor: .windowBackgroundColor)))
    settings.frame = NSRect(origin: .zero, size: settings.fittingSize)
    settings.layoutSubtreeIfNeeded()
    let settingsRep = settings.bitmapImageRepForCachingDisplay(in: settings.bounds)!
    settings.cacheDisplay(in: settings.bounds, to: settingsRep)
    try! settingsRep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("glass-settings.png"))
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    for strength in [0.0, 0.4, 1.0] {
        model.setGlassAppearance(GlassAppearance(transparency: 0.75, frost: strength), for: .desktop)
        let host = NSHostingView(rootView: QuotaCard(model: model, desktop: true))
        host.sizingOptions = []; host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let effects = descendants(host).compactMap { $0 as? FrostedBackdrop }
        precondition(effects.count == 1 && abs(effects[0].alphaValue - strength) < 0.001)
        precondition(host.alphaValue == 1, "Changing background must not fade card content")
    }
    // Render the independent, unblurred transparency endpoints. At zero frost,
    // transparency must still change the background, not just another slider.
    var alphas: [CGFloat] = []
    for transparency in [0.0, 1.0] {
        let host = NSHostingView(rootView: GlassSurface(appearance: GlassAppearance(transparency: transparency, frost: 0)).frame(width: 100, height: 100))
        host.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        alphas.append(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)!.alphaComponent)
        try! rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("glass-transparency-\(Int(transparency * 100)).png"))
    }
    precondition(alphas[0] > 0.95 && alphas[1] < 0.05, "Transparency must change the rendered background independently of frost")
    let anchor = NSWindow(contentRect: NSRect(x: 300, y: 200, width: 332, height: 500), styleMask: [.borderless], backing: .buffered, defer: false)
    anchor.isReleasedWhenClosed = false
    anchor.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 332, height: 500))
    anchor.orderBack(nil)
    let frame = anchor.frame
    let popover = makeNativePopover()
    let controller = NSHostingController(rootView: SettingsPanel(model: model, close: {}))
    popover.contentViewController = controller
    popover.glassAppearance = GlassAppearance(transparency: 1, frost: 0.4)
    popover.show(relativeTo: NSRect(x: 166, y: 250, width: 1, height: 1), of: anchor.contentView!, preferredEdge: .minX)
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    var ancestor = controller.view.superview
    var effect: NSVisualEffectView?
    while let view = ancestor {
        if let visual = view as? NSVisualEffectView { effect = visual; break }
        ancestor = view.superview
    }
    precondition(effect != nil && popover.refreshGlassAppearance(), "Native popover must expose an adjustable background")
    let originalFrame = controller.view.window!.frame
    for strength in [0.0, 0.25, 0.75, 1.0, 0.0, 1.0] {
        popover.glassAppearance = GlassAppearance(transparency: 0.7, frost: strength)
        precondition(controller.view.alphaValue == 1 && controller.view.window!.alphaValue == 1 && effect!.alphaValue == 1, "Popover content must stay fully opaque")
        precondition(popover.contentViewController === controller, "Dragging a slider must not recreate the controller")
        precondition(popover.isShown && popover.animates && controller.view.window!.frame == originalFrame && anchor.frame == frame, "Appearance updates must not replay animation, dismiss or move either window")
        for decoration in effect!.subviews where decoration !== controller.view && !controller.view.isDescendant(of: decoration) {
            precondition(abs(decoration.alphaValue - strength) < 0.001, "Native background did not update")
        }
    }
    popover.close(); anchor.orderOut(nil)
    print("PASS: independent glass controls, sync/reset/persistence, rendered transparency, desktop frost and live native popover background without fading content or moving windows")
}
