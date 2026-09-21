import Cocoa

// ChatGPT 风格的配色：跟着系统深浅模式变化，不用 macOS 默认的蓝色高亮/毛玻璃侧边栏，
// 换成纯色背景 + 中性灰的选中态，参考 chatgpt.com 网页版的视觉语言。
extension NSColor {
    private static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    static let sidebarBackground = adaptive(
        light: NSColor(calibratedRed: 0.969, green: 0.969, blue: 0.973, alpha: 1),
        dark: NSColor(calibratedRed: 0.090, green: 0.090, blue: 0.090, alpha: 1)
    )
    static let contentBackground = adaptive(
        light: .white,
        dark: NSColor(calibratedRed: 0.129, green: 0.129, blue: 0.129, alpha: 1)
    )
    static let rowSelectedBackground = adaptive(
        light: NSColor(calibratedWhite: 0.90, alpha: 1),
        dark: NSColor(calibratedWhite: 0.20, alpha: 1)
    )
    static let rowHoverBackground = adaptive(
        light: NSColor(calibratedWhite: 0.945, alpha: 1),
        dark: NSColor(calibratedWhite: 0.16, alpha: 1)
    )
    static let sidebarPrimaryText = adaptive(
        light: NSColor(calibratedWhite: 0.05, alpha: 1),
        dark: NSColor(calibratedWhite: 0.92, alpha: 1)
    )
    static let sidebarMutedText = adaptive(
        light: NSColor(calibratedRed: 0.43, green: 0.43, blue: 0.50, alpha: 1),
        dark: NSColor(calibratedWhite: 0.61, alpha: 1)
    )
}

// 选中行的圆角灰底高亮，不用系统蓝色
class SidebarRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        let rect = bounds.insetBy(dx: 8, dy: 1)
        NSColor.rowSelectedBackground.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
    }
}

class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    struct Item {
        let title: String
        let icon: String
    }

    let items: [Item] = [
        Item(title: "作业看板", icon: "list.bullet.clipboard"),
        Item(title: "课程资料", icon: "folder"),
        Item(title: "成绩", icon: "chart.bar.fill"),
        Item(title: "课程表", icon: "calendar"),
        Item(title: "提醒时间", icon: "alarm"),
        Item(title: "设置", icon: "gearshape"),
    ]

    var onSelect: ((Int) -> Void)?
    private var tableView: NSTableView!

    override func loadView() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .sidebarBackground
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 44, left: 0, bottom: 12, right: 0)

        tableView = NSTableView()
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.rowHeight = 32
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.autoresizingMask = [.width]

        // 列宽之前固定写死200，但侧边栏实际只有170宽（NSSplitViewItem的
        // minimumThickness），导致每一行的内容/选中高亮往右溢出被裁掉一截——
        // 左边留白8pt看得见，右边溢出的部分直接看不见，这就是"外侧轮廓不平均"
        // 的真正原因。改成跟着侧边栏实际宽度自动伸缩，不再写死。
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sidebarItem"))
        column.width = 170
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        scrollView.documentView = tableView

        // 顶部标题区，类似 ChatGPT 侧边栏的品牌区域。
        // 之前用一个额外的 NSView 把 scrollView 包起来再放标题，结果导致整个侧边栏点不动了——
        // 这个额外的容器view会跟 NSSplitViewItem(sidebarWithViewController:) 自带的
        // sidebar材质/点击处理机制冲突。改成 NSScrollView 自己的悬浮子视图（floating subview）
        // 就没有这个问题：self.view 还是 scrollView 本身，不再多包一层。
        let header = NSTextField(labelWithString: "📚 CanvasX")
        header.font = .systemFont(ofSize: 13, weight: .semibold)
        header.textColor = .sidebarPrimaryText
        header.translatesAutoresizingMaskIntoConstraints = false
        header.backgroundColor = .sidebarBackground
        header.drawsBackground = true

        scrollView.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 18),
        ])
        scrollView.addFloatingSubview(header, for: .vertical)

        self.view = scrollView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SidebarRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        let selected = row == tableView.selectedRow
        let cell = NSTableCellView()

        let imageView = NSImageView(image: NSImage(systemSymbolName: item.icon, accessibilityDescription: item.title) ?? NSImage())
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentTintColor = selected ? .sidebarPrimaryText : .sidebarMutedText
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)

        let textField = NSTextField(labelWithString: item.title)
        textField.font = .systemFont(ofSize: 13, weight: selected ? .semibold : .regular)
        textField.textColor = selected ? .sidebarPrimaryText : .sidebarMutedText
        textField.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(imageView)
        cell.addSubview(textField)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 18),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16),

            textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 10),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            textField.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -12),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard tableView.selectedRow >= 0 else { return }
        let row = tableView.selectedRow
        onSelect?(row)
        // reloadData 放到下一个 runloop，避免在选中态变化的通知回调里直接重入改表格，
        // 这个重入是选中行本身"点了没反应"的真正原因。
        DispatchQueue.main.async { [weak self] in
            self?.tableView.reloadData()
        }
    }

    // "设置"那一行点了之后其实不对应一块常驻内容（它弹的是单独的设置窗口），
    // 点完要把高亮挪回原来那个板块，不然侧边栏会一直停留在"设置"这个不代表
    // 任何可见内容的选中态上。这里临时摘掉 delegate 再选中，避免又触发一遍
    // tableViewSelectionDidChange 重新调用 onSelect 引发死循环/多余的页面重载。
    func selectRowSilently(_ index: Int) {
        let previousDelegate = tableView.delegate
        tableView.delegate = nil
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tableView.delegate = previousDelegate
        tableView.reloadData()
    }
}
