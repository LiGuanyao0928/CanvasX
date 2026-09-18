import Cocoa
import WebKit

// 通用的"开一个窗口显示一个本地网页"控制器——设置向导 (setup_wizard.html) 和
// 设置面板 (settings.html) 都用这个，不用再各自写一套原生 UI 布局代码。
// 网页内容通过 NativeBridge 调用原生能力（见 Bridge.swift）。
class WebPageWindowController: NSWindowController, WKNavigationDelegate {
    private var webView: WKWebView!
    private var bridge: NativeBridge!

    convenience init(htmlFileName: String, title: String, width: CGFloat, height: CGFloat) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.center()
        self.init(window: window)

        let configuration = WKWebViewConfiguration()
        let newWebView = WKWebView(frame: .zero, configuration: configuration)
        newWebView.navigationDelegate = self
        webView = newWebView
        bridge = NativeBridge(webView: newWebView)
        NativeBridge.install(on: configuration, bridge: bridge)

        newWebView.translatesAutoresizingMaskIntoConstraints = false
        let contentView = NSView()
        contentView.addSubview(newWebView)
        window.contentView = contentView
        NSLayoutConstraint.activate([
            newWebView.topAnchor.constraint(equalTo: contentView.topAnchor),
            newWebView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            newWebView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            newWebView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        let url = URL(fileURLWithPath: projectDir + "/" + htmlFileName)
        newWebView.loadFileURL(url, allowingReadAccessTo: URL(fileURLWithPath: projectDir))
    }

    override init(window: NSWindow?) {
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    // 设置向导页面里"苹果快捷指令"推送选项只在 Mac 上显示，页面加载完告诉它当前平台。
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("window.__setPlatform && window.__setPlatform('mac')")
    }
}
