import AppKit
import SwiftUI

@MainActor func runDesktopCardTests(directory: String) {
    let app = NSApplication.shared
    try! FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    testQuotaRingBounds(directory: directory)
    testQuotaRingClockwise(directory: directory)
    app.setActivationPolicy(.accessory)
    let root = URL(fileURLWithPath: directory)
    try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let suite = "local.codexquota.desktop-test." + UUID().uuidString
    let prefs = UserDefaults(suiteName: suite)!
    defer { prefs.removePersistentDomain(forName: suite) }
    let model = QuotaModel(executableOverride: "/usr/bin/false", preferences: prefs)
    let panel = DesktopPanel(cardFrame: NSRect(x: 80, y: 120, width: 332, height: 600))
    panel.title = "Codex Meter · 界面测试"; panel.isOpaque = false; panel.backgroundColor = .clear
    let host = NSHostingView(rootView: DesktopCard(model: model, openMenu: { print("DRAG_FIXTURE settings clicked") }))
    host.sizingOptions = []; panel.contentView = host
    func allViews(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(allViews) }
    func save(_ name: String) {
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(name + ".png"))
    }
    for plan in ["plus", "pro"] {
        model.account = AccountInfo(type: "chatgpt", email: "demo@example.test", planType: plan)
        let reset = Date().addingTimeInterval(7200).timeIntervalSince1970
        let weekly = QuotaWindow(usedPercent: 13, windowDurationMins: 10080, resetsAt: reset + 86400 * 4)
        let short = QuotaWindow(usedPercent: 35, windowDurationMins: 300, resetsAt: reset)
        model.limits = Limits(rateLimits: Bucket(limitId: "codex", limitName: nil, primary: plan == "plus" ? short : weekly, secondary: plan == "plus" ? weekly : nil, planType: plan), rateLimitsByLimitId: nil)
        model.lastUpdate = Date()
        for crowded in [false, true] {
          for requestedScale in [0.75, 1.0, 1.6] {
            model.error = crowded ? String(repeating: "验证长内容与屏幕适配。", count: 25) : nil
            model.work = WorkOverview(state: .running, tasks: (0..<(crowded ? 2 : 1)).map { index in
                var task = WorkTask(id: "demo-\(index)", title: "验证 Mac 卡片拖动与完整显示")
                task.active = true; task.startedAt = Date().addingTimeInterval(-90); task.updatedAt = Date()
                task.detail = "只使用演示数据，检查 Plus / Pro 和小屏幕上的标题、进度与缩放手柄。"
                task.planTotal = 4; task.planDone = 2
                return task
            }, activeCount: crowded ? 2 : 1)
            let measure = NSHostingView(rootView: QuotaCard(model: model, desktop: true))
            let height = measure.fittingSize.height
            let area = crowded ? NSRect(x: 0, y: 0, width: 1024, height: 480) : NSScreen.main!.visibleFrame
            let layout = desktopCardLayout(naturalHeight: height, requestedScale: requestedScale, visibleFrame: area, currentFrame: panel.frame)
            model.cardHeight = height; model.cardVisibleHeight = layout.visibleHeight; model.cardScale = layout.scale
            panel.setFrame(layout.frame, display: true)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            host.layoutSubtreeIfNeeded()
            precondition(abs(host.frame.height - layout.frame.height) < 1)
            let views = allViews(host)
            let drags = views.compactMap { $0 as? WindowDragView }.filter { !$0.isHiddenOrHasHiddenAncestor && $0.bounds.width > 0 }
            precondition(drags.count == 1, "The panel needs one full-card drag region")
            precondition(panel.level == .normal && !panel.isMovableByWindowBackground)
            // Both quota rows, title, whitespace and footer must route dragging
            // in the inactive production panel, at normal and fitted scales.
            for point in [NSPoint(x: 30, y: panel.frame.height - 32), NSPoint(x: 15, y: panel.frame.height / 2), NSPoint(x: 50, y: 30)] {
                precondition(panel.canDragDesktop(at: point), "Background drag region is blocked")
            }
            let controls = views.compactMap { $0 as? WindowControlView }.filter { !$0.visibleRect.isEmpty }
            precondition(controls.count == 2, "Settings and refresh need click-through exclusions")
            for control in controls {
                let point = control.convert(NSPoint(x: control.bounds.midX, y: control.bounds.midY), to: nil)
                precondition(!panel.canDragDesktop(at: point), "Dragging must not steal a control click")
            }
            let before = panel.frame.origin
            var ended = 0; panel.dragEnded = { ended += 1 }
            panel.beginDesktopDrag(at: NSPoint(x: 400, y: 400))
            panel.moveDesktopDrag(to: NSPoint(x: 490, y: 435))
            precondition(panel.userDragging && abs(panel.frame.minX - before.x - 90) < 1 && abs(panel.frame.minY - before.y - 35) < 1, "Desktop drag did not actually move the window")
            panel.moveDesktopDrag(to: NSPoint(x: 370, y: 390))
            precondition(abs(panel.frame.minX - before.x + 30) < 1 && abs(panel.frame.minY - before.y + 10) < 1, "Drag offsets must stay anchored to the original pointer")
            panel.endDesktopDrag(); panel.endDesktopDrag()
            precondition(!panel.userDragging && ended == 1, "Drag state did not reset exactly once")
            panel.setFrame(layout.frame, display: true)
            let grip = views.compactMap { $0 as? CornerResizeView }.first!
            let gripRect = grip.convert(grip.bounds, to: host)
            precondition(host.bounds.insetBy(dx: -1, dy: -1).contains(gripRect), "Resize grip is clipped")
            precondition(!panel.canDragDesktop(at: grip.convert(NSPoint(x: grip.bounds.midX, y: grip.bounds.midY), to: nil)), "Dragging must not steal resizing")
            if crowded { precondition(layout.visibleHeight < height, "Expected scrollable overflow") }
            save(plan + (crowded ? "-small" : "-normal") + "-scale-\(Int(requestedScale * 100))")
          }
        }
    }
    print("PASS: Mac Plus/Pro window movement, inactive normal-level panels, control exclusions, overflow and resize grip")
    if CommandLine.arguments.contains("--desktop-demo") {
        // Keep the interactive fixture on Plus with both quota windows visible.
        model.error = nil
        model.account = AccountInfo(type: "chatgpt", email: "demo@example.test", planType: "plus")
        let reset = Date().addingTimeInterval(7200).timeIntervalSince1970
        model.limits = Limits(rateLimits: Bucket(limitId: "codex", limitName: nil,
            primary: QuotaWindow(usedPercent: 35, windowDurationMins: 300, resetsAt: reset),
            secondary: QuotaWindow(usedPercent: 13, windowDurationMins: 10080, resetsAt: reset + 86400 * 4), planType: "plus"), rateLimitsByLimitId: nil)
        let measure = NSHostingView(rootView: QuotaCard(model: model, desktop: true))
        let height = measure.fittingSize.height
        let layout = desktopCardLayout(naturalHeight: height, requestedScale: 1, visibleFrame: NSScreen.main!.visibleFrame, currentFrame: NSRect(x: 200, y: 100, width: 332, height: height))
        model.cardHeight = height; model.cardVisibleHeight = layout.visibleHeight; model.cardScale = layout.scale
        panel.setFrame(layout.frame, display: true)
        model.onChange = { [weak model, weak panel] in
            guard let model, let panel, !panel.userDragging else { return }
            let measure = NSHostingView(rootView: QuotaCard(model: model, desktop: true))
            let height = measure.fittingSize.height
            let fit = desktopCardLayout(naturalHeight: height, requestedScale: model.desktopScale, visibleFrame: panel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame, currentFrame: panel.frame)
            model.cardHeight = height; model.cardVisibleHeight = fit.visibleHeight; model.cardScale = fit.scale
            panel.setFrame(fit.frame, display: true)
            print("DRAG_FIXTURE scale \(model.desktopScale), frame \(panel.frame)")
        }
        panel.dragEnded = { print("DRAG_FIXTURE ended \(panel.frame.origin.x),\(panel.frame.origin.y)") }
        let observer = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { _ in
            print("DRAG_FIXTURE moved \(panel.frame.origin.x),\(panel.frame.origin.y)")
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        print("DRAG_FIXTURE initial \(panel.frame.origin.x),\(panel.frame.origin.y)")
        panel.orderFrontRegardless()
        app.run()
    }
    panel.orderOut(nil)
}

