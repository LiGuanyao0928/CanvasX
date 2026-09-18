using System.Diagnostics;
using System.IO;
using System.Text.Json;
using CanvasDashboard;
using Microsoft.Web.WebView2.Core;

namespace CanvasDashboard.Services;

/// <summary>
/// 网页 &lt;-&gt; 原生代码的桥接层，对应 Mac 版 native_app/Bridge.swift——设置向导
/// (setup_wizard.html)、设置面板 (settings.html)、提醒时间 (schedule.html) 都是普通网页，
/// 通过这层桥接调用原生能力（读写配置文件、跑 Python 脚本、开关窗口）。
///
/// JS 那边（bridge.js 的 NativeBridge.send）用 window.chrome.webview.postMessage 发送
/// {id, action, payload}，这里在 CoreWebView2.WebMessageReceived 里接住、按 action 分发、
/// 干完活用 ExecuteScriptAsync 把结果送回页面的 window.__bridgeResult(id, ok, data)。
///
/// 这是把三块原生专属界面（向导/设置/提醒编辑器）从"Mac 和 Windows 各写一份原生代码"
/// 改成"两边共用同一份网页"这次重构的核心——具体背景见 PARITY.md。
/// </summary>
public sealed class NativeBridge
{
    private readonly CoreWebView2 _webView;

    private NativeBridge(CoreWebView2 webView)
    {
        _webView = webView;
    }

    public static void Install(CoreWebView2 webView)
    {
        var bridge = new NativeBridge(webView);
        webView.WebMessageReceived += bridge.OnWebMessageReceived;
    }

    // WebView2 的消息事件是在这个控件所属的 UI 线程（STA）上触发的，用 async void
    // 直接处理没问题——它不像别处那样有"返回值没人等"的调用方，是事件处理器的标准写法，
    // 内部把所有异常都兜住，不会变成没人处理的异常炸掉整个 App。
    private async void OnWebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        int id;
        string action;
        JsonElement payload;

        try
        {
            using var doc = JsonDocument.Parse(e.WebMessageAsJson);
            var root = doc.RootElement;
            id = root.GetProperty("id").GetInt32();
            action = root.GetProperty("action").GetString() ?? "";
            // Clone：doc 在这个 using 块结束后就释放了，payload 得脱离它独立存活，
            // 后面跑完 Python 脚本再来读里面的字段。
            payload = root.TryGetProperty("payload", out var p)
                ? p.Clone()
                : JsonDocument.Parse("{}").RootElement.Clone();
        }
        catch
        {
            // 连 id 都解析不出来，没法回复——跟 Mac 版 didReceive message 的 guard 一样直接丢弃。
            return;
        }

