using System.IO;
using System.Windows;
using CanvasDashboard.Services;

namespace CanvasDashboard.Views;

/// <summary>
/// 通用的"开一个窗口显示一个本地网页"控制器，对应 Mac 版 WebPageWindowController.swift。
/// 设置向导 (setup_wizard.html) 和设置面板 (settings.html) 都用这个，不用再各自写一套
/// 原生 UI 布局代码。网页内容通过 NativeBridge 调用原生能力（见 Services/NativeBridge.cs）。
///
/// 窗口本身不持有"完成后做什么"的回调——那部分逻辑（关掉向导切主窗口、退出登录切窗口……）
/// 完全交给 NativeBridge 处理具体 action 时直接调用 App 的静态方法触发，跟 Mac 版
/// Bridge.swift 直接调用全局 delegate 是同一个思路，窗口本身只管"显示这个网页"。
/// </summary>
public partial class WebPageWindow : Window
{
    private readonly string _htmlFileName;

    public WebPageWindow(string htmlFileName, string title, double width, double height)
    {
        InitializeComponent();
        _htmlFileName = htmlFileName;
        Title = title;
        Width = width;
        Height = height;
    }

    private async void Window_Loaded(object sender, RoutedEventArgs e)
    {
        try
        {
            await Browser.EnsureCoreWebView2Async();
        }
        catch (Exception ex)
        {
            MessageBox.Show(this,
                "WebView2 初始化失败，通常是因为这台电脑还没装 WebView2 Runtime（新版 Windows 10/11 一般已经" +
                $"随 Edge 自带，缺失的话去微软官网搜索 \"WebView2 Runtime\" 下载安装）。\n\n详细信息：{ex.Message}",
                "CanvasX", MessageBoxButton.OK, MessageBoxImage.Error);
            return;
        }

        NativeBridge.Install(Browser.CoreWebView2);
        ThemeManager.RegisterWebView(Browser.CoreWebView2);

        // 设置向导页面里"苹果快捷指令"推送选项只在 Mac 上显示，页面每次加载完都告诉它
        // 当前平台是 windows（对应 Mac 版 webView(_:didFinish:) 的做法）。settings.html
        // 不关心这个调用，页面里 window.__setPlatform 判断了 platform === "mac" 才生效，
        // 传其它值（包括 "windows"）都是安全的空操作。
        Browser.CoreWebView2.NavigationCompleted += (_, _) =>
        {
            _ = Browser.CoreWebView2.ExecuteScriptAsync("window.__setPlatform && window.__setPlatform('windows')");
        };

        var path = Path.Combine(ProjectPaths.ProjectRoot, _htmlFileName);
        if (File.Exists(path))
        {
            Browser.CoreWebView2.Navigate(new Uri(path).AbsoluteUri);
        }
        else
        {
            MessageBox.Show(this, $"找不到页面文件：{path}", "CanvasX",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
}
