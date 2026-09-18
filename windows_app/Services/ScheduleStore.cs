using System.IO;
using System.Text.Json;

namespace CanvasDashboard.Services;

/// <summary>
/// 读写项目根目录下的 schedule.json，并在保存后调用 update_schedule_windows.py
/// 重新生成 Windows「任务计划程序」里的定时任务。
///
/// "提醒时间"现在是网页（schedule.html），闹钟数据结构完全交给网页 JS 处理，原生这边
/// 只负责原样存取 alarms 这个 JSON 数组，不用再维护 Alarm 这个 C# 类型——对应 Mac 版
/// Bridge.swift 里的 ScheduleFile enum，同一个思路，只是 applyToLaunchd() 换成了
/// schtasks（update_schedule_windows.py）。
/// </summary>
public static class ScheduleStore
{
    private static string Path => System.IO.Path.Combine(ProjectPaths.ProjectRoot, "schedule.json");

    private const string DefaultAlarmsJson =
        "[{\"id\":\"default\",\"hour\":8,\"minute\":0,\"enabled\":true,\"days\":[0,1,2,3,4,5,6]}]";

    /// <summary>返回 alarms 数组的原始 JSON 文本，直接透传给网页，不反序列化成强类型对象。</summary>
    public static string LoadAlarmsJson()
    {
        try
        {
            var text = File.ReadAllText(Path);
            using var doc = JsonDocument.Parse(text);
            if (doc.RootElement.TryGetProperty("alarms", out var alarms) && alarms.ValueKind == JsonValueKind.Array)
            {
                return alarms.GetRawText();
            }
        }
        catch
        {
            // 文件不存在/损坏，都退回默认值——跟 Mac 版行为一致，不让用户对着空列表懵掉
        }
        return DefaultAlarmsJson;
    }

    /// <summary>alarmsJsonArray 是网页那边已经序列化好的 JSON 数组文本，原样包一层 {"alarms": [...]} 写文件。</summary>
    public static void Save(string alarmsJsonArray)
    {
        using var doc = JsonDocument.Parse("{\"alarms\":" + alarmsJsonArray + "}");
        File.WriteAllText(Path, JsonSerializer.Serialize(doc.RootElement, new JsonSerializerOptions { WriteIndented = true }));
    }

    /// <summary>
    /// 调用 update_schedule_windows.py 重新生成 schtasks 计划任务。每次保存完 schedule.json
    /// 之后都必须紧接着调用这个，不然 Windows 那边的定时任务和 schedule.json 会不一致。
    /// </summary>
    public static Task<int> ApplyAsync() => PythonRunner.RunAsync(new[] { "update_schedule_windows.py" });
}
