using System.Text.Json.Serialization;

namespace CanvasDashboard.Models;

/// <summary>
/// 一条提醒时间。0 = 周日 ... 6 = 周六，跟 Mac 版 Alarm.swift、update_schedule_windows.py
/// 里的 WEEKDAY_CODES 编号一致，务必不要改成 0=周一 这种别的编号方式。
/// </summary>
public class Alarm
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = Guid.NewGuid().ToString();

    [JsonPropertyName("hour")]
    public int Hour { get; set; }

    [JsonPropertyName("minute")]
    public int Minute { get; set; }

    [JsonPropertyName("enabled")]
    public bool Enabled { get; set; } = true;

    [JsonPropertyName("days")]
    public List<int> Days { get; set; } = new();

    public static readonly string[] DayLabels = { "日", "一", "二", "三", "四", "五", "六" };

    public string TimeText => $"{Hour:D2}:{Minute:D2}";

    public string RepeatText
    {
        get
        {
            var set = new HashSet<int>(Days);
            if (set.Count >= 7) return "每天";
            if (set.SetEquals(new[] { 1, 2, 3, 4, 5 })) return "周一至周五";
            if (set.SetEquals(new[] { 0, 6 })) return "周六、周日";
            if (set.Count == 0) return "不重复";
            return string.Join("、", set.OrderBy(d => d).Select(d => $"周{DayLabels[d]}"));
        }
    }

    public static Alarm CreateDefault() => new()
    {
        Id = Guid.NewGuid().ToString(),
        Hour = 8,
        Minute = 0,
        Enabled = true,
        Days = Enumerable.Range(0, 7).ToList(),
    };
}

public class Schedule
{
    [JsonPropertyName("alarms")]
    public List<Alarm> Alarms { get; set; } = new();
}
