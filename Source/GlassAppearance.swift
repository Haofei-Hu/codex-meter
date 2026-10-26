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
    // The native blur stays fully enabled. Frost now adds a matte veil instead
    // of crossfading with an unblurred desktop/window. Endpoints span native
    // frosted glass through near-solid coverage, independently of base opacity.
    var toneOpacity: Double { 1 - transparency * (1 - 0.96 * frost) }
    private static func normalized(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 1
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
            Picker("底色", selection: Binding(get: { value.theme }, set: { theme in
                var next = value; next.theme = theme
                model.setGlassAppearance(next, for: target)
            })) {
                ForEach(GlassTheme.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
                .accessibilityLabel(target.title + "底色")
            Text("始终模糊背景；提高磨砂会遮住更多细节，降低透明度会加实底色。")
                .font(.system(size: 10)).foregroundStyle(glassSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(target == .desktop ? "同步到弹出面板" : "同步到桌面卡片") {
                model.setGlassAppearance(value, for: target == .desktop ? .popover : .desktop)
            }
        }
    }
}
