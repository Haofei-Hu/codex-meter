import AppKit
import SwiftUI

enum GlassTarget: String, CaseIterable, Identifiable {
    case desktop, popover
    var id: String { rawValue }
    var title: String { self == .desktop ? "桌面卡片" : "弹出面板" }
}
enum GlassTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { self == .system ? "跟随系统" : self == .light ? "浅色" : "深色" }
    var colorScheme: ColorScheme? { self == .system ? nil : self == .light ? .light : .dark }
    var nativeAppearance: NSAppearance? {
        self == .system ? nil : NSAppearance(named: self == .light ? .aqua : .darkAqua)
    }
}

struct GlassAppearance: Equatable {
    var transparency: Double = 1
    var frost: Double = 0
    var theme: GlassTheme = .system
    static let system = GlassAppearance()
    init(transparency: Double = 1, frost: Double = 0, theme: GlassTheme = .system) {
        self.transparency = Self.normalized(transparency)
        self.frost = Self.normalized(frost)
        self.theme = theme
    }
    // Above 100% transparency, remove the denser material over the permanent
    // HUD blur. This reveals more blurred background color, never sharp text.
    var densityOpacity: Double { max(0, min(1, 2 - transparency)) }
    var toneOpacity: Double { 1 - min(transparency, 1) * (1 - frost / 2) }
    private static func normalized(_ value: Double) -> Double {
        value.isFinite ? min(2, max(0, value)) : 1
    }
    init(preferences: UserDefaults, target: GlassTarget) {
        func value(_ field: String, fallback: Double) -> Double {
            let key = "glass.\(target.rawValue).\(field)"
            return (preferences.object(forKey: key) as? NSNumber)?.doubleValue ?? fallback
        }
        let theme = GlassTheme(rawValue: preferences.string(forKey: "glass.\(target.rawValue).theme") ?? "") ?? .system
        self.init(transparency: value("transparency", fallback: 1), frost: value("frost", fallback: 0), theme: theme)
    }
    func save(to preferences: UserDefaults, target: GlassTarget) {
        preferences.set(transparency, forKey: "glass.\(target.rawValue).transparency")
        preferences.set(frost, forKey: "glass.\(target.rawValue).frost")
        preferences.set(theme.rawValue, forKey: "glass.\(target.rawValue).theme")
    }
}

struct GlassTone: View {
    let appearance: GlassAppearance
    var body: some View {
        Color(nsColor: .windowBackgroundColor).opacity(appearance.toneOpacity)
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
                Text("\(Int((value[keyPath: field] * 100).rounded()))% / 200%")
                    .monospacedDigit().foregroundStyle(glassSecondary)
            }
            Slider(value: Binding(get: { value[keyPath: field] }, set: { number in
                var next = value; next[keyPath: field] = number
                model.setGlassAppearance(next, for: target)
            }), in: 0...2, step: 0.01)
                .accessibilityLabel(target.title + title)
                .accessibilityValue("\(Int((value[keyPath: field] * 100).rounded()))%")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("玻璃外观").fontWeight(.medium)
                Text(nativeLiquidGlassAvailable ? "液态玻璃" : "兼容磨砂")
                    .font(.system(size: 9)).foregroundStyle(glassSecondary)
                Spacer()
                Button("还原外观") { model.setGlassAppearance(.system, for: target) }
                    .help("将当前面板还原为默认磨砂外观")
            }
            Picker("调整对象", selection: $target) {
                ForEach(GlassTarget.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            slider("透明度", field: \.transparency)
            slider("磨砂强度", field: \.frost)
            Picker("底色", selection: Binding(get: { value.theme }, set: { theme in
                var next = value; next.theme = theme
                model.setGlassAppearance(next, for: target)
            })) {
                ForEach(GlassTheme.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
                .accessibilityLabel(target.title + "底色")
            Text("透明度超过 100% 更通透；磨砂 200% 为实色遮挡。所有位置都保留背景模糊。")
                .font(.system(size: 10)).foregroundStyle(glassSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(target == .desktop ? "同步到弹出面板" : "同步到桌面卡片") {
                model.setGlassAppearance(value, for: target == .desktop ? .popover : .desktop)
            }
        }
    }
}
