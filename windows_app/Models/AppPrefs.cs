using System.Text.Json.Serialization;

namespace CanvasDashboard.Models;

/// <summary>
/// Windows 客户端自己的本地偏好设置（主题 + 设置窗口语言），存在项目根目录下的
/// .windows_app_prefs.json 里——这是 Windows 版独有的文件，Mac 版没有对应物，
/// 跟 schedule.json 一样是"每台电脑自己的本地状态"，不提交到仓库。
/// </summary>
public class AppPrefs
{
    /// <summary>system / light / dark</summary>
    [JsonPropertyName("theme")]
    public string Theme { get; set; } = "system";

    /// <summary>zh / en —— 只影响设置窗口自己的文字</summary>
    [JsonPropertyName("language")]
    public string Language { get; set; } = "zh";
}
