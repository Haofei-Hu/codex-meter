import AppKit
import SwiftUI

enum GlassTarget: String, CaseIterable, Identifiable {
    case desktop, popover
    var id: String { rawValue }
    var title: String { self == .desktop ? "桌面卡片" : "弹出面板" }
}

struct GlassAppearance: Equatable {
    var transparency: Double = 1
    var frost: Double = 1
    static let system = GlassAppearance()
    init(transparency: Double = 1, frost: Double = 1) {
        self.transparency = Self.normalized(transparency)
        self.frost = Self.normalized(frost)
    }
    private static func normalized(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 1
    }
    init(preferences: UserDefaults, target: GlassTarget) {
        func value(_ field: String) -> Double {
            let key = "glass.\(target.rawValue).\(field)"
            return (preferences.object(forKey: key) as? NSNumber)?.doubleValue ?? 1
        }
        self.init(transparency: value("transparency"), frost: value("frost"))
    }
    func save(to preferences: UserDefaults, target: GlassTarget) {
        preferences.set(transparency, forKey: "glass.\(target.rawValue).transparency")
        preferences.set(frost, forKey: "glass.\(target.rawValue).frost")
    }
}

struct GlassTone: View {
    let appearance: GlassAppearance
    var body: some View {
        Color(nsColor: .windowBackgroundColor).opacity(1 - appearance.transparency)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct GlassAppearanceSettings: View {
    @ObservedObject var model: QuotaModel
    @State private var target: GlassTarget = .desktop
    private var value: GlassAppearance { model.glassAppearance(for: target) }
    private func slider(_ title: String, field: WritableKeyPath<GlassAppearance, Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value[keyPath: field] * 100).rounded()))%")
                    .monospacedDigit().foregroundStyle(glassSecondary)
            }
            Slider(value: Binding(get: { value[keyPath: field] }, set: { number in
                var next = value; next[keyPath: field] = number
                model.setGlassAppearance(next, for: target)
            }), in: 0...1, step: 0.01)
                .accessibilityLabel(target.title + title)
                .accessibilityValue("\(Int((value[keyPath: field] * 100).rounded()))%")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("玻璃外观").fontWeight(.medium)
                Spacer()
                Button("还原外观") { model.setGlassAppearance(.system, for: target) }
                    .help("将当前面板还原为系统默认材质")
            }
            Picker("调整对象", selection: $target) {
                ForEach(GlassTarget.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            slider("透明度", field: \.transparency)
            slider("磨砂强度", field: \.frost)
            Text("磨砂越低，背景越清晰；透明度越低，底色越实。")
                .font(.system(size: 10)).foregroundStyle(glassSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(target == .desktop ? "同步到弹出面板" : "同步到桌面卡片") {
                model.setGlassAppearance(value, for: target == .desktop ? .popover : .desktop)
            }
        }
    }
}
