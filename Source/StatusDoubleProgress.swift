import AppKit

func statusDoubleProgressImage(rows: [QuotaDisplayRow], stale: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: 111, height: 22), flipped: false) { _ in
        for (index, row) in rows.prefix(2).enumerated() {
            let y = index == 0 ? 12.0 : 1.0
            let color = row.remaining.map { NSColor(quotaColor($0)).withAlphaComponent(stale ? 0.65 : 1) } ?? NSColor.secondaryLabelColor
            let label = index == 0 ? row.window?.windowDurationMins.map { "\($0 / 60)小时" } ?? "5小时" : "每周"
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium), .foregroundColor: color]
            (label as NSString).draw(at: NSPoint(x: 0, y: y - 1), withAttributes: attributes)
            let track = NSRect(x: 32, y: y + 2, width: 40, height: 5)
            let shape = NSBezierPath(roundedRect: track, xRadius: 2.5, yRadius: 2.5)
            NSColor.gray.withAlphaComponent(0.32).setFill(); shape.fill()
            if let amount = row.remaining {
                NSGraphicsContext.saveGraphicsState(); shape.addClip(); color.setFill()
                NSRect(x: 32, y: y + 2, width: 40 * Double(amount) / 100, height: 5).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            ((row.remaining.map { "\($0)%" } ?? "—") as NSString).draw(at: NSPoint(x: 77, y: y - 1), withAttributes: attributes)
        }
        return true
    }
    image.isTemplate = false
    image.accessibilityDescription = rows.map { $0.label + ($0.remaining.map { " \($0)%" } ?? " 未返回") }.joined(separator: "，")
    return image
}
