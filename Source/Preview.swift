import AppKit
import SwiftUI

@MainActor func renderPlusPreview(directory: String) {
    _ = NSApplication.shared
    let root = URL(fileURLWithPath: directory)
    try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let suite = "local.codexquota.preview." + UUID().uuidString
    let prefs = UserDefaults(suiteName: suite)!
    let model = QuotaModel(preferences: prefs)
    model.account = AccountInfo(type: "chatgpt", email: "plus@example.test", planType: "plus")
    let reset = Date().addingTimeInterval(7200).timeIntervalSince1970
    let short = QuotaWindow(usedPercent: 38, windowDurationMins: 300, resetsAt: reset)
    let week = QuotaWindow(usedPercent: 74, windowDurationMins: 10080, resetsAt: reset + 86400 * 3)
    model.limits = Limits(rateLimits: Bucket(limitId: "codex", limitName: nil, primary: short, secondary: week, planType: "plus"), rateLimitsByLimitId: nil)
    model.lastUpdate = Date()
    func save(_ view: some View, _ name: String) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(name))
    }
    save(QuotaCard(model: model, desktop: true), "plus-card.png")
    let status = statusDoubleProgressImage(rows: model.displayRows, stale: false)
    let image = NSImage(size: NSSize(width: 264, height: 36), flipped: false) { _ in
        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 264, height: 36).fill()
        status.draw(at: NSPoint(x: 10, y: 7), from: .zero, operation: .sourceOver, fraction: 1)
        ("Codex 剩余额度" as NSString).draw(at: NSPoint(x: 132, y: 11), withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 13)])
        return true
    }
    try! NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("plus-menubar.png"))
    model.setHostRunning(false)
    precondition(model.statusText == "等待登录")
    save(QuotaCard(model: model, desktop: true), "waiting-card.png")
    prefs.removePersistentDomain(forName: suite)
}
