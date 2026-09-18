using System.Windows;
using Microsoft.Web.WebView2.Core;
using Microsoft.Win32;

namespace CanvasDashboard.Services;

/// <summary>
/// 手动切换 Light.xaml / Dark.xaml 这两套同名 key 的资源字典（原生窗口外观），
/// 外加把同一个选择同步给所有已知的 WebView2（网页内容的深浅色）。
///
/// 网页那边（dashboard/materials/grades/schedule/setup_wizard/settings.html）全部走
/// app_theme.css 的 CSS 变量 + prefers-color-scheme，"浅色/深色"这两个强制选项要对网页
/// 也生效，得让 WebView2 引擎本身认为的系统偏好跟着变——用 CoreWebView2Profile.
/// PreferredColorScheme。这一步是 Mac 版"设置 NSApp.appearance 后 WKWebView 自动跟着变"
/// 的对应物：Mac 一次赋值能同时影响原生控件和网页渲染，Windows 这边原生外观和网页外观
/// 是两套独立机制，得分别处理，所以这个类比 Mac 版的 AppearanceMode 多了后半段逻辑。
///
/// .NET 8 的 WPF 还没有内置的 ThemeMode API（那是 .NET 9+ 才有的东西），
/// 所以这里用最朴素的手动换资源字典的办法，"跟随系统"只在启动时读一次注册表，
/// 不做实时监听系统主题切换（按需求"best-effort，不用过度设计"）。
/// </summary>
public static class ThemeManager
{
    private const string LightUri = "Themes/Light.xaml";
    private const string DarkUri = "Themes/Dark.xaml";

    private static string _currentThemePref = "system";

    // 用弱引用登记所有初始化过的 CoreWebView2（主窗口的 Browser + 每个 WebPageWindow 各一个），
    // 这样换主题时能挨个同步过去；窗口关闭后对应的 CoreWebView2 会被回收，弱引用自然失效，
    // 不用手动摘除、不会内存泄漏。
    private static readonly List<WeakReference<CoreWebView2>> WebViews = new();

    /// <summary>
    /// 每个 WebView2 控件完成 EnsureCoreWebView2Async 之后都要调用一次这个，把自己登记进来，
    /// 并且立刻按当前主题设置一次——不然"先选了深色，之后才打开的新窗口"会读不到这个选择。
    /// </summary>
    public static void RegisterWebView(CoreWebView2 webView)
    {
        WebViews.Add(new WeakReference<CoreWebView2>(webView));
        ApplyColorSchemeTo(webView, _currentThemePref);
    }

    /// <summary>themePref: "system" / "light" / "dark"</summary>
    public static void Apply(string themePref)
    {
        _currentThemePref = themePref;

        var effective = themePref switch
        {
            "dark" => "dark",
            "light" => "light",
            _ => DetectSystemTheme(),
        };

        var targetUri = effective == "dark" ? DarkUri : LightUri;
        var merged = Application.Current.Resources.MergedDictionaries;

        for (var i = merged.Count - 1; i >= 0; i--)
        {
            var source = merged[i].Source?.OriginalString ?? "";
            if (source.EndsWith(LightUri, StringComparison.OrdinalIgnoreCase) ||
                source.EndsWith(DarkUri, StringComparison.OrdinalIgnoreCase))
            {
                merged.RemoveAt(i);
            }
        }

        merged.Add(new ResourceDictionary { Source = new Uri(targetUri, UriKind.Relative) });

        for (var i = WebViews.Count - 1; i >= 0; i--)
        {
            if (WebViews[i].TryGetTarget(out var webView))
            {
                ApplyColorSchemeTo(webView, themePref);
            }
            else
            {
                WebViews.RemoveAt(i);
            }
        }
    }

    private static void ApplyColorSchemeTo(CoreWebView2 webView, string themePref)
    {
        try
        {
            webView.Profile.PreferredColorScheme = themePref switch
            {
                "dark" => CoreWebView2PreferredColorScheme.Dark,
                "light" => CoreWebView2PreferredColorScheme.Light,
                _ => CoreWebView2PreferredColorScheme.Auto,
            };
        }
        catch
        {
            // 老版本 WebView2 Runtime 可能没有 PreferredColorScheme 这个属性，或者
            // Profile 还没就绪——网页本身有 prefers-color-scheme 兜底，失败了只是
            // "浅色/深色"这两个强制选项对网页内容不生效（还是跟着系统走），不影响别的功能。
        }
    }

    /// <summary>
    /// 读 HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize 的
    /// AppsUseLightTheme：0 = 深色，非 0（或读不到）= 浅色。
    /// </summary>
    public static string DetectSystemTheme()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            if (key?.GetValue("AppsUseLightTheme") is int value)
            {
                return value == 0 ? "dark" : "light";
            }
        }
        catch
        {
            // 读注册表失败（权限/版本差异）就退回浅色，不影响启动
        }
        return "light";
    }
}
