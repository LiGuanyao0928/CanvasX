import Cocoa

// 外观（浅色/深色/跟随系统）、语言（只影响这个设置面板自己的文字）、账号（换Token/退出登录）、
// 其他（立即同步/打开日志/关于）。偏好存 UserDefaults，下次开窗还记得住。

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
        // 但已经在屏幕上的窗口不一定会重新计算 effectiveAppearance、触发子视图的
        // viewDidChangeEffectiveAppearance（这正是卡片背景切换后没刷新的根因）。
        // 显式挨个把已开窗口的 appearance 也设一遍，强制它们立刻重算。
        for window in NSApp.windows {
            window.appearance = resolved
        }
    }
}

enum SettingsLanguage: String, Equatable {
    case zh, en

    static var current: SettingsLanguage {
        SettingsLanguage(rawValue: UserDefaults.standard.string(forKey: "settingsLanguage") ?? "zh") ?? .zh
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: "settingsLanguage")
    }
}

// 只覆盖设置面板本身出现的文字——按用户的要求，先不做全局翻译，作业看板/成绩/
// 资料那些网页内容目前还是纯中文。
private let settingsStrings: [String: (zh: String, en: String)] = [
    "title": ("设置", "Settings"),
    "appearance": ("外观", "Appearance"),
    "appearance.system": ("跟随系统", "System"),
    "appearance.light": ("浅色", "Light"),
    "appearance.dark": ("深色", "Dark"),
    "language": ("语言（仅设置面板文字）", "Language (this panel only)"),
    "account": ("账号", "Account"),
    "account.currentURL": ("当前 Canvas 网址", "Current Canvas URL"),
    "account.rerunWizard": ("重新选课 / 更换 Token", "Change Courses / Token"),
    "account.logout": ("退出登录", "Log Out"),
    "account.logout.confirmTitle": ("确定要退出登录吗？", "Log out?"),
    "account.logout.confirmMessage": (
        "会清除这台电脑上保存的 Canvas 账号信息、选课设置和已同步的数据（方便下一个用这台\n电脑的同学重新开始）。下次打开 App 会重新走一遍设置向导。",
        "This clears the saved Canvas credentials, course selection, and synced data on this\ncomputer (so the next classmate using it starts fresh). You'll go through setup again."
    ),
    "account.logout.confirmButton": ("退出登录", "Log Out"),
    "account.logout.cancelButton": ("取消", "Cancel"),
    "more": ("其他", "More"),
    "more.syncNow": ("立即同步", "Sync Now"),
    "more.syncing": ("同步中…", "Syncing…"),
    "more.syncDone": ("✓ 已同步", "✓ Synced"),
    "more.openLogs": ("打开日志文件夹", "Open Logs Folder"),
    "more.about": ("关于", "About"),
    "more.aboutText": (
        "Canvas 作业追踪 · 个人项目，完全在本机运行，账号信息和作业数据不会上传到\n除 Canvas 官方以外的任何服务器。",
        "Canvas Assignment Tracker · A personal project that runs entirely on your machine.\nYour credentials and assignment data are never uploaded anywhere except Canvas itself."
    ),
]

class SettingsWindowController: NSWindowController {
    var onRerunWizard: (() -> Void)?
    var onLogout: (() -> Void)?
    var onSyncNow: ((@escaping () -> Void) -> Void)?

