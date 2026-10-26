import AppKit
import SwiftUI

@MainActor func runDesktopCardTests(directory: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let root = URL(fileURLWithPath: directory)
    try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let suite = "local.codexquota.desktop-test." + UUID().uuidString
    let prefs = UserDefaults(suiteName: suite)!
    defer { prefs.removePersistentDomain(forName: suite) }
    let model = QuotaModel(executableOverride: "/usr/bin/false", preferences: prefs)
    let panel = DesktopPanel(contentRect: NSRect(x: 80, y: 120, width: 332, height: 600), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.title = "Codex Meter · 界面测试"; panel.isOpaque = false; panel.backgroundColor = .clear
    let host = NSHostingView(rootView: DesktopCard(model: model, openMenu: {}))
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
            let layout = desktopCardLayout(naturalHeight: height, requestedScale: crowded ? 1.6 : 1, visibleFrame: area, currentFrame: panel.frame)
            model.cardHeight = height; model.cardVisibleHeight = layout.visibleHeight; model.cardScale = layout.scale
            panel.setFrame(layout.frame, display: true)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            host.layoutSubtreeIfNeeded()
            precondition(abs(host.frame.height - layout.frame.height) < 1)
            let views = allViews(host)
            let drags = views.compactMap { $0 as? WindowDragView }.filter { !$0.isHiddenOrHasHiddenAncestor && $0.bounds.width > 0 }
            precondition(drags.count >= 2, "Missing explicit native drag surfaces")
            let titleDrag = drags.max { $0.convert($0.bounds, to: host).midY < $1.convert($1.bounds, to: host).midY }!
            let point = host.convert(NSPoint(x: titleDrag.bounds.midX, y: titleDrag.bounds.midY), from: titleDrag)
            precondition(host.hitTest(point) is WindowDragView, "Title drag surface is blocked")
            let grip = views.compactMap { $0 as? CornerResizeView }.first!
            let gripRect = grip.convert(grip.bounds, to: host)
            precondition(host.bounds.insetBy(dx: -1, dy: -1).contains(gripRect), "Resize grip is clipped")
            if crowded { precondition(layout.visibleHeight < height, "Expected scrollable overflow") }
            save(plan + (crowded ? "-small" : "-normal"))
        }
    }
    print("PASS: Mac Plus/Pro native drag hit tests, content measurement, small-screen overflow and visible resize grip")
    if CommandLine.arguments.contains("--desktop-demo") {
        panel.orderFrontRegardless()
        app.run()
    }
    panel.orderOut(nil)
}
