using System.IO;
using System.Text.Json;
using CanvasDashboard.Models;

namespace CanvasDashboard.Services;

/// <summary>
/// 读写 .windows_app_prefs.json（主题+设置窗口语言）。Windows 版独有的小文件，
/// 已经在项目根目录的 .gitignore 里加了一行，不会被提交。
/// </summary>
public static class PrefsStore
{
    private static string Path => System.IO.Path.Combine(ProjectPaths.ProjectRoot, ".windows_app_prefs.json");

    public static AppPrefs Load()
    {
        try
        {
            var json = File.ReadAllText(Path);
            var prefs = JsonSerializer.Deserialize<AppPrefs>(json, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true,
            });
            if (prefs != null) return prefs;
        }
        catch
        {
            // 文件不存在/第一次运行/损坏，都用默认值
        }
        return new AppPrefs();
    }

    public static void Save(AppPrefs prefs)
    {
        try
        {
            File.WriteAllText(Path, JsonSerializer.Serialize(prefs, new JsonSerializerOptions
            {
                WriteIndented = true,
            }));
        }
        catch
        {
            // 保存偏好失败不应该让整个操作（比如切换主题）崩掉
        }
    }
}
