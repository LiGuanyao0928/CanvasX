import Cocoa
import WebKit

// 项目目录不再写死——CanvasDashboard.app 固定放在项目文件夹里面，
// 用 App 自己所在的位置往上推一层就能拿到项目目录，不管这个文件夹
// 被放在谁的电脑上、放在哪个路径下都一样能跑。
let projectDir: String = Bundle.main.bundleURL.deletingLastPathComponent().path
let dashboardPath = projectDir + "/dashboard.html"
let materialsPath = projectDir + "/materials.html"
let gradesPath = projectDir + "/grades.html"
let schedulePath = projectDir + "/schedule.html"
let timetablePath = projectDir + "/timetable.html"

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
    var sidebarVC: SidebarViewController!
    var splitViewController: NSSplitViewController!
    var currentSection = 0
    var wizardWindowController: WebPageWindowController!
    var settingsWindowController: WebPageWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearanceMode.applyStartupPreference()
        setupMenu()

        if !hasValidCanvasConfig() {
            showSetupWizard()
            return
        }
        showMainWindow()
    }

    func showSetupWizard() {
        wizardWindowController = WebPageWindowController(
            htmlFileName: "setup_wizard.html", title: "欢迎使用 Canvas 作业追踪", width: 480, height: 780)
        wizardWindowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // 设置向导网页调用 completeSetup 桥接、Python 那边写完配置+同步完之后回调这里。
    func finishSetupWizard() {
        wizardWindowController?.window?.close()
        wizardWindowController = nil
        showMainWindow()
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

        // "提醒时间"现在也是网页（schedule.html），跟作业看板/资料/成绩一样在同一个
        // webView 里加载，不用再维护一个原生 ScheduleViewController 跟 webView 并排
        // 显隐切换——四个板块现在是完全对称的"加载不同网页"，不用特殊分支。
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        NativeBridge.install(on: webView.configuration, bridge: NativeBridge(webView: webView))

        let detailVC = NSViewController()
        let container = NSView()
        // 必须显式关掉——这个容器要交给 NSSplitViewController 用 Auto Layout 布局，
        // 默认的 true 会让系统在背后偷偷生成一套基于 frame 的约束，跟下面手写的
        // Auto Layout 约束互相打架，NSSplitViewController 摆放它时会直接抛
        // Auto Layout 异常（这类异常会被 AppKit 的事件循环吞掉、不崩溃但窗口也
        // 出不来）——这是这个项目踩过的老坑，之前修过一次，这次重构时漏抄了。
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
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

    // MARK: - 左侧边栏切换：作业看板 / 课程资料 / 成绩 / 课程表 / 提醒时间 / 设置

    func sectionChanged(_ index: Int) {
        if index == 5 {
            // "设置"不是一块常驻内容，点了弹单独的设置窗口，侧边栏高亮退回原来那块。
            showSettings()
            sidebarVC.selectRowSilently(currentSection)
            return
        }
        currentSection = index
        switch index {
        case 1:
            loadPage(materialsPath)
        case 2:
            loadPage(gradesPath)
        case 3:
            loadPage(timetablePath)
        case 4:
            loadPage(schedulePath)
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

    // 设置面板"立即同步"跑完之后回调这里，把主窗口当前那一页重新加载一遍。
    func reloadMainWindowCurrentSection() {
        sectionChanged(currentSection)
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

    // MARK: - 设置面板

    func showSettings() {
        settingsWindowController = WebPageWindowController(
            htmlFileName: "settings.html", title: "设置", width: 460, height: 620)
        settingsWindowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // 设置面板网页调用 logout 桥接、Python 那边清完文件之后回调这里，负责窗口切换。
    // 先展示新向导窗口，再关掉旧窗口——顺序不能反过来，中间有一瞬间零窗口存在的话，
    // 有可能触发 App 提前退出（取决于 ShutdownMode 之类的行为），新向导就弹不出来了。
    func performLogoutTransition() {
        settingsWindowController?.window?.close()
        settingsWindowController = nil
        showSetupWizard()
        window?.close()
        window = nil
    }

    // "记住我"没勾选（公用电脑场景）：退出 App 时自动清掉这台电脑上刚才写的登录信息，
    // 不等用户自己记得去点"退出登录"。同步阻塞跑完（几个小文件，毫秒级）——
    // applicationWillTerminate 返回之后进程就真的退出了，没法排一个异步续体。
    func clearLocalUserDataSync() {
        let task = Process()
        task.currentDirectoryURL = URL(fileURLWithPath: projectDir)
        task.executableURL = URL(fileURLWithPath: projectDir + "/.venv/bin/python3")
        task.arguments = ["clear_local_user_data.py"]
        try? task.run()
        task.waitUntilExit()
    }

    func applicationWillTerminate(_ notification: Notification) {
        let remember = UserDefaults.standard.object(forKey: "rememberLogin") as? Bool ?? true
        if !remember {
            clearLocalUserDataSync()
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
    // 这个机制比其他页面早、已经跑通很久了，这次重构没有把它也改成 NativeBridge 消息——
    // 没必要为了统一而统一，能跑的东西不用动。

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

    // MARK: - 菜单栏

    func setupMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        appMenuItem.title = "Canvas Dashboard"
        let appMenu = NSMenu(title: "Canvas Dashboard")
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(settingsMenuAction), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "退出 Canvas 作业追踪", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        editMenuItem.title = "Edit"
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        // 手搓的菜单栏之前漏了这一项——没有菜单项声明 Cmd+V 的 key equivalent，
        // 输入框里粘贴（比如粘贴 Token 这种长字符串）就完全没反应，看着像"输入不了"。
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let viewMenuItem = NSMenuItem()
        viewMenuItem.title = "View"
        let viewMenu = NSMenu(title: "View")
        let refreshItem = NSMenuItem(title: "刷新数据", action: #selector(refreshMenuAction), keyEquivalent: "r")
        refreshItem.target = self
        viewMenu.addItem(refreshItem)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc func refreshMenuAction() {
        refreshData()
    }

    @objc func settingsMenuAction() {
        showSettings()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
