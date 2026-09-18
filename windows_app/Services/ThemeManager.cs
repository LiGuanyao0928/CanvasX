using System.Windows;
using Microsoft.Win32;

namespace CanvasDashboard.Services;

/// <summary>
/// 手动切换 Light.xaml / Dark.xaml 这两套同名 key 的资源字典，挂到
/// Application.Current.Resources.MergedDictionaries 上。
///
/// .NET 8 的 WPF 还没有内置的 ThemeMode API（那是 .NET 9+ 才有的东西），
/// 所以这里用最朴素的手动换资源字典的办法，"跟随系统"只在启动时读一次注册表，
/// 不做实时监听系统主题切换（按需求"best-effort，不用过度设计"）。
/// </summary>
public static class ThemeManager
{
    private const string LightUri = "Themes/Light.xaml";
    private const string DarkUri = "Themes/Dark.xaml";

    /// <summary>themePref: "system" / "light" / "dark"</summary>
    public static void Apply(string themePref)
    {
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
