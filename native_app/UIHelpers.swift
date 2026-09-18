import Cocoa

// NSColor 动态色（跟着浅色/深色变化）赋给 CALayer 的 backgroundColor/borderColor 时，
// 取到的 CGColor 只是那一刻的静态快照——之后外观再变（比如在设置面板里手动切换
// 浅色/深色，而不是系统外观本身变化）不会跟着刷新，因为没有任何东西触发重新取色。
// 这个类专门补上这一步：外观真的变了就在 viewDidChangeEffectiveAppearance 里重新取。
class DynamicColorLayerView: NSView {
    var backgroundColorProvider: (() -> NSColor)? {
        didSet { refresh() }
    }
    var borderColorProvider: (() -> NSColor)? {
        didSet { refresh() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    func refresh() {
        // 在 viewDidChangeEffectiveAppearance 这种非绘制回调里直接读 NSColor.xxx.cgColor，
        // 取到的还是全局 NSAppearance.current（这时候不一定已经跟着这个 view 的
        // effectiveAppearance 变过来），不是这个 view 应该用的外观——必须显式用
        // performAsCurrentDrawingAppearance 包一下，动态色才会按传进来的外观解析。
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if let provider = self.backgroundColorProvider { self.layer?.backgroundColor = provider().cgColor }
            if let provider = self.borderColorProvider { self.layer?.borderColor = provider().cgColor }
        }
    }
}

// 圆角卡片背景——登录页（设置向导第1步）和设置面板都用得上，抽出来避免重复
// 写 wantsLayer + cornerRadius 那几行。
func makeCard(_ content: NSView, padding: CGFloat = 20) -> NSView {
    let card = DynamicColorLayerView()
    card.wantsLayer = true
    card.layer?.cornerRadius = 12
    card.layer?.borderWidth = 1
    card.backgroundColorProvider = { .controlBackgroundColor }
    card.borderColorProvider = { .separatorColor }

    content.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(content)
    NSLayoutConstraint.activate([
        content.topAnchor.constraint(equalTo: card.topAnchor, constant: padding),
        content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: padding),
        content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -padding),
        content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -padding),
    ])
    return card
}

// .env 目前只有几行 KEY=VALUE，好几个地方都要单独读一个 key 的值——不用引入解析库，
// 一个小函数就够，跟 main.swift 里 hasValidCanvasConfig() 的手动解析是同一个思路。
func readEnvValue(_ key: String) -> String? {
    let envPath = projectDir + "/.env"
    guard let content = try? String(contentsOfFile: envPath, encoding: .utf8) else { return nil }
    for line in content.split(separator: "\n") {
        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0] == key else { continue }
        let value = parts[1].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
    return nil
}
