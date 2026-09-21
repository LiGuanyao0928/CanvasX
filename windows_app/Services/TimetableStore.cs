using System.IO;
using System.Text.Json;

namespace CanvasDashboard.Services;

/// <summary>
/// 读写项目根目录下的 timetable.json（课程表：星期几/几点/教室，用户自己填的——
/// Canvas 不提供这份数据，教务系统才有）。对应 Mac 版 Bridge.swift 的 TimetableFile
/// enum，同一个思路：原样存取 blocks 这个 JSON 数组，不用维护强类型模型。跟 ScheduleStore
/// 不一样的是，这里不需要在保存后额外驱动系统级定时任务——课程表只是给用户自己看。
/// </summary>
public static class TimetableStore
{
    private static string Path => System.IO.Path.Combine(ProjectPaths.ProjectRoot, "timetable.json");

    /// <summary>返回 blocks 数组的原始 JSON 文本，直接透传给网页。</summary>
    public static string LoadBlocksJson()
    {
        try
        {
            var text = File.ReadAllText(Path);
            using var doc = JsonDocument.Parse(text);
            if (doc.RootElement.TryGetProperty("blocks", out var blocks) && blocks.ValueKind == JsonValueKind.Array)
            {
                return blocks.GetRawText();
            }
        }
        catch
        {
            // 文件不存在/损坏，都退回空数组——课程表本来就允许一开始什么都没有
        }
        return "[]";
    }

    /// <summary>blocksJsonArray 是网页那边已经序列化好的 JSON 数组文本，原样包一层 {"blocks": [...]} 写文件。</summary>
    public static void Save(string blocksJsonArray)
    {
        using var doc = JsonDocument.Parse("{\"blocks\":" + blocksJsonArray + "}");
        File.WriteAllText(Path, JsonSerializer.Serialize(doc.RootElement, new JsonSerializerOptions { WriteIndented = true }));
    }
}
