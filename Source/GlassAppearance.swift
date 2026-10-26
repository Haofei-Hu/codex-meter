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
    // Legacy preference name; this selects widget styling, never a fixed tint.
    var widgetTint = false
    static let system = GlassAppearance()
    static let appleWidget = GlassAppearance(transparency: 3, frost: 0, theme: .dark, widgetTint: true)
    init(transparency: Double = 1, frost: Double = 0, theme: GlassTheme = .system, widgetTint: Bool = false) {
        self.transparency = Self.normalized(transparency)
        self.frost = Self.normalized(frost)
        self.theme = theme
        self.widgetTint = widgetTint
    }
    // Remove extra material toward 300% rather than painting a fixed color.
    // Positive frost selects native adaptive blur and strengthens the HUD layer.
    var densityOpacity: Double { max(0, min(1, 2 - transparency)) }
    var blurLayerOpacity: Double { min(1, max(0, 3 - transparency) + frost / 3) }
    var toneOpacity: Double { 1 - min(transparency, 1) * (1 - frost / 3) }
    var matteOpacity: Double { toneOpacity }
    private static func normalized(_ value: Double) -> Double {
        value.isFinite ? min(3, max(0, value)) : 1
    }
    init(preferences: UserDefaults, target: GlassTarget) {
        func value(_ field: String, fallback: Double) -> Double {
            let key = "glass.\(target.rawValue).\(field)"
            return (preferences.object(forKey: key) as? NSNumber)?.doubleValue ?? fallback
        }
        let theme = GlassTheme(rawValue: preferences.string(forKey: "glass.\(target.rawValue).theme") ?? "") ?? .system
        self.init(transparency: value("transparency", fallback: 1), frost: value("frost", fallback: 0), theme: theme,
                  widgetTint: preferences.bool(forKey: "glass.\(target.rawValue).widgetTint"))
    }
    func save(to preferences: UserDefaults, target: GlassTarget) {
        preferences.set(transparency, forKey: "glass.\(target.rawValue).transparency")
        preferences.set(frost, forKey: "glass.\(target.rawValue).frost")
        preferences.set(theme.rawValue, forKey: "glass.\(target.rawValue).theme")
        preferences.set(widgetTint, forKey: "glass.\(target.rawValue).widgetTint")
    }
}

struct GlassTone: View {
    let appearance: GlassAppearance
    var body: some View {
        Color(nsColor: .windowBackgroundColor).opacity(appearance.matteOpacity)
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
                Text("\(Int((value[keyPath: field] * 100).rounded()))% / 300%")
                    .monospacedDigit().foregroundStyle(glassSecondary)
            }
            Slider(value: Binding(get: { value[keyPath: field] }, set: { number in
                var next = value; next[keyPath: field] = number
                model.setGlassAppearance(next, for: target)
            }), in: 0...3, step: 0.01)
                .accessibilityLabel(target.title + title)
                .accessibilityValue("\(Int((value[keyPath: field] * 100).rounded()))%")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("玻璃外观").fontWeight(.medium)
                Text(value.widgetTint ? "小组件风格" : nativeLiquidGlassAvailable ? "液态玻璃" : "兼容磨砂")
                    .font(.system(size: 9)).foregroundStyle(glassSecondary)
                Spacer()
                Button("还原外观") { model.setGlassAppearance(.system, for: target) }
                    .help("将当前面板还原为默认磨砂外观")
            }
            Picker("调整对象", selection: $target) {
                ForEach(GlassTarget.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            Button("应用苹果小组件外观") { model.applyAppleWidgetAppearance() }
                .help("将两处统一为透明磨砂底、浅色文字和细亮边，不添加固定颜色")
            slider("透明度", field: \.transparency)
            slider("磨砂强度", field: \.frost)
            Picker("底色", selection: Binding(get: { value.theme }, set: { theme in
                var next = value; next.theme = theme
                model.setGlassAppearance(next, for: target)
            })) {
                ForEach(GlassTheme.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
                .accessibilityLabel(target.title + "底色")
            Text("透明度 200–300% 更通透；磨砂 0 保留玻璃自身效果，提高磨砂会模糊并遮挡背景。不固定底色。")
                .font(.system(size: 10)).foregroundStyle(glassSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(target == .desktop ? "同步到弹出面板" : "同步到桌面卡片") {
                model.setGlassAppearance(value, for: target == .desktop ? .popover : .desktop)
            }
        }
    }
}
