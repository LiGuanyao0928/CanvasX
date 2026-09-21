using System.IO;
using System.Text.Json;

namespace CanvasDashboard.Services;

/// <summary>
/// 读写项目根目录下的 timetable.json（课程表：星期几/几点/教室/频率（每周/隔周）/
/// 阅读周，都是用户自己填的——Canvas 不提供这份数据，教务系统才有）。对应 Mac 版
/// Bridge.swift 的 TimetableFile enum，同一个思路：网页那边（timetable.html）自己
/// 维护完整的 {termStart, readingWeeks, blocks} 状态并计算单双周/阅读周要不要显示课，
/// 这边只是个透传的存储层，原样存取整个 JSON 对象，不用关心里面有哪些字段。跟
/// ScheduleStore 不一样的是，这里不需要在保存后额外驱动系统级定时任务——课程表只是
/// 给用户自己看，没有后台联动。
/// </summary>
public static class TimetableStore
{
    private static string Path => System.IO.Path.Combine(ProjectPaths.ProjectRoot, "timetable.json");

    private const string DefaultTimetableJson = "{\"termStart\":null,\"readingWeeks\":[],\"blocks\":[]}";

    /// <summary>返回整个课表状态对象的原始 JSON 文本，直接透传给网页。</summary>
    public static string LoadTimetableJson()
    {
        try
        {
            var text = File.ReadAllText(Path);
            using var doc = JsonDocument.Parse(text); // 校验一下确实是合法 JSON 再原样返回
            return doc.RootElement.GetRawText();
        }
        catch
        {
            // 文件不存在/损坏，都退回默认空状态——课程表本来就允许一开始什么都没有
            return DefaultTimetableJson;
        }
    }

    /// <summary>timetableJson 是网页那边已经序列化好的完整状态对象 JSON 文本，原样写文件。</summary>
    public static void Save(string timetableJson)
    {
        using var doc = JsonDocument.Parse(timetableJson);
        File.WriteAllText(Path, JsonSerializer.Serialize(doc.RootElement, new JsonSerializerOptions { WriteIndented = true }));
    }
}
