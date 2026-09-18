using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using CanvasDashboard.Models;

namespace CanvasDashboard.Services;

public enum CanvasApiErrorKind
{
    BadUrl,
    Unauthorized,
    Http,
    Decode,
    Network,
}

public class CanvasApiException : Exception
{
    public CanvasApiErrorKind Kind { get; }

    public CanvasApiException(CanvasApiErrorKind kind, string message) : base(message)
    {
        Kind = kind;
    }
}

/// <summary>
/// 设置向导用的最小 Canvas API 客户端，对应 Mac 版 CanvasAPI.swift：只做
/// "验证 token + 拉课程列表"这一件事。
/// GET {baseURL}/api/v1/courses?per_page=50&amp;enrollment_state=active
/// Header: Authorization: Bearer {token}
/// </summary>
public static class CanvasApi
{
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    public static async Task<List<CanvasCourse>> FetchCoursesAsync(string baseUrl, string token)
    {
        var trimmed = baseUrl.Trim();
        while (trimmed.EndsWith('/')) trimmed = trimmed[..^1];
        if (!trimmed.StartsWith("http://", StringComparison.OrdinalIgnoreCase) &&
            !trimmed.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            trimmed = "https://" + trimmed;
        }

        if (!Uri.TryCreate(trimmed + "/api/v1/courses?per_page=50&enrollment_state=active",
                UriKind.Absolute, out var uri))
        {
            throw new CanvasApiException(CanvasApiErrorKind.BadUrl, "网址格式不对，检查一下是不是漏了 https://");
        }

        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
        http.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", token.Trim());

        HttpResponseMessage response;
        try
        {
            response = await http.GetAsync(uri).ConfigureAwait(true);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            throw new CanvasApiException(CanvasApiErrorKind.Network,
                $"连不上服务器，检查一下网址和网络：{ex.Message}");
        }

        if (response.StatusCode == HttpStatusCode.Unauthorized)
        {
            throw new CanvasApiException(CanvasApiErrorKind.Unauthorized, "Token 无效或已过期");
        }

        if (!response.IsSuccessStatusCode)
        {
            throw new CanvasApiException(CanvasApiErrorKind.Http,
                $"请求失败（状态码 {(int)response.StatusCode}）");
        }

        var json = await response.Content.ReadAsStringAsync().ConfigureAwait(true);
        try
        {
            var dtos = JsonSerializer.Deserialize<List<CanvasCourseDto>>(json, JsonOpts) ?? new();
            return dtos.Select(CanvasCourse.FromDto).ToList();
        }
        catch (JsonException)
        {
            throw new CanvasApiException(CanvasApiErrorKind.Decode,
                "服务器返回的内容解析不了，确认一下网址是不是 Canvas 的地址");
        }
    }
}
