using System.Diagnostics;
using System.IO;
using System.Text;

namespace CanvasDashboard.Services;

public class PythonRunException : Exception
{
    public int ExitCode { get; }
    public string StdErr { get; }

    public PythonRunException(string[] args, int exitCode, string stdErr)
        : base($"python {string.Join(' ', args)} 运行失败（退出码 {exitCode}）：{stdErr}")
    {
        ExitCode = exitCode;
        StdErr = stdErr;
    }
}

/// <summary>
/// 统一负责"用项目自带的 .venv 跑一个 Python 脚本"这件事——每次调用都把
/// WorkingDirectory 设成项目根目录（脚本内部用的是相对路径，比如 canvas.db、
/// dashboard.html），跟 Mac 版 main.swift 里 runPython 的做法一致。
///
/// 所有课程资料的增删调用都必须按顺序 await 完再进行下一个——不要用
/// Task.WhenAll 之类的并发调用，之前在 Mac 版上真的因为并发写 SQLite
/// 遇到过"database is locked"，这里照抄同样的谨慎做法。
/// </summary>
public static class PythonRunner
{
    // 特意不用 Encoding.UTF8 这个静态常量——它自带 BOM 前导字节，StreamWriter 会在
    // 第一次写入时把 EF BB BF 这三个字节也写进子进程的 stdin。fetch_courses.py /
    // write_config.py 用的是 json.load(sys.stdin)（文本模式，不认 BOM），一旦带了 BOM，
    // 每次调用都会在第一个字符上直接报 JSONDecodeError，看起来像"桥接完全不能用"，
    // 其实只是编码选错了。用不带 BOM 的 UTF8Encoding 构造函数规避这个坑。
    private static readonly Encoding Utf8NoBom = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false);

    public static Task<int> RunAsync(IEnumerable<string> arguments) => RunAsync(arguments, null);

    /// <summary>
    /// 纯同步版本，专门给 App.xaml.cs 的 OnExit 这种地方用——退出钩子返回之后进程
    /// 就真的没了，不能安全地 await 一个还没跑完的续体（RunAsync 内部
    /// ConfigureAwait(true) 会尝试回到 UI 线程续体，退出时 UI 线程已经在等这个
    /// 调用本身返回，会死锁）。清几个小文件是毫秒级操作，直接同步阻塞完全够用，
    /// 加个超时兜底避免 python 卡住时无限期挡住 App 退出。
    /// </summary>
    public static int RunSyncBlocking(IEnumerable<string> arguments, int timeoutMs = 5000)
    {
        var args = arguments.ToArray();
        var pythonExe = ProjectPaths.PythonExe;
        if (!File.Exists(pythonExe)) return -1;

        var psi = new ProcessStartInfo
        {
            FileName = pythonExe,
            WorkingDirectory = ProjectPaths.ProjectRoot,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        foreach (var a in args) psi.ArgumentList.Add(a);

        try
        {
            using var process = Process.Start(psi);
            if (process == null) return -1;
            process.WaitForExit(timeoutMs);
            return process.HasExited ? process.ExitCode : -1;
        }
        catch
        {
            return -1;
        }
    }

    public static async Task<int> RunAsync(IEnumerable<string> arguments, string? logFilePath)
    {
        var args = arguments.ToArray();
        var pythonExe = ProjectPaths.PythonExe;

        if (!File.Exists(pythonExe))
        {
            throw new InvalidOperationException(
                $"找不到 Python 虚拟环境（{pythonExe}）。请先在项目目录运行 setup.bat，" +
                "或者手动执行 python -m venv .venv 然后 .venv\\Scripts\\pip install -r requirements.txt。");
        }

        var psi = new ProcessStartInfo
        {
            FileName = pythonExe,
            WorkingDirectory = ProjectPaths.ProjectRoot,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        foreach (var a in args) psi.ArgumentList.Add(a);

        using var process = new Process { StartInfo = psi };
        process.Start();

        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        var stderrTask = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync().ConfigureAwait(true);
        var stdout = await stdoutTask.ConfigureAwait(true);
        var stderr = await stderrTask.ConfigureAwait(true);

        if (logFilePath != null)
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(logFilePath)!);
                await File.WriteAllTextAsync(logFilePath, stdout + Environment.NewLine + stderr)
                    .ConfigureAwait(true);
            }
            catch
            {
                // 写日志失败不应该影响主流程
            }
        }

        return process.ExitCode;
    }

    /// <summary>
    /// 给 list_tracked_courses.py 这类不需要 stdin、直接读本地文件/数据库就能出结果的
    /// 脚本用：只捕获 stdout/stderr 一起返回，不写任何输入。对应 Mac 版 Bridge.swift 的
    /// runPythonCaptureOutput。
    /// </summary>
    public static async Task<(int ExitCode, string StdOut, string StdErr)> RunCaptureOutputAsync(
        IEnumerable<string> arguments)
    {
        var args = arguments.ToArray();
        var pythonExe = ProjectPaths.PythonExe;

        if (!File.Exists(pythonExe))
        {
            throw new InvalidOperationException(
                $"找不到 Python 虚拟环境（{pythonExe}）。请先在项目目录运行 setup.bat。");
        }

        var psi = new ProcessStartInfo
        {
            FileName = pythonExe,
            WorkingDirectory = ProjectPaths.ProjectRoot,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Utf8NoBom,
            StandardErrorEncoding = Utf8NoBom,
        };
        foreach (var a in args) psi.ArgumentList.Add(a);

        using var process = new Process { StartInfo = psi };
        process.Start();

        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        var stderrTask = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync().ConfigureAwait(true);
        var stdout = (await stdoutTask.ConfigureAwait(true)).Trim();
        var stderr = (await stderrTask.ConfigureAwait(true)).Trim();

        return (process.ExitCode, stdout, stderr);
    }

    /// <summary>
    /// 给 fetch_courses.py / write_config.py 这类"从 stdin 读一段 JSON、把结果/错误打到
    /// stdout/stderr"的脚本用：写一段 JSON 文本到子进程 stdin，捕获 stdout 和 stderr 一起
    /// 返回（不像 RunAsync 那样只关心退出码）。对应 Mac 版 Bridge.swift 的 runPythonJSON。
    ///
    /// 全程 async/await，不涉及 UI 线程同步阻塞等待，调用方（NativeBridge 的
    /// WebMessageReceived 处理）本身就是 async void，这里放心 await 到底就行。
    /// </summary>
    public static async Task<(int ExitCode, string StdOut, string StdErr)> RunJsonRawAsync(
        IEnumerable<string> arguments, string stdinJson)
    {
        var args = arguments.ToArray();
        var pythonExe = ProjectPaths.PythonExe;

        if (!File.Exists(pythonExe))
        {
            throw new InvalidOperationException(
                $"找不到 Python 虚拟环境（{pythonExe}）。请先在项目目录运行 setup.bat，" +
                "或者手动执行 python -m venv .venv 然后 .venv\\Scripts\\pip install -r requirements.txt。");
        }

        var psi = new ProcessStartInfo
        {
            FileName = pythonExe,
            WorkingDirectory = ProjectPaths.ProjectRoot,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardInputEncoding = Utf8NoBom,
            StandardOutputEncoding = Utf8NoBom,
            StandardErrorEncoding = Utf8NoBom,
        };
        foreach (var a in args) psi.ArgumentList.Add(a);

        using var process = new Process { StartInfo = psi };
        process.Start();

        // 先把读 stdout/stderr 的两个任务挂起来，再写 stdin 关闭它——不要反过来。
        // 这两个脚本输出量很小（几百字节到几 KB），理论上不会撑爆管道缓冲区，但顺序
        // 写对了不费事，干脆照着"不会死锁"的写法来，参考 Mac 版的注释。
        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        var stderrTask = process.StandardError.ReadToEndAsync();

        await process.StandardInput.WriteAsync(stdinJson).ConfigureAwait(true);
        process.StandardInput.Close();

        await process.WaitForExitAsync().ConfigureAwait(true);
        var stdout = (await stdoutTask.ConfigureAwait(true)).Trim();
        var stderr = (await stderrTask.ConfigureAwait(true)).Trim();

        return (process.ExitCode, stdout, stderr);
    }
}
