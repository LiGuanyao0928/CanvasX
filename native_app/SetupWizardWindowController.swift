import Cocoa

// 首次使用引导：连接 Canvas 账号 → 选课程 → (可选)设置手机推送 → 完成。
// 每一步都是独立的一块视图，塞进同一个 stepContainer 里，跟主窗口切换
// 作业看板/课程资料/成绩那套"整体替换内容视图"的思路一致。
class SetupWizardWindowController: NSWindowController {
    var onComplete: (() -> Void)?

    private var canvasURLValue = ""
    private var canvasTokenValue = ""
    private var allCourses: [CanvasCourse] = []
    private var selectedCourseIDs: Set<Int> = []
    private var notifyMethod = "none"
    private var ntfyTopicValue = ""
    private var discordWebhookValue = ""
    private var shortcutsNameValue = ""
    private var rememberMeValue = true

    private var stepContainer: NSView!
    private var currentStepView: NSView?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 760),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "欢迎使用 Canvas 作业追踪"
        window.center()
        self.init(window: window)
        buildContainer()
        showStep1()
    }

    override init(window: NSWindow?) {
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildContainer() {
        guard let contentView = window?.contentView else { return }
        stepContainer = NSView()
        stepContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stepContainer)
        NSLayoutConstraint.activate([
            stepContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            stepContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stepContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stepContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    private func setStepView(_ view: NSView) {
        currentStepView?.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        stepContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: stepContainer.topAnchor),
            view.leadingAnchor.constraint(equalTo: stepContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: stepContainer.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: stepContainer.bottomAnchor),
        ])
        currentStepView = view
    }

    // 每一步共用的外层排版：标题+提示+内容+按钮，靠左对齐、离窗口边缘留固定间距。
    // 用 leading/trailing 贴边宽度不固定的写法（不是先前作业提醒编辑窗口那种居中卡片），
    // 这样长短不一的内容（尤其课程名有长有短）都能正常换行，不用来回猜尺寸。
    private func wrap(_ stack: NSStackView) -> NSView {
        let wrapper = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 32),
            stack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -32),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: wrapper.bottomAnchor, constant: -24),
        ])
        return wrapper
    }

    private func stepTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 18)
        return label
    }

    private func hintLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 400
        return label
    }

    private func fieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        return label
    }

    // MARK: - 第 1 步：连接 Canvas 账号

    private var urlField: NSTextField!
    private var tokenField: NSTextField!
    private var step1ErrorLabel: NSTextField!
    private var step1NextButton: NSButton!
    private var step1Spinner: NSProgressIndicator!
    private var step1HelpLabel: NSTextField!
    private var privacyCheckbox: NSButton!
    private var rememberCheckbox: NSButton!

    // 登录页重新设计：图标+居中标题的"登录屏"观感，字段装进一张卡片里，
    // 不再是跟第2/3步一样的左对齐大段文字——这一步是同学们对这个 App 的
    // 第一印象，单独给一个更像样的视觉处理。
    private func showStep1() {
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 60).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 60).isActive = true

        let title = NSTextField(labelWithString: "连接你的 Canvas 账号")
        title.font = .boldSystemFont(ofSize: 20)
        title.alignment = .center

        let subtitle = hintLabel("登录一次，之后每天自动帮你追作业、算成绩、整理课程资料")
        subtitle.alignment = .center
        subtitle.textColor = .secondaryLabelColor
        subtitle.preferredMaxLayoutWidth = 360

        let hint = hintLabel("在 Canvas 网页里，进入「账户 → 设置」，拉到最下面点「+新建访问令牌」，把生成的 Token 粘贴到下面。网址就是你平时登录 Canvas 用的那个网址（不用带后面的路径）。")
        hint.preferredMaxLayoutWidth = 340

        let urlLabel = fieldLabel("Canvas 网址")
        urlField = NSTextField()
        urlField.placeholderString = "https://yourschool.instructure.com"
        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlField.widthAnchor.constraint(equalToConstant: 340).isActive = true
        urlField.stringValue = canvasURLValue

        let tokenLabel = fieldLabel("Access Token")
        tokenField = NSSecureTextField()
        tokenField.translatesAutoresizingMaskIntoConstraints = false
        tokenField.widthAnchor.constraint(equalToConstant: 340).isActive = true
        tokenField.stringValue = canvasTokenValue

        let fieldsStack = NSStackView(views: [hint, urlLabel, urlField, tokenLabel, tokenField])
        fieldsStack.orientation = .vertical
        fieldsStack.alignment = .leading
        fieldsStack.spacing = 8
        fieldsStack.setCustomSpacing(16, after: hint)
        let card = makeCard(fieldsStack)

        let helpToggle = NSButton(title: "生成不了 / 找不到 Token？", target: self, action: #selector(toggleTokenHelp))
        helpToggle.isBordered = false
        helpToggle.bezelStyle = .inline
        helpToggle.font = .systemFont(ofSize: 11)
        helpToggle.contentTintColor = .linkColor

        step1HelpLabel = hintLabel("这通常是学校 Canvas 管理员关掉了学生自主生成 Token 的权限，不是你操作有问题。\n解决办法：找任课老师或学校 IT/教务，请他们在 Canvas 管理后台给你开启「用户\n自主生成访问令牌」的权限。目前没有不需要 Token 就能用的替代方案——Canvas\n官方的应用授权（OAuth）流程需要学校管理员审批，普通学生个人没法自己申请。")
        step1HelpLabel.preferredMaxLayoutWidth = 340
        step1HelpLabel.isHidden = true

        step1ErrorLabel = hintLabel("")
        step1ErrorLabel.alignment = .center
        step1ErrorLabel.textColor = .systemRed
        step1ErrorLabel.isHidden = true

        // 隐私/数据使用说明——直接给同学用之前，这个必须让人先看一眼、勾选了才能继续，
        // 不能藏在某个链接后面。内容跟 README 里的口径一致：本地跑、不上传除 Canvas/
        // 用户自选推送服务以外的任何服务器。
        let privacyText = hintLabel("这个 App 完全在你自己电脑上运行：Canvas 网址和 Token 只保存在本机，不会\n上传到 Canvas 官方以外的任何服务器；开启手机推送的话，作业标题会发给你自\n己选的推送服务（ntfy/Discord/快捷指令）。这是同学做的个人小工具，不是学\n校或 Canvas 官方产品。")
        privacyText.preferredMaxLayoutWidth = 340

        privacyCheckbox = NSButton(checkboxWithTitle: "我已阅读并同意上面的说明", target: self, action: #selector(privacyCheckboxChanged(_:)))
        privacyCheckbox.font = .systemFont(ofSize: 12)

        let privacyStack = NSStackView(views: [privacyText, privacyCheckbox])
        privacyStack.orientation = .vertical
        privacyStack.alignment = .leading
        privacyStack.spacing = 8

        // "记住我"默认勾选（大多数人是在自己的私人电脑上用）；如果是图书馆/机房这种
        // 公用电脑，取消勾选后退出 App 会自动清掉这台电脑上的登录信息，不会留给下一个人。
        rememberCheckbox = NSButton(checkboxWithTitle: "记住我的登录信息（下次自动打开，不用重新输入）", target: nil, action: nil)
        rememberCheckbox.state = .on
        rememberCheckbox.font = .systemFont(ofSize: 12)

        let rememberWarning = hintLabel("⚠️ 不是你自己的私人电脑（比如图书馆/机房的公用电脑）？取消勾选——退出\nApp 时会自动清除这台电脑上的登录信息，不会留给下一个用的人看到。")
        rememberWarning.textColor = .systemOrange
        rememberWarning.preferredMaxLayoutWidth = 340

        let rememberStack = NSStackView(views: [rememberCheckbox, rememberWarning])
        rememberStack.orientation = .vertical
        rememberStack.alignment = .leading
        rememberStack.spacing = 6

        step1Spinner = NSProgressIndicator()
        step1Spinner.style = .spinning
        step1Spinner.controlSize = .small
        step1Spinner.isHidden = true

        step1NextButton = NSButton(title: "下一步", target: self, action: #selector(step1NextTapped))
        step1NextButton.bezelStyle = .rounded
        step1NextButton.keyEquivalent = "\r"
        step1NextButton.isEnabled = false

        let bottomRow = NSStackView(views: [step1Spinner, step1NextButton])
        bottomRow.orientation = .horizontal
        bottomRow.spacing = 10

        let stack = NSStackView(views: [icon, title, subtitle, card, helpToggle, step1HelpLabel, privacyStack, rememberStack, step1ErrorLabel, bottomRow])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.setCustomSpacing(4, after: icon)
        stack.setCustomSpacing(20, after: subtitle)
        stack.setCustomSpacing(6, after: card)
        stack.setCustomSpacing(16, after: privacyStack)
        stack.setCustomSpacing(20, after: rememberStack)

        setStepView(wrap(stack))
    }

    @objc private func toggleTokenHelp() {
        step1HelpLabel.isHidden.toggle()
    }

    @objc private func privacyCheckboxChanged(_ sender: NSButton) {
        step1NextButton.isEnabled = sender.state == .on
    }

    @objc private func step1NextTapped() {
        let url = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, !token.isEmpty else {
            step1ErrorLabel.stringValue = "网址和 Token 都要填"
            step1ErrorLabel.isHidden = false
            return
        }
        step1ErrorLabel.isHidden = true
        step1Spinner.isHidden = false
        step1Spinner.startAnimation(nil)
        step1NextButton.isEnabled = false

        CanvasAPI.fetchCourses(baseURL: url, token: token) { [weak self] result in
            guard let self = self else { return }
            self.step1Spinner.stopAnimation(nil)
            self.step1Spinner.isHidden = true
            self.step1NextButton.isEnabled = self.privacyCheckbox.state == .on
            switch result {
            case .success(let courses):
                self.canvasURLValue = url
                self.canvasTokenValue = token
                self.rememberMeValue = self.rememberCheckbox.state == .on
                self.allCourses = courses
                self.showStep2()
            case .failure(let error):
                self.step1ErrorLabel.stringValue = "连接失败：\(error.localizedDescription)"
                self.step1ErrorLabel.isHidden = false
            }
        }
    }

    // MARK: - 第 2 步：选课程

    private var courseCheckboxes: [(id: Int, checkbox: NSButton)] = []

    private func showStep2() {
        let title = stepTitle("第 2 步 · 选择要追踪的课程")
        let hint = hintLabel("勾选真正要交作业的课。像「学术诚信培训」「新生导师」这类不是正课的模块不用选——之后随时能在菜单栏「查看 → 重新运行设置向导」里改。")

        let listStack = NSStackView()
        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 8
        listStack.translatesAutoresizingMaskIntoConstraints = false

        courseCheckboxes = []
        for course in allCourses {
            let checkbox = NSButton(checkboxWithTitle: course.displayName, target: nil, action: nil)
            checkbox.state = selectedCourseIDs.contains(course.id) ? .on : .off
            listStack.addArrangedSubview(checkbox)
            courseCheckboxes.append((course.id, checkbox))
        }
        if allCourses.isEmpty {
            listStack.addArrangedSubview(NSTextField(labelWithString: "没有拉到课程，返回上一步检查一下网址和 Token"))
        }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.widthAnchor.constraint(equalToConstant: 400).isActive = true
        scrollView.heightAnchor.constraint(equalToConstant: 260).isActive = true
        scrollView.documentView = listStack
        NSLayoutConstraint.activate([
            listStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 6),
            listStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 10),
            listStack.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.trailingAnchor, constant: -10),
        ])

        let backButton = NSButton(title: "上一步", target: self, action: #selector(step2BackTapped))
        let nextButton = NSButton(title: "下一步", target: self, action: #selector(step2NextTapped))
        nextButton.bezelStyle = .rounded
        nextButton.keyEquivalent = "\r"
        let bottomRow = NSStackView(views: [backButton, nextButton])
        bottomRow.orientation = .horizontal
        bottomRow.spacing = 10

        let stack = NSStackView(views: [title, hint, scrollView, bottomRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.setCustomSpacing(20, after: hint)
        stack.setCustomSpacing(20, after: scrollView)

        setStepView(wrap(stack))
    }

    @objc private func step2BackTapped() {
        selectedCourseIDs = Set(courseCheckboxes.filter { $0.checkbox.state == .on }.map { $0.id })
        showStep1()
    }

    @objc private func step2NextTapped() {
        selectedCourseIDs = Set(courseCheckboxes.filter { $0.checkbox.state == .on }.map { $0.id })
        showStep3()
    }

    // MARK: - 第 3 步：手机推送（可选，几种方式选一个）

    private var notifyRadios: [(method: String, button: NSButton)] = []
    private var notifyDetailContainer: NSView!
    private var ntfyField: NSTextField!
    private var discordField: NSTextField!
    private var shortcutsField: NSTextField!

    private func showStep3() {
        let title = stepTitle("第 3 步 · 手机推送提醒（可选）")
        let hint = hintLabel("不开也可以，随时打开 App 看网页仪表盘一样能看到要交的作业。要开的话选一种方式：")

        notifyRadios = []
        let options: [(String, String)] = [
            ("none", "不需要，只看网页仪表盘"),
            ("ntfy", "ntfy（推荐）—— 跨平台，手机装个 App 就行"),
            ("discord", "Discord —— 发到你自己的 Discord 频道"),
            ("shortcuts", "苹果快捷指令 —— 纯苹果自家生态，不用第三方服务"),
        ]
        let radioStack = NSStackView()
        radioStack.orientation = .vertical
        radioStack.alignment = .leading
        radioStack.spacing = 8
        for (method, label) in options {
            let radio = NSButton(radioButtonWithTitle: label, target: self, action: #selector(notifyMethodChanged(_:)))
            radio.font = .systemFont(ofSize: 12)
            radio.state = (method == notifyMethod) ? .on : .off
            radioStack.addArrangedSubview(radio)
            notifyRadios.append((method, radio))
        }

        notifyDetailContainer = NSView()
        notifyDetailContainer.translatesAutoresizingMaskIntoConstraints = false
        notifyDetailContainer.widthAnchor.constraint(equalToConstant: 400).isActive = true

        let backButton = NSButton(title: "上一步", target: self, action: #selector(step3BackTapped))
        let nextButton = NSButton(title: "完成", target: self, action: #selector(step3FinishTapped))
        nextButton.bezelStyle = .rounded
        nextButton.keyEquivalent = "\r"
        let bottomRow = NSStackView(views: [backButton, nextButton])
        bottomRow.orientation = .horizontal
        bottomRow.spacing = 10

        let stack = NSStackView(views: [title, hint, radioStack, notifyDetailContainer, bottomRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.setCustomSpacing(20, after: hint)
        stack.setCustomSpacing(20, after: notifyDetailContainer)

        setStepView(wrap(stack))
        updateNotifyDetail()
    }

    @objc private func notifyMethodChanged(_ sender: NSButton) {
        guard let match = notifyRadios.first(where: { $0.button === sender }) else { return }
        notifyMethod = match.method
        updateNotifyDetail()
    }

    private func updateNotifyDetail() {
        for sub in notifyDetailContainer.subviews { sub.removeFromSuperview() }

        let detail: NSView
        switch notifyMethod {
        case "ntfy":
            let hint = hintLabel("手机 App Store 搜索安装「ntfy」，打开后点右下角 ＋，粘贴下面这个频道名订阅它（频道名相当于一个不公开的密钥，不要告诉别人）：")
            ntfyField = NSTextField()
            ntfyField.stringValue = ntfyTopicValue.isEmpty ? "canvas-\(Int.random(in: 100_000...999_999))" : ntfyTopicValue
            ntfyField.translatesAutoresizingMaskIntoConstraints = false
            ntfyField.widthAnchor.constraint(equalToConstant: 300).isActive = true
            let stack = NSStackView(views: [hint, ntfyField])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 8
            detail = stack
        case "discord":
            let hint = hintLabel("在你的 Discord 服务器里：频道设置 →「整合」→「Webhook」→「新增 Webhook」，复制生成的网址粘贴到下面（不用邀请机器人，纯网址推送）：")
            discordField = NSTextField()
            discordField.placeholderString = "https://discord.com/api/webhooks/..."
            discordField.stringValue = discordWebhookValue
            discordField.translatesAutoresizingMaskIntoConstraints = false
            discordField.widthAnchor.constraint(equalToConstant: 340).isActive = true
            let stack = NSStackView(views: [hint, discordField])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 8
            detail = stack
        case "shortcuts":
            let hint = hintLabel("在 Mac 的「快捷指令」App 里新建一个快捷指令：加一个「获取输入的文本」动作，再加一个「发送信息」动作（收件人填你自己），给这个快捷指令起个名字，填在下面：")
            shortcutsField = NSTextField()
            shortcutsField.stringValue = shortcutsNameValue.isEmpty ? "Canvas提醒" : shortcutsNameValue
            shortcutsField.translatesAutoresizingMaskIntoConstraints = false
            shortcutsField.widthAnchor.constraint(equalToConstant: 300).isActive = true
            let stack = NSStackView(views: [hint, shortcutsField])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 8
            detail = stack
        default:
            detail = NSView()
        }

        detail.translatesAutoresizingMaskIntoConstraints = false
        notifyDetailContainer.addSubview(detail)
        NSLayoutConstraint.activate([
            detail.topAnchor.constraint(equalTo: notifyDetailContainer.topAnchor),
            detail.leadingAnchor.constraint(equalTo: notifyDetailContainer.leadingAnchor),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: notifyDetailContainer.trailingAnchor),
            detail.bottomAnchor.constraint(equalTo: notifyDetailContainer.bottomAnchor),
        ])
    }

    @objc private func step3BackTapped() {
        showStep2()
    }

    @objc private func step3FinishTapped() {
        ntfyTopicValue = ntfyField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        discordWebhookValue = discordField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        shortcutsNameValue = shortcutsField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        showStep4()
    }

    // MARK: - 第 4 步：写配置 + 首次同步

    private func showStep4() {
        let title = stepTitle("正在完成设置…")
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.startAnimation(nil)

        let stack = NSStackView(views: [title, spinner])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false

        let wrapper = NSView()
        wrapper.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
        ])
        setStepView(wrapper)

        writeConfigAndSync()
    }

    private func writeConfigAndSync() {
        var envLines = [
            "CANVAS_API_TOKEN=\(canvasTokenValue)",
            "CANVAS_BASE_URL=\(canvasURLValue)",
            "NOTIFY_METHOD=\(notifyMethod)",
        ]
        switch notifyMethod {
        case "ntfy":
            envLines.append("NTFY_TOPIC=\(ntfyTopicValue)")
        case "discord":
            envLines.append("DISCORD_WEBHOOK_URL=\(discordWebhookValue)")
        case "shortcuts":
            envLines.append("SHORTCUTS_NAME=\(shortcutsNameValue)")
        default:
            break
        }
        try? (envLines.joined(separator: "\n") + "\n").write(
            toFile: projectDir + "/.env", atomically: true, encoding: .utf8)

        let idsText = selectedCourseIDs.sorted().map(String.init).joined(separator: ", ")
        try? "{\"course_ids\": [\(idsText)]}\n".write(
            toFile: projectDir + "/tracked_courses.json", atomically: true, encoding: .utf8)

        // "记住我"没勾选（公用电脑）：记下这个偏好，AppDelegate 在 App 退出时会读它，
        // 决定要不要把刚写的这些本机文件自动清掉。
        UserDefaults.standard.set(rememberMeValue, forKey: "rememberLogin")

        let task = Process()
        task.currentDirectoryURL = URL(fileURLWithPath: projectDir)
        task.executableURL = URL(fileURLWithPath: projectDir + "/.venv/bin/python3")
        task.arguments = ["canvas_sync.py", "--refresh"]
        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.window?.close()
                self?.onComplete?()
            }
        }
        do {
            try task.run()
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.window?.close()
                self?.onComplete?()
            }
        }
    }
}
