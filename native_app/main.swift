import Cocoa
import WebKit

// 项目目录不再写死——CanvasDashboard.app 固定放在项目文件夹里面，
// 用 App 自己所在的位置往上推一层就能拿到项目目录，不管这个文件夹
// 被放在谁的电脑上、放在哪个路径下都一样能跑。
let projectDir: String = Bundle.main.bundleURL.deletingLastPathComponent().path
let dashboardPath = projectDir + "/dashboard.html"
let materialsPath = projectDir + "/materials.html"
let gradesPath = projectDir + "/grades.html"

// 检查 .env 里是不是已经填了 Canvas 账号信息——没有的话说明是第一次用，
// 先走设置向导，不直接进主界面。只做最简单的手动解析，不用引入额外的库。
func hasValidCanvasConfig() -> Bool {
    let envPath = projectDir + "/.env"
    guard let content = try? String(contentsOfFile: envPath, encoding: .utf8) else { return false }
    var token = "", baseURL = ""
    for line in content.split(separator: "\n") {
        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { continue }
        if parts[0] == "CANVAS_API_TOKEN" { token = parts[1].trimmingCharacters(in: .whitespaces) }
        if parts[0] == "CANVAS_BASE_URL" { baseURL = parts[1].trimmingCharacters(in: .whitespaces) }
    }
    return !token.isEmpty && !baseURL.isEmpty
}

