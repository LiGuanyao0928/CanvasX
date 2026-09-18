using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using CanvasDashboard.Models;
using CanvasDashboard.Services;

namespace CanvasDashboard.Views;

/// <summary>
/// "提醒时间" 页面：列出所有 Alarm（时间/重复规则/开关/删除），加一个"添加提醒时间"入口。
/// 对应 Mac 版 ScheduleViewController.swift。行是代码里手动拼的 UI 元素（不用
/// ItemsControl+DataTemplate 绑定），跟 Mac 版用 NSTableView cell 手动 configure 是同一个
///思路，减少 WPF 数据绑定踩坑的风险。
///
/// 每次增删/开关改动都会：1) 保存 schedule.json  2) 调 update_schedule_windows.py
/// 重新生成 Windows 计划任务——两步缺一不可，否则定时任务和 schedule.json 不同步。
/// </summary>
public partial class ScheduleView : UserControl
{
    private List<Alarm> _alarms = new();

    public ScheduleView()
    {
        InitializeComponent();
    }

    public void Reload()
    {
        _alarms = ScheduleStore.Load();
        RebuildRows();
    }

    private void RebuildRows()
    {
        AlarmsPanel.Children.Clear();
        foreach (var alarm in _alarms)
        {
            AlarmsPanel.Children.Add(BuildRow(alarm));
        }
        if (_alarms.Count == 0)
        {
            AlarmsPanel.Children.Add(new TextBlock
            {
                Text = "还没有设置提醒时间",
                Margin = new Thickness(12),
                Foreground = (Brush)FindResource("AppTextSecondaryBrush"),
            });
        }
    }

    private UIElement BuildRow(Alarm alarm)
    {
        var grid = new Grid { Margin = new Thickness(12, 10, 12, 10) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var textStack = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        textStack.Children.Add(new TextBlock
        {
            Text = alarm.TimeText,
            FontSize = 22,
            FontWeight = FontWeights.SemiBold,
            Foreground = (Brush)FindResource("AppTextPrimaryBrush"),
        });
        textStack.Children.Add(new TextBlock
        {
            Text = alarm.RepeatText,
            FontSize = 12,
            Foreground = (Brush)FindResource("AppTextSecondaryBrush"),
        });
        Grid.SetColumn(textStack, 0);
        grid.Children.Add(textStack);

        var toggle = new CheckBox
        {
            Content = "启用",
            IsChecked = alarm.Enabled,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(8, 0, 8, 0),
        };
        toggle.Checked += (_, _) => OnToggle(alarm, true);
        toggle.Unchecked += (_, _) => OnToggle(alarm, false);
        Grid.SetColumn(toggle, 1);
        grid.Children.Add(toggle);

        var editButton = new Button { Content = "编辑", Padding = new Thickness(10, 4, 10, 4), Margin = new Thickness(0, 0, 8, 0) };
        editButton.Click += (_, _) => OnEdit(alarm);
        Grid.SetColumn(editButton, 2);
        grid.Children.Add(editButton);

        var deleteButton = new Button
        {
            Content = "删除",
            Padding = new Thickness(10, 4, 10, 4),
            Foreground = (Brush)FindResource("AppDangerBrush"),
            ToolTip = "删除这条提醒时间",
        };
        deleteButton.Click += (_, _) => OnDelete(alarm);
        Grid.SetColumn(deleteButton, 3);
        grid.Children.Add(deleteButton);

        var border = new Border
        {
            Child = grid,
            BorderBrush = (Brush)FindResource("AppBorderBrush"),
            BorderThickness = new Thickness(0, 0, 0, 1),
        };
        return border;
    }

    private async void OnToggle(Alarm alarm, bool isOn)
    {
        alarm.Enabled = isOn;
        await SaveAndApplyAsync();
    }

    private void OnEdit(Alarm alarm)
    {
        var editor = new AlarmEditorWindow(alarm, isNew: false) { Owner = Window.GetWindow(this) };
        editor.Saved += async updated =>
        {
            var index = _alarms.FindIndex(a => a.Id == updated.Id);
            if (index >= 0) _alarms[index] = updated;
            RebuildRows();
            await SaveAndApplyAsync();
        };
        editor.Deleted += async () =>
        {
            _alarms.RemoveAll(a => a.Id == alarm.Id);
            RebuildRows();
            await SaveAndApplyAsync();
        };
        editor.ShowDialog();
    }

    private async void OnDelete(Alarm alarm)
    {
        var result = MessageBox.Show(Window.GetWindow(this), $"删除 {alarm.TimeText} 这条提醒时间？",
            "Canvas 作业追踪", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No);
        if (result != MessageBoxResult.Yes) return;

        _alarms.RemoveAll(a => a.Id == alarm.Id);
        RebuildRows();
        await SaveAndApplyAsync();
    }

    private void AddButton_Click(object sender, RoutedEventArgs e)
    {
        var editor = new AlarmEditorWindow(null, isNew: true) { Owner = Window.GetWindow(this) };
        editor.Saved += async newAlarm =>
        {
            _alarms.Add(newAlarm);
            RebuildRows();
            await SaveAndApplyAsync();
        };
        editor.ShowDialog();
    }

    private async Task SaveAndApplyAsync()
    {
        ScheduleStore.Save(_alarms);
        try
        {
            await ScheduleStore.ApplyAsync();
        }
        catch (Exception ex)
        {
            MessageBox.Show(Window.GetWindow(this),
                $"提醒时间已保存，但更新 Windows 计划任务失败：{ex.Message}\n\n" +
                "可以自己在项目目录手动运行一次：.venv\\Scripts\\python.exe update_schedule_windows.py",
                "Canvas 作业追踪", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }
}