    private var language = SettingsLanguage.current
    private var contentContainer: NSView!
    private var syncButton: NSButton!
    private var syncSpinner: NSProgressIndicator!
    private var syncStatusLabel: NSTextField!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        self.init(window: window)
        buildContainer()
        render()
    }

    override init(window: NSWindow?) {
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func t(_ key: String) -> String {
        let pair = settingsStrings[key] ?? (zh: key, en: key)
        return language == .zh ? pair.zh : pair.en
    }

    private func buildContainer() {
        guard let contentView = window?.contentView else { return }
        contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentContainer)
        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        return label
    }

    // MARK: - 整体布局

    private func render() {
        window?.title = t("title")
        for sub in contentContainer.subviews { sub.removeFromSuperview() }

        let sections = NSStackView(views: [
            buildAppearanceSection(),
            buildLanguageSection(),
            buildAccountSection(),
            buildMoreSection(),
        ])
        sections.orientation = .vertical
        sections.alignment = .leading
        sections.spacing = 16
        sections.translatesAutoresizingMaskIntoConstraints = false

        contentContainer.addSubview(sections)
        NSLayoutConstraint.activate([
            sections.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 24),
            sections.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 24),
            sections.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -24),
        ])
    }

    // MARK: - 外观

    private func buildAppearanceSection() -> NSView {
        let label = sectionLabel(t("appearance"))
        let segmented = NSSegmentedControl(
            labels: [t("appearance.system"), t("appearance.light"), t("appearance.dark")],
            trackingMode: .selectOne,
            target: self,
            action: #selector(appearanceChanged(_:))
        )
        let modes: [AppearanceMode] = [.system, .light, .dark]
        segmented.selectedSegment = modes.firstIndex(of: AppearanceMode.current) ?? 0
        segmented.identifier = NSUserInterfaceItemIdentifier("appearanceSegmented")

        let stack = NSStackView(views: [label, segmented])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        return makeCard(stack)
    }

    @objc private func appearanceChanged(_ sender: NSSegmentedControl) {
        let modes: [AppearanceMode] = [.system, .light, .dark]
        modes[sender.selectedSegment].apply()
    }

    // MARK: - 语言（仅本面板）

    private func buildLanguageSection() -> NSView {
        let label = sectionLabel(t("language"))
        let segmented = NSSegmentedControl(
            labels: ["中文", "English"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(languageChanged(_:))
        )
        segmented.selectedSegment = language == .zh ? 0 : 1

        let stack = NSStackView(views: [label, segmented])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        return makeCard(stack)
    }

    @objc private func languageChanged(_ sender: NSSegmentedControl) {
        language = sender.selectedSegment == 0 ? .zh : .en
        language.save()
        render()
    }

    // MARK: - 账号

    private func buildAccountSection() -> NSView {
        let label = sectionLabel(t("account"))

        let urlTitle = NSTextField(labelWithString: t("account.currentURL") + "：")
        urlTitle.font = .systemFont(ofSize: 12)
        urlTitle.textColor = .secondaryLabelColor
        let urlValue = NSTextField(labelWithString: readEnvValue("CANVAS_BASE_URL") ?? "—")
        urlValue.font = .systemFont(ofSize: 12, weight: .medium)
        urlValue.lineBreakMode = .byTruncatingMiddle
        let urlRow = NSStackView(views: [urlTitle, urlValue])
        urlRow.orientation = .horizontal
        urlRow.spacing = 4

        let rerunButton = NSButton(title: t("account.rerunWizard"), target: self, action: #selector(rerunWizardTapped))
        rerunButton.bezelStyle = .rounded

        let logoutButton = NSButton(title: t("account.logout"), target: self, action: #selector(logoutTapped))
        logoutButton.bezelStyle = .rounded
        logoutButton.contentTintColor = .systemRed

        let buttonRow = NSStackView(views: [rerunButton, logoutButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        let stack = NSStackView(views: [label, urlRow, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(4, after: label)
        return makeCard(stack)
    }

    @objc private func rerunWizardTapped() {
        window?.close()
        onRerunWizard?()
    }

    @objc private func logoutTapped() {
        let alert = NSAlert()
        alert.messageText = t("account.logout.confirmTitle")
        alert.informativeText = t("account.logout.confirmMessage")
        alert.addButton(withTitle: t("account.logout.confirmButton"))
        alert.addButton(withTitle: t("account.logout.cancelButton"))
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        window?.close()
        onLogout?()
    }

    // MARK: - 其他

    private func buildMoreSection() -> NSView {
        let label = sectionLabel(t("more"))

        syncButton = NSButton(title: t("more.syncNow"), target: self, action: #selector(syncNowTapped))
        syncButton.bezelStyle = .rounded
        syncSpinner = NSProgressIndicator()
        syncSpinner.style = .spinning
        syncSpinner.controlSize = .small
        syncSpinner.isHidden = true
        syncStatusLabel = NSTextField(labelWithString: "")
        syncStatusLabel.font = .systemFont(ofSize: 11)
        syncStatusLabel.textColor = .secondaryLabelColor
        let syncRow = NSStackView(views: [syncButton, syncSpinner, syncStatusLabel])
        syncRow.orientation = .horizontal
        syncRow.spacing = 8

        let logsButton = NSButton(title: t("more.openLogs"), target: self, action: #selector(openLogsTapped))
        logsButton.bezelStyle = .rounded

        let aboutLabel = sectionLabel(t("more.about"))
        let aboutText = NSTextField(wrappingLabelWithString: t("more.aboutText"))
        aboutText.font = .systemFont(ofSize: 11)
        aboutText.textColor = .secondaryLabelColor
        aboutText.preferredMaxLayoutWidth = 380

        let stack = NSStackView(views: [label, syncRow, logsButton, aboutLabel, aboutText])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(16, after: logsButton)
        return makeCard(stack)
    }

    @objc private func syncNowTapped() {
        syncButton.isEnabled = false
        syncSpinner.isHidden = false
        syncSpinner.startAnimation(nil)
        syncStatusLabel.stringValue = t("more.syncing")
        onSyncNow? { [weak self] in
            guard let self = self else { return }
            self.syncSpinner.stopAnimation(nil)
            self.syncSpinner.isHidden = true
            self.syncButton.isEnabled = true
            self.syncStatusLabel.stringValue = self.t("more.syncDone")
        }
    }

    @objc private func openLogsTapped() {
        let logsPath = projectDir + "/logs"
        try? FileManager.default.createDirectory(atPath: logsPath, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: logsPath))
    }
}
