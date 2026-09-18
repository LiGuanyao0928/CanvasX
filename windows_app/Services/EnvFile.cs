using System.IO;

namespace CanvasDashboard.Services;

/// <summary>
/// 读写项目根目录下的 .env —— 纯 KEY=VALUE 一行一个，不带引号，跟 Python 后端
/// load_dotenv() 期望的格式必须字节对齐一致（不能加多余的引号/空格处理花样）。
/// 解析规则跟 Mac 版 main.swift 的 hasValidCanvasConfig() 一样：按第一个 "=" 切开
/// （值本身可能包含 "="，比如某些 Webhook 网址），忽略切不出两段的行。
/// </summary>
public static class EnvFile
{
    private static string Path => System.IO.Path.Combine(ProjectPaths.ProjectRoot, ".env");

    public static Dictionary<string, string> Load()
    {
        var dict = new Dictionary<string, string>();
        if (!File.Exists(Path)) return dict;

        foreach (var line in File.ReadAllLines(Path))
        {
            var idx = line.IndexOf('=');
            if (idx <= 0) continue;
            var key = line[..idx].Trim();
            var value = line[(idx + 1)..].Trim();
            if (key.Length == 0) continue;
            dict[key] = value;
        }
        return dict;
    }

    public static bool HasValidConfig()
    {
        var env = Load();
        return env.TryGetValue("CANVAS_API_TOKEN", out var token) && !string.IsNullOrWhiteSpace(token)
               && env.TryGetValue("CANVAS_BASE_URL", out var url) && !string.IsNullOrWhiteSpace(url);
    }

    /// <summary>整份覆盖写入（设置向导用），保持插入顺序，末尾留一个换行。</summary>
    public static void Write(IEnumerable<KeyValuePair<string, string>> values)
    {
        var lines = values.Select(kv => $"{kv.Key}={kv.Value}");
        File.WriteAllText(Path, string.Join("\n", lines) + "\n");
    }
}