        try
        {
            await DispatchAsync(action, payload,
                onSuccess: json => Respond(id, ok: true, jsonOrMessage: json),
                onFailure: message => Respond(id, ok: false, jsonOrMessage: JsonSerializer.Serialize(message)));
        }
        catch (Exception ex)
        {
            Respond(id, ok: false, jsonOrMessage: JsonSerializer.Serialize(ex.Message));
        }
    }

    private void Respond(int id, bool ok, string jsonOrMessage)
    {
        // 额外包一层圆括号纯粹是防御性写法（跟 Mac 版 evaluateJavaScript 里的做法一样），
        // 这里其实用不上——jsonOrMessage 只会是函数调用的一个参数表达式，没有语句开头
        // 歧义的风险，但加上也没坏处。
        var script = $"window.__bridgeResult({id}, {(ok ? "true" : "false")}, ({jsonOrMessage}))";
        _ = _webView.ExecuteScriptAsync(script);
    }

    /// <summary>
    /// action 分发表，逐条对应 Bridge.swift 的 handle(action:payload:completion:)。
    /// onSuccess/onFailure 各自只应该被调用一次（对应 Swift 那边的 completion 闭包）；
    /// 没有显式调用任何一个、又没抛异常的分支不存在——default 分支兜底未知 action。
    /// </summary>
    private static async Task DispatchAsync(
        string action, JsonElement payload, Action<string> onSuccess, Action<string> onFailure)
    {
        switch (action)
        {
            case "fetchCourses":
            {
                // payload 已经是 {baseUrl, token}，跟 fetch_courses.py 期望的 stdin 格式
                // 完全一致，原样透传，不用在这两边之间再搭一层 C# DTO。
                var (code, stdout, stderr) = await PythonRunner.RunJsonRawAsync(
                    new[] { "fetch_courses.py" }, payload.GetRawText()).ConfigureAwait(true);
                if (code != 0)
                {
                    onFailure(string.IsNullOrEmpty(stderr) ? "脚本运行失败" : stderr);
                    return;
                }
                // stdout 已经是合法的 JSON 数组文本（课程列表），直接当结果透传给网页，
                // 不用先反序列化成 C# 类型再序列化回去绕一圈。
                onSuccess(stdout);
                return;
            }

            case "completeSetup":
            {
                var (code, _, stderr) = await PythonRunner.RunJsonRawAsync(
                    new[] { "write_config.py" }, payload.GetRawText()).ConfigureAwait(true);
                if (code != 0)
                {
                    onFailure(string.IsNullOrEmpty(stderr) ? "脚本运行失败" : stderr);
                    return;
                }

                // "记住我"没勾选（公用电脑场景）：记下这个偏好，App.OnExit 会读它，
                // 决定退出时要不要自动清掉刚写的这些本机文件。默认值必须是 true。
                var rememberMe = !(payload.ValueKind == JsonValueKind.Object
                    && payload.TryGetProperty("rememberMe", out var rm)
                    && rm.ValueKind == JsonValueKind.False);
                var prefs = PrefsStore.Load();
                prefs.RememberLogin = rememberMe;
                PrefsStore.Save(prefs);

                // 首次同步失败也不阻塞流程——忽略退出码，跟 Mac 版 runPython(...) { _ in ... } 一样，
                // 进主窗口后用户随时能手动点"立即同步"重试。
                await PythonRunner.RunAsync(new[] { "canvas_sync.py", "--refresh" }).ConfigureAwait(true);

                onSuccess("true");
                App.FinishSetupWizard();
                return;
            }

            case "getEnv":
                onSuccess(JsonSerializer.Serialize(EnvFile.Load()));
                return;

            case "getPrefs":
            {
                var prefs = PrefsStore.Load();
                onSuccess(JsonSerializer.Serialize(new { theme = prefs.Theme, language = prefs.Language }));
                return;
            }

            case "setPrefs":
            {
                var prefs = PrefsStore.Load();
                if (payload.ValueKind == JsonValueKind.Object)
                {
                    if (payload.TryGetProperty("theme", out var themeEl) && themeEl.ValueKind == JsonValueKind.String)
                    {
                        var theme = themeEl.GetString() ?? "system";
                        prefs.Theme = theme;
                        ThemeManager.Apply(theme);
                    }
                    if (payload.TryGetProperty("language", out var langEl) && langEl.ValueKind == JsonValueKind.String)
                    {
                        prefs.Language = langEl.GetString() ?? "zh";
                    }
                }
                PrefsStore.Save(prefs);
                onSuccess("true");
                return;
            }

            case "syncNow":
                await PythonRunner.RunAsync(new[] { "canvas_sync.py", "--refresh" }).ConfigureAwait(true);
                onSuccess("true");
                App.ReloadMainWindowCurrentSection();
                return;

            case "logout":
                await PythonRunner.RunAsync(new[] { "clear_local_user_data.py" }).ConfigureAwait(true);
                onSuccess("true");
                App.PerformLogoutTransition();
                return;

            case "openLogs":
                try
                {
                    Directory.CreateDirectory(ProjectPaths.LogsDir);
                    Process.Start(new ProcessStartInfo("explorer.exe", ProjectPaths.LogsDir) { UseShellExecute = true });
                }
                catch
                {
                    // 跟 Mac 版一样：打开失败不算错误，不阻塞用户（比如 explorer.exe 意外不可用）。
                }
                onSuccess("true");
                return;

            case "openWizard":
                App.ShowSetupWizard();
                onSuccess("true");
                return;

            case "getSchedule":
                onSuccess(ScheduleStore.LoadAlarmsJson());
                return;

            case "saveSchedule":
            {
                var alarmsJson = payload.ValueKind == JsonValueKind.Object
                    && payload.TryGetProperty("alarms", out var alarmsEl)
                    && alarmsEl.ValueKind == JsonValueKind.Array
                        ? alarmsEl.GetRawText()
                        : "[]";
                ScheduleStore.Save(alarmsJson);
                await ScheduleStore.ApplyAsync().ConfigureAwait(true);
                onSuccess("true");
                return;
            }

            default:
                onFailure($"未知的桥接调用：{action}");
                return;
        }
    }
}
