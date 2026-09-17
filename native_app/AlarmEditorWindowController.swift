import Cocoa

// 圆形色块日期按钮：选中是实心蓝底白字，没选是浅灰底黑字，仿苹果闹钟的重复选择样式
class DayToggleButton: NSButton {
    var isOn: Bool = false {
        didSet { updateAppearance() }
    }
    private let label: String

    init(label: String) {
        self.label = label
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 36).isActive = true
        heightAnchor.constraint(equalToConstant: 36).isActive = true
        wantsLayer = true
        isBordered = false
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.width / 2
        layer?.masksToBounds = true
    }

    private func updateAppearance() {
        layer?.backgroundColor = (isOn ? NSColor.controlAccentColor : NSColor.quaternaryLabelColor).cgColor
        let color: NSColor = isOn ? .white : .labelColor
        attributedTitle = NSAttributedString(
            string: label,
            attributes: [
                .foregroundColor: color,
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            ]
        )
    }

    override func mouseDown(with event: NSEvent) {
        isOn.toggle()
    }
}

// 不用时钟图案了——直接显示一个数字，鼠标/触控板在上面滚动就能加减，
// 参考的是滚轮式时间选择器（往下滚数字变大，往上滚变小），比时钟图案更直接，
// 也不用再纠结"时钟图案是否在竖直中心"这种问题。
class ScrollableTimeUnit: NSView {
    var value: Int {
        didSet {
            guard oldValue != value else { return }
            updateLabel()
        }
    }
    private let range: ClosedRange<Int>
    private let label = NSTextField(labelWithString: "")

    init(value: Int, range: ClosedRange<Int>) {
        self.value = value
        self.range = range
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        label.font = .monospacedDigitSystemFont(ofSize: 44, weight: .semibold)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalToConstant: 84),
            heightAnchor.constraint(equalToConstant: 60),
        ])
        updateLabel()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateLabel() {
        label.stringValue = String(format: "%02d", value)
    }

    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) > 0.5 else { return }
        if event.scrollingDeltaY < 0 {
            value = value == range.upperBound ? range.lowerBound : value + 1
        } else {
            value = value == range.lowerBound ? range.upperBound : value - 1
        }
    }
}

class AlarmEditorWindowController: NSWindowController {
    var onSave: ((Alarm) -> Void)?
    var onDelete: (() -> Void)?

    private var alarm: Alarm
    private let isNew: Bool
    private var hourUnit: ScrollableTimeUnit!
    private var minuteUnit: ScrollableTimeUnit!
    private var dayButtons: [DayToggleButton] = []
    private var enabledCheckbox: NSButton!
    private var presetDayLists: [[Int]] = []

