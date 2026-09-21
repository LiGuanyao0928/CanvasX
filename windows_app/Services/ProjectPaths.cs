using System.IO;

namespace CanvasDashboard.Services;

/// <summary>
/// 项目根目录解析。不能像 Mac 版那样"用 App 自己所在位置往上推一层"就假设是项目目录——
/// dotnet publish 的输出目录结构（尤其是 PublishSingleFile 自解压后的临时目录、
/// 用户又把 exe 单独拷到别处运行等情况）没法保证跟源码目录是"父子"这么简单的关系。
///
/// 做法：从 exe 所在目录（AppContext.BaseDirectory）开始，一路往上找父目录，
/// 找到第一个包含 canvas_sync.py 的目录就当作项目根目录；全部找不到的话退回当前工作目录
/// 再试一次；还是找不到就明确报错（调用方负责弹出中文提示，不能静默失败）。
///
/// 这是整个 Windows 客户端里最可能需要在真机上调整的一处"胶水代码"——如果你打包/放置
/// exe 的方式跟设想的不一样（比如把编译产物整个文件夹挪到了跟 canvas_sync.py 不在同一棵
/// 目录树下的地方），这里就会找不到，需要相应调整判定文件名或者搜索逻辑。
/// </summary>
public static class ProjectPaths
{
    private const string MarkerFile = "canvas_sync.py";

    private static string? _root;

    public static string ProjectRoot => _root ??= Resolve();

    private static string Resolve()
    {
        var found = SearchUpwardsFrom(AppContext.BaseDirectory)
                    ?? SearchUpwardsFrom(Directory.GetCurrentDirectory());

        if (found != null) return found;

        throw new InvalidOperationException(
            $"从 \"{AppContext.BaseDirectory}\" 和当前工作目录往上找，都没能找到包含 {MarkerFile} 的文件夹。");
    }

    private static string? SearchUpwardsFrom(string startDirectory)
    {
        var dir = new DirectoryInfo(startDirectory);
        while (dir != null)
        {
            if (File.Exists(Path.Combine(dir.FullName, MarkerFile)))
                return dir.FullName;
            dir = dir.Parent;
        }
        return null;
    }

    public static string PythonExe => Path.Combine(ProjectRoot, ".venv", "Scripts", "python.exe");

    public static string DashboardHtml => Path.Combine(ProjectRoot, "dashboard.html");
    public static string MaterialsHtml => Path.Combine(ProjectRoot, "materials.html");
    public static string GradesHtml => Path.Combine(ProjectRoot, "grades.html");
    // "提醒时间"现在也是网页（schedule.html），跟其它板块一样在主窗口同一个 WebView2
    // 里加载，不再是原生 ScheduleView/AlarmEditorWindow——五个板块完全对称，见 MainWindow。
    public static string ScheduleHtml => Path.Combine(ProjectRoot, "schedule.html");
    // 课程表：星期几/几点/教室是用户自己填的（教务系统才有这份数据，Canvas 没有），
    // 课程名字通过 getCourses 桥接调用对接本机已同步的真实 Canvas 课程列表。
    public static string TimetableHtml => Path.Combine(ProjectRoot, "timetable.html");

    public static string LogsDir => Path.Combine(ProjectRoot, "logs");
}
