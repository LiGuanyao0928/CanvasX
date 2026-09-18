using System.IO;
using System.Text.Json;
using CanvasDashboard.Models;

namespace CanvasDashboard.Services;

/// <summary>
/// 读写项目根目录下的 schedule.json，并在保存后调用 update_schedule_windows.py
/// 重新生成 Windows「任务计划程序」里的定时任务——跟 Mac 版 Alarm.swift 里的
/// ScheduleStore 是同一个思路，只是 applyToLaunchd() 换成了这里的 ApplyAsync()。
/// </summary>
public static class ScheduleStore
{
    private static string Path => System.IO.Path.Combine(ProjectPaths.ProjectRoot, "schedule.json");

    private static readonly JsonSerializerOptions ReadOpts = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private static readonly JsonSerializerOptions WriteOpts = new()
    {
        WriteIndented = true,
    };

    public static List<Alarm> Load()
    {
        try
        {
            var json = File.ReadAllText(Path);
            var schedule = JsonSerializer.Deserialize<Schedule>(json, ReadOpts);
            if (schedule?.Alarms is { Count: > 0 }) return schedule.Alarms;
        }
        catch
        {
            // 文件不存在/损坏，都退回默认值——跟 Mac 版行为一致，不让用户对着空列表懵掉
        }
        return new List<Alarm> { Alarm.CreateDefault() };
    }

    public static void Save(List<Alarm> alarms)
    {
        var schedule = new Schedule { Alarms = alarms };
        File.WriteAllText(Path, JsonSerializer.Serialize(schedule, WriteOpts));
    }

    /// <summary>
    /// 调用 update_schedule_windows.py 重新生成 schtasks 计划任务。
    /// 每次增删/开关/编辑提醒时间、保存完 schedule.json 之后都必须紧接着调用这个，
    /// 不然 Windows 那边的定时任务和 schedule.json 会不一致。
    /// </summary>
    public static Task<int> ApplyAsync() => PythonRunner.RunAsync(new[] { "update_schedule_windows.py" });
}