    init(alarm: Alarm?, isNew: Bool) {
        self.alarm = alarm ?? Alarm(id: UUID().uuidString, hour: 8, minute: 0, enabled: true, days: Array(0...6))
        self.isNew = isNew

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = isNew ? "添加提醒时间" : "编辑提醒时间"
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let titleLabel = NSTextField(labelWithString: "设置提醒时间")
        titleLabel.font = .boldSystemFont(ofSize: 16)
        titleLabel.alignment = .center

        hourUnit = ScrollableTimeUnit(value: alarm.hour, range: 0...23)
        minuteUnit = ScrollableTimeUnit(value: alarm.minute, range: 0...59)

        let colonLabel = NSTextField(labelWithString: ":")
        colonLabel.font = .monospacedDigitSystemFont(ofSize: 44, weight: .semibold)

        let timeRow = NSStackView(views: [hourUnit, colonLabel, minuteUnit])
        timeRow.orientation = .horizontal
        timeRow.spacing = 4
        timeRow.alignment = .centerY

        let scrollHint = NSTextField(labelWithString: "↕ 在数字上滚动调整")
        scrollHint.font = .systemFont(ofSize: 11)
        scrollHint.textColor = .secondaryLabelColor
        scrollHint.alignment = .center

        let repeatLabel = NSTextField(labelWithString: "重复")
        repeatLabel.font = .systemFont(ofSize: 12)
        repeatLabel.textColor = .secondaryLabelColor
        repeatLabel.alignment = .center

        let dayRow = NSStackView()
        dayRow.orientation = .horizontal
        dayRow.spacing = 6
        for (i, label) in Alarm.dayLabels.enumerated() {
            let btn = DayToggleButton(label: label)
            btn.isOn = alarm.days.contains(i)
            dayButtons.append(btn)
            dayRow.addArrangedSubview(btn)
        }

        let presets: [(String, [Int])] = [
            ("每天", Array(0...6)),
            ("工作日", [1, 2, 3, 4, 5]),
            ("周末", [0, 6]),
        ]
        presetDayLists = presets.map { $0.1 }
        let presetRow = NSStackView()
        presetRow.orientation = .horizontal
        presetRow.spacing = 6
        presetRow.distribution = .fillEqually
        for (i, preset) in presets.enumerated() {
            let btn = NSButton(title: preset.0, target: self, action: #selector(presetTapped(_:)))
            btn.tag = i
            btn.bezelStyle = .rounded
            btn.font = .systemFont(ofSize: 11)
            presetRow.addArrangedSubview(btn)
        }
        presetRow.translatesAutoresizingMaskIntoConstraints = false

        enabledCheckbox = NSButton(checkboxWithTitle: "启用", target: nil, action: nil)
        enabledCheckbox.state = alarm.enabled ? .on : .off

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 12

        let cancelBtn = NSButton(title: "取消", target: self, action: #selector(cancelTapped))
        buttonRow.addArrangedSubview(cancelBtn)
        if !isNew {
            let deleteBtn = NSButton(title: "删除", target: self, action: #selector(deleteTapped))
            buttonRow.addArrangedSubview(deleteBtn)
        }
        let saveBtn = NSButton(title: "保存", target: self, action: #selector(saveTapped))
        saveBtn.keyEquivalent = "\r"
        buttonRow.addArrangedSubview(saveBtn)
        for view in buttonRow.arrangedSubviews {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalToConstant: 90).isActive = true
        }

        // 不再需要单独把某个元素钉在窗口正中心——去掉了时钟图案以后，
        // 所有内容量级差不多对称，直接用一根竖直 stack 整体居中就足够自然。
        let mainStack = NSStackView(views: [
            titleLabel, timeRow, scrollHint, repeatLabel, dayRow, presetRow, enabledCheckbox, buttonRow,
        ])
        mainStack.orientation = .vertical
        mainStack.alignment = .centerX
        mainStack.spacing = 18
        mainStack.setCustomSpacing(12, after: titleLabel)
        mainStack.setCustomSpacing(4, after: timeRow)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            mainStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            mainStack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 24),
            mainStack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),
            mainStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 20),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),

            // presetRow 和 dayRow 都是 mainStack 的 arranged subview 了，有共同祖先，
            // 这个宽度对齐约束在这里（加进 mainStack 之后）才合法生效。
            presetRow.widthAnchor.constraint(equalTo: dayRow.widthAnchor),
        ])
    }

    @objc private func presetTapped(_ sender: NSButton) {
        let days = Set(presetDayLists[sender.tag])
        for (i, btn) in dayButtons.enumerated() {
            btn.isOn = days.contains(i)
        }
    }

    @objc private func cancelTapped() {
        window?.sheetParent?.endSheet(window!, returnCode: .cancel)
    }

    @objc private func deleteTapped() {
        onDelete?()
        window?.sheetParent?.endSheet(window!, returnCode: .cancel)
    }

    @objc private func saveTapped() {
        alarm.hour = hourUnit.value
        alarm.minute = minuteUnit.value
        alarm.enabled = enabledCheckbox.state == .on
        alarm.days = dayButtons.enumerated().filter { $0.element.isOn }.map { $0.offset }
        onSave?(alarm)
        window?.sheetParent?.endSheet(window!, returnCode: .OK)
    }
}
