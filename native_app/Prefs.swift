import Cocoa

// 外观偏好（浅色/深色/跟随系统）——设置面板现在是网页（settings.html），
// 但"改变整个 App 的外观"这件事（标题栏之类的原生窗口装饰）还是得靠原生代码，
// 所以这个 enum 留在原生这边，网页通过 Bridge.swift 的 getPrefs/setPrefs 调用它。
enum AppearanceMode: String, Equatable {
    case system, light, dark

    static var current: AppearanceMode {
        AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "appearanceMode") ?? "system") ?? .system
    }

    // 开机/启动时调用一次，把上次选的外观应用上——不写这一步的话每次重开 App
    // 都会先闪一下系统默认外观，再等设置面板打开才生效。
    static func applyStartupPreference() {
        current.apply(persist: false)
    }

    func apply(persist: Bool = true) {
        if persist {
            UserDefaults.standard.set(rawValue, forKey: "appearanceMode")
        }
        let resolved: NSAppearance?
        switch self {
        case .system: resolved = nil
        case .light: resolved = NSAppearance(named: .aqua)
        case .dark: resolved = NSAppearance(named: .darkAqua)
        }
        NSApp.appearance = resolved
        // 只设 NSApp.appearance 对已经开着的窗口不可靠——新开的窗口会立刻生效，
        // 但已经在屏幕上的窗口不一定会重新计算 effectiveAppearance。显式挨个把
        // 已开窗口的 appearance 也设一遍，强制它们立刻重算标题栏之类的原生装饰。
        for window in NSApp.windows {
            window.appearance = resolved
        }
    }
}
