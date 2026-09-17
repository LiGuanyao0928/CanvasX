import Cocoa

class AlarmRowView: NSTableCellView {
    let timeLabel = NSTextField(labelWithString: "")
    let repeatLabel = NSTextField(labelWithString: "")
    let toggle = NSSwitch()
    let deleteButton = NSButton()
    var onToggle: ((Bool) -> Void)?
    var onDelete: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .regular)
        timeLabel.frame = NSRect(x: 16, y: 22, width: 120, height: 30)
        addSubview(timeLabel)

        repeatLabel.font = .systemFont(ofSize: 12)
        repeatLabel.textColor = .secondaryLabelColor
        repeatLabel.frame = NSRect(x: 16, y: 6, width: 260, height: 16)
        addSubview(repeatLabel)

        toggle.frame = NSRect(x: 320, y: 18, width: 40, height: 24)
        toggle.target = self
        toggle.action = #selector(switchFlipped)
        addSubview(toggle)

        deleteButton.frame = NSRect(x: 380, y: 16, width: 28, height: 28)
        deleteButton.isBordered = false
        deleteButton.bezelStyle = .regularSquare
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "删除")
        deleteButton.contentTintColor = .secondaryLabelColor
        deleteButton.target = self
        deleteButton.action = #selector(deleteTapped)
        deleteButton.toolTip = "删除这条提醒时间"
        addSubview(deleteButton)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func switchFlipped() {
        onToggle?(toggle.state == .on)
    }

    @objc private func deleteTapped() {
        onDelete?()
    }

    func configure(with alarm: Alarm, onToggle: @escaping (Bool) -> Void, onDelete: @escaping () -> Void) {
        timeLabel.stringValue = alarm.timeText
        repeatLabel.stringValue = alarm.repeatText
        toggle.state = alarm.enabled ? .on : .off
        self.onToggle = onToggle
        self.onDelete = onDelete
    }
}

class ScheduleViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private var alarms: [Alarm] = []
    private var tableView: NSTableView!

    override func loadView() {
        // 全部改用 Auto Layout 约束贴边，不用固定 frame——这个视图现在装在左侧边栏+
        // 分屏窗口里，实际尺寸不再是当初设计时假设的 900x760，固定 frame 会导致
        // 元素位置和真实边界对不上（"添加提醒时间"按钮点不到就是这个原因）。
        let container = NSView()
        container.wantsLayer = true

        let headerLabel = NSTextField(labelWithString: "自动同步提醒时间")
        headerLabel.font = .boldSystemFont(ofSize: 20)
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        let subLabel = NSTextField(labelWithString: "到点会自动同步 Canvas 数据并推送手机提醒。每条都能单独开关，可以设置只在某几天重复。")
        subLabel.font = .systemFont(ofSize: 12)
        subLabel.textColor = .secondaryLabelColor
        subLabel.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = 56
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)
        tableView.autoresizingMask = [.width]

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("alarm"))
        column.width = 680
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        scrollView.documentView = tableView

        let addBtn = NSButton(title: "＋ 添加提醒时间", target: self, action: #selector(addTapped))
        addBtn.bezelStyle = .rounded
        addBtn.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(headerLabel)
        container.addSubview(subLabel)
        container.addSubview(scrollView)
        container.addSubview(addBtn)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            headerLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            subLabel.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 6),
            subLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            subLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),

            scrollView.topAnchor.constraint(equalTo: subLabel.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            scrollView.bottomAnchor.constraint(equalTo: addBtn.topAnchor, constant: -16),

            addBtn.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            addBtn.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            addBtn.widthAnchor.constraint(equalToConstant: 160),
            addBtn.heightAnchor.constraint(equalToConstant: 30),
        ])

        self.view = container
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reload()
    }

    func reload() {
        alarms = ScheduleStore.load()
        tableView?.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return alarms.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = AlarmRowView(frame: NSRect(x: 0, y: 0, width: 680, height: 56))
        let alarm = alarms[row]
        cell.configure(with: alarm, onToggle: { [weak self] isOn in
            guard let self = self else { return }
            self.alarms[row].enabled = isOn
            ScheduleStore.save(self.alarms)
        }, onDelete: { [weak self] in
            guard let self = self else { return }
            self.alarms.remove(at: row)
            ScheduleStore.save(self.alarms)
            self.reload()
        })
        return cell
    }

    @objc private func rowDoubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < alarms.count else { return }
        editAlarm(at: row)
    }

    @objc private func addTapped() {
        let editor = AlarmEditorWindowController(alarm: nil, isNew: true)
        editor.onSave = { [weak self] newAlarm in
            guard let self = self else { return }
            self.alarms.append(newAlarm)
            ScheduleStore.save(self.alarms)
            self.reload()
        }
        presentEditor(editor)
    }

    private func editAlarm(at row: Int) {
        let editor = AlarmEditorWindowController(alarm: alarms[row], isNew: false)
        editor.onSave = { [weak self] updated in
            guard let self = self else { return }
            self.alarms[row] = updated
            ScheduleStore.save(self.alarms)
            self.reload()
        }
        editor.onDelete = { [weak self] in
            guard let self = self else { return }
            self.alarms.remove(at: row)
            ScheduleStore.save(self.alarms)
            self.reload()
        }
        presentEditor(editor)
    }

    private func presentEditor(_ editor: AlarmEditorWindowController) {
        guard let parentWindow = view.window, let sheet = editor.window else { return }
        parentWindow.beginSheet(sheet) { _ in
            _ = editor // keep a strong reference alive until the sheet closes
        }
    }
}