@MainActor func testQuotaRingBounds(directory: String) {
    let host = NSHostingView(rootView: QuotaRing(remaining: 100).padding(8).background(Color.black).environment(\.colorScheme, .dark))
    host.frame = NSRect(x: 0, y: 0, width: 110, height: 110)
    host.layoutSubtreeIfNeeded()
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    let scaleX = CGFloat(rep.pixelsWide) / 110, scaleY = CGFloat(rep.pixelsHigh) / 110
    var colored = 0
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide {
            guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                  color.redComponent < 0.65, color.greenComponent > 0.7, color.blueComponent > 0.5 else { continue }
            colored += 1
            precondition(CGFloat(x) >= 8 * scaleX && CGFloat(x) < 102 * scaleX && CGFloat(y) >= 8 * scaleY && CGFloat(y) < 102 * scaleY, "Ring stroke escapes its layout bounds and will be clipped by a scroll view")
        }
    }
    precondition(colored > 100, "Ring did not render")
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent("ring-bounds.png"))
    print("PASS: rendered ring stroke stays entirely inside its layout bounds")
}

@MainActor func testQuotaRingClockwise(directory: String) {
    for value in [95, 75, 25] {
        let host = NSHostingView(rootView: QuotaRing(remaining: value).padding(8).background(Color.black).environment(\.colorScheme, .dark))
        host.frame = NSRect(x: 0, y: 0, width: 110, height: 110)
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        func colored(_ x: Int, _ y: Int) -> Bool {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
            let colors = [c.redComponent, c.greenComponent, c.blueComponent]
            return colors.max()! - colors.min()! > 0.2 && colors.max()! > 0.4
        }
        var left = 0, right = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where colored(x, y) {
                if x < rep.pixelsWide / 2 { left += 1 } else { right += 1 }
            }
        }
        // The used gap advances from the top into the right half. Remaining
        // paint must favor the left half, distinguishing clockwise from both
        // the old counterclockwise gap and the rejected symmetric design.
        precondition(left + right > 100 && Double(left - right) / Double(left + right) > 0.015, "Quota gap must advance clockwise from twelve o'clock")
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent("ring-gap-\(value).png"))
    }
    print("PASS: rendered quota gaps advance clockwise from twelve o'clock at 95%, 75%, and 25%")
}
