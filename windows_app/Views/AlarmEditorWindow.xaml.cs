using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using CanvasDashboard.Models;

namespace CanvasDashboard.Views;

/// <summary>
/// 添加/编辑一条提醒时间：小时(0-23)、分钟(0-59)、星期几重复、启用开关。
/// 对应 Mac 版 AlarmEditorWindowController.swift，只是把"滚轮上滚动调整数字"换成了
/// 更普适的 ▲▼ 按钮（功能等价，不需要跟 Mac 版视觉一致）。
/// </summary>
public partial class AlarmEditorWindow : Window
{
    public event Action<Alarm>? Saved;
    public event Action? Deleted;

    private readonly Alarm _alarm;
    private readonly bool _isNew;
    private int _hour;
    private int _minute;
    private readonly List<ToggleButton> _dayButtons = new();

    private static readonly int[] AllDays = { 0, 1, 2, 3, 4, 5, 6 };
    private static readonly int[] WeekdayDays = { 1, 2, 3, 4, 5 };
    private static readonly int[] WeekendDays = { 0, 6 };

    public AlarmEditorWindow(Alarm? alarm, bool isNew)
    {
        InitializeComponent();
        _alarm = alarm ?? Alarm.CreateDefault();
        _isNew = isNew;
        _hour = _alarm.Hour;
        _minute = _alarm.Minute;

        Title = isNew ? "添加提醒时间" : "编辑提醒时间";
        TitleLabel.Text = isNew ? "添加提醒时间" : "编辑提醒时间";
        DeleteButton.Visibility = isNew ? Visibility.Collapsed : Visibility.Visible;
        EnabledCheckBox.IsChecked = _alarm.Enabled;

        UpdateTimeLabels();
        BuildDayButtons();
        BuildPresetButtons();
    }

    private void BuildDayButtons()
    {
        DayButtonsPanel.Children.Clear();
        _dayButtons.Clear();
        for (var i = 0; i < Alarm.DayLabels.Length; i++)
        {
            var day = i;
            var btn = new ToggleButton
            {
                Content = Alarm.DayLabels[day],
                Width = 32,
                Height = 32,
                Margin = new Thickness(3, 0, 3, 0),
                IsChecked = _alarm.Days.Contains(day),
            };
            ApplyDayButtonAppearance(btn);
            btn.Checked += (_, _) => ApplyDayButtonAppearance(btn);
            btn.Unchecked += (_, _) => ApplyDayButtonAppearance(btn);
            _dayButtons.Add(btn);
            DayButtonsPanel.Children.Add(btn);
        }
    }

    private void ApplyDayButtonAppearance(ToggleButton btn)
    {
        var isOn = btn.IsChecked == true;
        btn.Background = isOn
            ? (Brush)FindResource("AppAccentBrush")
            : (Brush)FindResource("AppControlBackgroundBrush");
        btn.Foreground = isOn
            ? (Brush)FindResource("AppAccentForegroundBrush")
            : (Brush)FindResource("AppTextPrimaryBrush");
    }

    private void BuildPresetButtons()
    {
        PresetButtonsPanel.Children.Clear();
        AddPreset("每天", AllDays);
        AddPreset("工作日", WeekdayDays);
        AddPreset("周末", WeekendDays);
    }

    private void AddPreset(string label, int[] days)
    {
        var btn = new Button { Content = label, Padding = new Thickness(10, 4, 10, 4), Margin = new Thickness(4, 0, 4, 0), FontSize = 11 };
        btn.Click += (_, _) =>
        {
            var set = new HashSet<int>(days);
            foreach (var dayBtn in _dayButtons)
            {
                var day = _dayButtons.IndexOf(dayBtn);
                dayBtn.IsChecked = set.Contains(day);
            }
        };
        PresetButtonsPanel.Children.Add(btn);
    }

    private void UpdateTimeLabels()
    {
        HourText.Text = _hour.ToString("D2");
        MinuteText.Text = _minute.ToString("D2");
    }

    private void HourUp_Click(object sender, RoutedEventArgs e)
    {
        _hour = _hour == 23 ? 0 : _hour + 1;
        UpdateTimeLabels();
    }

    private void HourDown_Click(object sender, RoutedEventArgs e)
    {
        _hour = _hour == 0 ? 23 : _hour - 1;
        UpdateTimeLabels();
    }

    private void MinuteUp_Click(object sender, RoutedEventArgs e)
    {
        _minute = _minute == 59 ? 0 : _minute + 1;
        UpdateTimeLabels();
    }

    private void MinuteDown_Click(object sender, RoutedEventArgs e)
    {
        _minute = _minute == 0 ? 59 : _minute - 1;
        UpdateTimeLabels();
    }

    private void CancelButton_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }

    private void DeleteButton_Click(object sender, RoutedEventArgs e)
    {
        Deleted?.Invoke();
        DialogResult = true;
        Close();
    }

    private void SaveButton_Click(object sender, RoutedEventArgs e)
    {
        _alarm.Hour = _hour;
        _alarm.Minute = _minute;
        _alarm.Enabled = EnabledCheckBox.IsChecked == true;
        _alarm.Days = _dayButtons
            .Select((btn, index) => (btn, index))
            .Where(x => x.btn.IsChecked == true)
            .Select(x => x.index)
            .ToList();

        Saved?.Invoke(_alarm);
        DialogResult = true;
        Close();
    }
}
