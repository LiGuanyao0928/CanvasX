using System.Text.Json.Serialization;

namespace CanvasDashboard.Models;

/// <summary>
/// 反序列化 GET /api/v1/courses 的单条结果。字段名跟 Canvas API 保持一致（course_code 用
/// snake_case），对应 Mac 版 CanvasAPI.swift 里的 CanvasCourse。
/// </summary>
public class CanvasCourseDto
{
    [JsonPropertyName("id")]
    public int Id { get; set; }

    [JsonPropertyName("name")]
    public string? Name { get; set; }

    [JsonPropertyName("course_code")]
    public string? CourseCode { get; set; }
}

public record CanvasCourse(int Id, string? Name, string? CourseCode)
{
    public string DisplayName => !string.IsNullOrWhiteSpace(Name) ? Name! :
        !string.IsNullOrWhiteSpace(CourseCode) ? CourseCode! :
        $"未命名课程 #{Id}";

    public static CanvasCourse FromDto(CanvasCourseDto dto) => new(dto.Id, dto.Name, dto.CourseCode);
}
