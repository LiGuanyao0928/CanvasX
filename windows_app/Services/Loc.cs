namespace CanvasDashboard.Services;

/// <summary>
/// 极简字符串表，只给"设置"窗口自己用——按用户明确的范围决定：语言切换只影响这一个
/// 窗口的文字，不做全应用国际化。中文是唯一真源（跟其它所有 UI 文字一样的语气），
/// English 是给这一扇窗户的翻译。
/// </summary>
public static class Loc
{
    private static readonly Dictionary<string, (string Zh, string En)> Table = new()
    {
        ["settings.title"] = ("设置", "Settings"),

        ["settings.section.appearance"] = ("外观", "Appearance"),
        ["settings.appearance.system"] = ("跟随系统", "Match system"),
        ["settings.appearance.light"] = ("浅色", "Light"),
        ["settings.appearance.dark"] = ("深色", "Dark"),

        ["settings.section.language"] = ("语言", "Language"),
        ["settings.language.zh"] = ("中文", "Chinese"),
        ["settings.language.en"] = ("English", "English"),

        ["settings.section.account"] = ("账号", "Account"),
        ["settings.account.baseurl.label"] = ("Canvas 网址", "Canvas URL"),
        ["settings.account.baseurl.empty"] = ("（还没设置）", "(not set)"),
        ["settings.account.reconfigure"] = ("重新选课 / 更换 Token", "Re-pick courses / change token"),
        ["settings.account.logout"] = ("退出登录", "Log out"),
        ["settings.account.logout.confirm.title"] = ("确定要退出登录吗？", "Log out?"),
        ["settings.account.logout.confirm.body"] =
            ("会清空这台电脑上保存的 Canvas 账号信息和所有同步数据（作业/资料/成绩缓存），" +
             "下一个用这台电脑的人不会看到你的任何数据。这一步不能撤销。",
             "This clears the Canvas account info and all synced data (assignments / materials / " +
             "grades cache) stored on this computer, so the next person to use it won't see any of " +
             "your data. This cannot be undone."),

        ["settings.section.other"] = ("其它", "Other"),
        ["settings.sync.now"] = ("立即同步", "Sync now"),
        ["settings.sync.inprogress"] = ("同步中…", "Syncing…"),
        ["settings.sync.failed.title"] = ("同步失败", "Sync failed"),
        ["settings.logs.open"] = ("打开日志文件夹", "Open logs folder"),
        ["settings.calendar.note"] =
            ("作业日历文件：项目目录下的 canvas_assignments.ics，导入到 Outlook / Google 日历就能看到截止日期",
             "Assignment calendar file: canvas_assignments.ics in the project folder — " +
             "import it into Outlook / Google Calendar to see due dates"),

        ["settings.section.about"] = ("关于", "About"),
        ["settings.about.body"] =
            ("Canvas 作业追踪 · Windows 版\n个人 Canvas LMS 作业追踪工具，非官方，与 Instructure 无关。",
             "Canvas Assignment Tracker · Windows\nA personal Canvas LMS assignment tracker. " +
             "Unofficial, not affiliated with Instructure."),

        ["settings.close"] = ("关闭", "Close"),
    };

    public static string T(string key, string lang) =>
        Table.TryGetValue(key, out var v) ? (lang == "en" ? v.En : v.Zh) : key;
}