class AppDelegate: NSObject, NSApplicationDelegate, WKUIDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var scheduleVC: ScheduleViewController!
    var sidebarVC: SidebarViewController!
    var splitViewController: NSSplitViewController!
    var currentSection = 0
    var wizardWindowController: SetupWizardWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()

        if !hasValidCanvasConfig() {
            showSetupWizard()
            return
        }
        showMainWindow()
    }

    func showSetupWizard() {
        wizardWindowController = SetupWizardWindowController()
        wizardWindowController.onComplete = { [weak self] in
            self?.showMainWindow()
        }
        wizardWindowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showMainWindow() {
        // 从设置向导第二次回来时（比如用户从菜单重新跑了一遍向导）复用已有窗口，
        // 只刷新数据，不要重新建一整套 webView/侧边栏——那样会跟旧的叠在一起。
        if window != nil {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            refreshData()
            return
        }

        let width: CGFloat = 940
        let height: CGFloat = 760
        let rect = NSRect(x: 0, y: 0, width: width, height: height)

        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Canvas 作业追踪"
        window.center()
        window.setFrameAutosaveName("CanvasDashboardMainWindow")
        window.toolbarStyle = .unified
        window.toolbar = NSToolbar(identifier: "MainToolbar")
        window.backgroundColor = .contentBackground

        // 容器view，装作业看板/课程资料/成绩(webView) 和 提醒时间(scheduleVC.view)，切换时只是显隐，不销毁重建
        // 这个容器交给 NSSplitViewController 用 Auto Layout 布局，不能带非零的初始 frame——
        // 哪怕关了 translatesAutoresizingMaskIntoConstraints，分屏控制器初次摆放时还是会
        // 参考这个初始 frame 尺寸，导致整个窗口被撑大、侧边栏的可点击区域跟着错位。
        let container = NSView(frame: .zero)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.contentBackground.cgColor

        // webView / scheduleVC.view 也全部改用 Auto Layout 约束贴边，不用 autoresizingMask——
        // 混用两套布局系统会导致子视图残留的固定 frame 尺寸反向影响 container 的尺寸计算，
        // 这正是刚才侧边栏区域被挤丢/窗口尺寸错乱的根源。
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)

        scheduleVC = ScheduleViewController()
        scheduleVC.view.translatesAutoresizingMaskIntoConstraints = false
        scheduleVC.view.isHidden = true
        container.addSubview(scheduleVC.view)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            scheduleVC.view.topAnchor.constraint(equalTo: container.topAnchor),
            scheduleVC.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scheduleVC.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scheduleVC.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let detailVC = NSViewController()
        detailVC.view = container

        sidebarVC = SidebarViewController()
        sidebarVC.onSelect = { [weak self] index in
            self?.sectionChanged(index)
        }

        splitViewController = NSSplitViewController()
        // 不用 sidebarWithViewController 这个便捷构造器——它会自动套用系统
        // 最新的"侧边栏"材质效果（一个悬浮的圆角卡片，离窗口顶部的间距比左右两边
        // 大很多），这正是"外部边框不均匀"的原因，不是我们自己代码画出来的。
        // 改用普通构造器 + 手动设置属性，侧边栏背景贴着窗口边缘走，没有这层系统外壳。
        let sidebarItem = NSSplitViewItem(viewController: sidebarVC)
        sidebarItem.minimumThickness = 170
        sidebarItem.maximumThickness = 220
        sidebarItem.canCollapse = true
        let detailItem = NSSplitViewItem(viewController: detailVC)
        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(detailItem)

        window.contentViewController = splitViewController
        // 赋值 contentViewController 会让窗口自动缩到分屏内容的"合适尺寸"——
        // 两个分栏都没有固定 frame 时这个"合适尺寸"会塌缩成 0，窗口跟着缩没了，
        // 所以这里必须显式把窗口尺寸改回来。
        window.setContentSize(rect.size)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        loadDashboard()
        refreshData()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // MARK: - 左侧边栏切换：作业看板 / 课程资料 / 成绩 / 提醒时间

    func sectionChanged(_ index: Int) {
        currentSection = index
        let showSchedule = index == 3
        scheduleVC.view.isHidden = !showSchedule
        webView.isHidden = showSchedule
        if showSchedule {
            scheduleVC.reload()
            return
        }
        switch index {
        case 1:
            loadPage(materialsPath)
        case 2:
            loadPage(gradesPath)
        default:
            loadPage(dashboardPath)
        }
    }

    func loadDashboard() {
        loadPage(dashboardPath)
    }

    func loadPage(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        let url = URL(fileURLWithPath: path)
        webView.loadFileURL(url, allowingReadAccessTo: URL(fileURLWithPath: projectDir))
    }

    func refreshData() {
        let task = Process()
        task.currentDirectoryURL = URL(fileURLWithPath: projectDir)
        task.executableURL = URL(fileURLWithPath: projectDir + "/.venv/bin/python3")
        task.arguments = ["canvas_sync.py", "--refresh"]

        let logURL = URL(fileURLWithPath: projectDir + "/logs/app_launch.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            task.standardOutput = handle
            task.standardError = handle
        }

        task.terminationHandler = { _ in
            DispatchQueue.main.async {
                self.sectionChanged(self.currentSection)
            }
        }

        do {
            try task.run()
        } catch {
            NSLog("refresh failed to launch: \(error)")
        }
    }

    // target="_blank" 链接（详情/提交按钮）在系统默认浏览器里打开，不要在App窗口内跳转
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
        }
        return nil
    }

    // MARK: - 课程资料页里的"添加文件"/"删除文件"按钮，用自定义 URL scheme 从网页调回原生代码
    // （canvasapp://add?course_id=X ，canvasapp://delete?id=X），点击时拦截掉，不真的当链接跳转。

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url, url.scheme == "canvasapp" else {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        handleCanvasAppLink(url)
    }

    func handleCanvasAppLink(_ url: URL) {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func param(_ name: String) -> String? {
            query.first(where: { $0.name == name })?.value
        }

        switch url.host {
        case "add":
            guard let courseId = param("course_id") else { return }
            presentOpenPanelAndRegister(courseId: courseId)
        case "delete":
            guard let materialId = param("id") else { return }
            runPython(["canvas_materials.py", "--delete", materialId]) { [weak self] in
                self?.loadPage(materialsPath)
            }
        default:
            break
        }
    }

    func presentOpenPanelAndRegister(courseId: String) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "添加到课程资料"
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            self?.registerFiles(panel.urls.map { $0.path }, courseId: courseId)
        }
    }

    // 逐个注册，不要并发跑多个 python 进程同时写 SQLite（这个项目之前真遇到过
    // "database is locked"，就是两个写操作同时发生导致的）。
    func registerFiles(_ paths: [String], courseId: String) {
        guard var remaining = Optional(paths), !remaining.isEmpty else { return }
        let path = remaining.removeFirst()
        runPython(["canvas_materials.py", "--register", courseId, path]) { [weak self] in
            if remaining.isEmpty {
                self?.loadPage(materialsPath)
            } else {
                self?.registerFiles(remaining, courseId: courseId)
            }
        }
    }

    func runPython(_ arguments: [String], completion: @escaping () -> Void) {
        let task = Process()
        task.currentDirectoryURL = URL(fileURLWithPath: projectDir)
        task.executableURL = URL(fileURLWithPath: projectDir + "/.venv/bin/python3")
        task.arguments = arguments
        task.terminationHandler = { _ in
            DispatchQueue.main.async { completion() }
        }
        do {
            try task.run()
        } catch {
            NSLog("runPython \(arguments) failed: \(error)")
        }
    }

    // MARK: - 菜单栏（Quit / 刷新数据）

    func setupMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        appMenuItem.title = "Canvas Dashboard"
        let appMenu = NSMenu(title: "Canvas Dashboard")
        appMenu.addItem(NSMenuItem(title: "退出 Canvas 作业追踪", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        editMenuItem.title = "Edit"
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let viewMenuItem = NSMenuItem()
        viewMenuItem.title = "View"
        let viewMenu = NSMenu(title: "View")
        let refreshItem = NSMenuItem(title: "刷新数据", action: #selector(refreshMenuAction), keyEquivalent: "r")
        refreshItem.target = self
        viewMenu.addItem(refreshItem)
        let rerunWizardItem = NSMenuItem(title: "重新运行设置向导（换 Token / 改选课）", action: #selector(rerunWizardAction), keyEquivalent: "")
        rerunWizardItem.target = self
        viewMenu.addItem(rerunWizardItem)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc func refreshMenuAction() {
        refreshData()
    }

    @objc func rerunWizardAction() {
        showSetupWizard()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
