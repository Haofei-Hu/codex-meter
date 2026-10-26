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
    model.setGlassAppearance(GlassAppearance(transparency: 0.65, frost: 0.3, theme: .dark), for: .desktop)
    precondition(updates == 1 && model.popoverGlass == .system, "Targets must have independent controls")
    model.setGlassAppearance(model.desktopGlass, for: .popover)
    precondition(model.desktopGlass == model.popoverGlass, "Sync must copy both values")
    let relaunched = QuotaModel(executableOverride: "/usr/bin/false", preferences: preferences)
    precondition(relaunched.desktopGlass == model.desktopGlass && relaunched.popoverGlass == model.popoverGlass, "Appearance must survive restart")
    model.setGlassAppearance(.system, for: .popover)
    precondition(model.popoverGlass == .system && model.desktopGlass.frost == 0.3, "Reset must affect only the selected target")
    let invalid = GlassAppearance(transparency: -.infinity, frost: 4)
    precondition(invalid == GlassAppearance(transparency: 1, frost: 3))
    precondition(GlassAppearance(transparency: -2, frost: -1) == GlassAppearance(transparency: 0, frost: 0))
    model.applyAppleWidgetAppearance()
    precondition(model.desktopGlass == .appleWidget && model.popoverGlass == .appleWidget, "Widget preset must apply to both surfaces")
    let widgetRestart = QuotaModel(executableOverride: "/usr/bin/false", preferences: preferences)
    precondition(widgetRestart.desktopGlass == .appleWidget && widgetRestart.popoverGlass == .appleWidget, "Widget appearance must persist")
    precondition(widgetRestart.desktopGlass.widgetTint && widgetRestart.popoverGlass.widgetTint, "Widget tint must survive both model setters and relaunch")
    let settings = NSHostingView(rootView: SettingsPanel(model: model, close: {}).background(Color(nsColor: .windowBackgroundColor)))
    settings.frame = NSRect(origin: .zero, size: settings.fittingSize)
    settings.layoutSubtreeIfNeeded()
    let settingsRep = settings.bitmapImageRepForCachingDisplay(in: settings.bounds)!
    settings.cacheDisplay(in: settings.bounds, to: settingsRep)
    try! settingsRep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("glass-settings.png"))
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    for strength in [0.0, 0.4, 1.0, 2.0, 3.0] {
      for transparency in [0.0, 0.75, 1.0, 1.5, 2.0, 2.5, 3.0] {
        model.setGlassAppearance(GlassAppearance(transparency: transparency, frost: strength), for: .desktop)
        let host = NSHostingView(rootView: QuotaCard(model: model, desktop: true))
        host.sizingOptions = []; host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let effects = descendants(host).compactMap { $0 as? FrostedBackdrop }
        precondition(effects.count == 1 && effects[0].material == .hudWindow && effects[0].state == .active && effects[0].blendingMode == .behindWindow && effects[0].maskImage == nil)
        precondition(abs(effects[0].alphaValue - (effects[0].liquidGlass == nil ? 1 : model.desktopGlass.blurLayerOpacity)) < 0.001, "200–300% must actually reduce additional material on native glass")
        precondition(abs(effects[0].density.alphaValue - model.desktopGlass.densityOpacity) < 0.001, "Extended transparency must remove the denser overlaid material")
        precondition(abs(effects[0].matte.alphaValue - model.desktopGlass.toneOpacity) < 0.001)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = effects[0].liquidGlass as? NSGlassEffectView
            precondition(glass != nil && glass!.contentView === effects[0].matte && glass!.tintColor == nil, "macOS 26 must use the real native Liquid Glass effect")
            precondition(glass!.style == (transparency > 2 && strength == 0 ? .clear : .regular), "Positive frost must retain native adaptive blur")
            precondition(glass!.alphaValue == 1 && glass!.cornerRadius == glassCornerRadius)
            precondition(glass!.frame == effects[0].bounds, "Native glass must cover the complete card at every scale")
        } else { precondition(effects[0].liquidGlass == nil) }
        #endif
        precondition(host.alphaValue == 1, "Changing background must not fade card content")
      }
    }
    // The neutral veil ranges from absent to opaque. Native clear glass is
    // allowed at zero extra frost; positive frost selects adaptive blur.
    var alphas: [CGFloat] = []
    for transparency in [0.0, 1.0] {
        let host = NSHostingView(rootView: GlassTone(appearance: GlassAppearance(transparency: transparency, frost: 0)).frame(width: 100, height: 100))
        host.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        alphas.append(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)!.alphaComponent)
        try! rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("glass-transparency-\(Int(transparency * 100)).png"))
    }
    precondition(alphas[0] > 0.95 && alphas[1] < 0.05, "Transparency must change the rendered background independently of frost")
    for transparency in stride(from: 0.0, through: 3.0, by: 0.05) {
        var previous = -1.0
        for frost in stride(from: 0.0, through: 3.0, by: 0.05) {
            let opacity = GlassAppearance(transparency: transparency, frost: frost).toneOpacity
            precondition(opacity >= previous && (0...1).contains(opacity), "Matte range must be continuous and monotonic")
            previous = opacity
        }
    }
    precondition(GlassAppearance(transparency: 3, frost: 3).toneOpacity == 1, "300% frost must completely cover the background")
    precondition(GlassAppearance(transparency: 3, frost: 0).blurLayerOpacity == 0 && GlassAppearance(transparency: 2, frost: 0).blurLayerOpacity == 1, "The extended range must remove the extra HUD material")
    precondition(GlassAppearance(transparency: 2, frost: 0).densityOpacity == 0 && GlassAppearance(transparency: 1, frost: 0).densityOpacity == 1, "100–200% transparency must visibly reduce material density")
    let desktop = DesktopPanel(cardFrame: NSRect(x: 10, y: 10, width: 332, height: 500))
    precondition(!desktop.hasShadow, "A translucent card must not reveal a dark shadow ring beneath itself")
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
    let originalMask = effect!.maskImage
    let decorations = effect!.subviews.filter { $0 !== controller.view && !controller.view.isDescendant(of: $0) }.map { ($0, $0.alphaValue) }
    let originalFrame = controller.view.window!.frame
    for strength in [0.0, 0.25, 0.75, 1.0, 1.5, 2.0, 3.0, 0.0, 3.0] {
        let value = GlassAppearance(transparency: 3, frost: strength)
        model.setGlassAppearance(value, for: .popover)
        popover.glassAppearance = value
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        precondition(controller.view.alphaValue == 1 && controller.view.window!.alphaValue == 1 && effect!.alphaValue == 1, "Popover content must stay fully opaque")
        precondition(popover.contentViewController === controller, "Dragging a slider must not recreate the controller")
        precondition(popover.isShown && popover.animates && controller.view.window!.frame == originalFrame && anchor.frame == frame, "Appearance updates must not replay animation, dismiss or move either window")
        let owned = descendants(controller.view).compactMap { $0 as? FrostedBackdrop }
        precondition(owned.count == 1 && owned[0].material == .hudWindow && owned[0].maskImage == nil && owned[0].density.alphaValue == 0)
        precondition(effect!.maskImage === originalMask && !controller.view.window!.hasShadow, "Additional native tint and shadow must not cap the range or create a dark ring")
        for (decoration, originalAlpha) in decorations {
            precondition(decoration.isHidden && decoration.alphaValue == originalAlpha, "Additional native background must be suppressed without fading any content")
        }
    }
    for theme in GlassTheme.allCases {
        popover.glassAppearance = GlassAppearance(transparency: 0.5, frost: 0.5, theme: theme)
        precondition(popover.appearance?.bestMatch(from: [.aqua, .darkAqua]) == (theme.nativeAppearance ?? NSApp.effectiveAppearance).bestMatch(from: [.aqua, .darkAqua]))
    }
    model.applyAppleWidgetAppearance()
    let widgetHost = NSHostingView(rootView: QuotaCard(model: model, desktop: true))
    widgetHost.frame = NSRect(origin: .zero, size: widgetHost.fittingSize)
    widgetHost.layoutSubtreeIfNeeded()
    let widgetContainers = descendants(widgetHost).compactMap { $0 as? GlassBackdropContainer }
    precondition(widgetContainers.count == 1 && widgetContainers[0].appearance?.name == .darkAqua, "Widget look must set the complete glass hierarchy to dark, not just the blur")
    precondition(widgetContainers[0].backdrop.matte.alphaValue == 0, "Transparent widget style must not paint a fixed blue or gray backdrop")
    let matte = widgetContainers[0].backdrop.matte
    precondition(matte.bounds.width > 100 && matte.bounds.height > 100, "The tint must cover the whole widget, not an empty content view")
    let tintRep = matte.bitmapImageRepForCachingDisplay(in: matte.bounds)!
    matte.cacheDisplay(in: matte.bounds, to: tintRep)
    let tintPixel = tintRep.colorAt(x: tintRep.pixelsWide / 2, y: tintRep.pixelsHigh / 2)!.usingColorSpace(.deviceRGB)!
    precondition(abs(tintPixel.blueComponent - tintPixel.redComponent) < 0.08, "No fixed blue tint may remain in the backdrop")
    #if compiler(>=6.2)
    if #available(macOS 26.0, *) {
        precondition(widgetContainers[0].backdrop.liquidGlass?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua, "Native glass must follow the selected dark appearance")
        precondition((widgetContainers[0].backdrop.liquidGlass as? NSGlassEffectView)?.tintColor == nil, "Glass color must come from the background, not a fixed tint")
    }
    #endif
    popover.close(); anchor.orderOut(nil)
    print("PASS: native Liquid Glass on macOS 26, compatible blur fallback, real 0–300% range, native clear/adaptive blur styles, no fixed tint/shadow, themes, sync/reset/persistence and stable animated popovers")
}
