using Microsoft.Win32;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Interop;

namespace ScreenFlowLite.Windows;

public partial class MainWindow : Window
{
    private readonly RecorderService recorder = new();
    private string outputFolder = Environment.GetFolderPath(Environment.SpecialFolder.MyVideos);
    private const int HotKeyId = 9001;

    public MainWindow()
    {
        InitializeComponent(); FolderText.Text = outputFolder;
        ModeBox.SelectionChanged += (_, _) => StartButton.Content = ModeBox.SelectedIndex == 0 ? "选择区域并录制" : "开始全屏录制";
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        var source = HwndSource.FromHwnd(new WindowInteropHelper(this).Handle);
        source.AddHook(WndProc);
        NativeMethods.RegisterHotKey(source.Handle, HotKeyId, NativeMethods.MOD_CONTROL | NativeMethods.MOD_ALT, 0x52);
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == NativeMethods.WM_HOTKEY && wParam.ToInt32() == HotKeyId) { _ = BeginRecording(); handled = true; }
        return IntPtr.Zero;
    }

    private async void Start_Click(object sender, RoutedEventArgs e) => await BeginRecording();

    private async Task BeginRecording()
    {
        if (recorder.IsRecording) { await StopRecording(); return; }
        Rect? region = null;
        if (ModeBox.SelectedIndex == 0)
        {
            var selector = new RegionSelectorWindow();
            if (selector.ShowDialog() != true) return;
            region = selector.SelectedRegion;
        }
        try
        {
            var quality = (RecordingQuality)QualityBox.SelectedIndex;
            await recorder.StartAsync(outputFolder, region, quality, SystemAudioBox.IsChecked == true, MicrophoneBox.IsChecked == true);
            StartButton.Content = "停止录制"; StatusText.Text = "正在录制…";
            recorder.ElapsedChanged += OnElapsed;
        }
        catch (Exception ex) { StatusText.Text = "启动失败：" + ex.Message; }
    }

    private void OnElapsed(TimeSpan value) => Dispatcher.Invoke(() => StatusText.Text = $"● 正在录制 {value:mm\\:ss}");

    private async Task StopRecording()
    {
        var file = await recorder.StopAsync(); recorder.ElapsedChanged -= OnElapsed;
        StartButton.Content = ModeBox.SelectedIndex == 0 ? "选择区域并录制" : "开始全屏录制";
        StatusText.Text = "录制完成：" + Path.GetFileName(file);
        if (RevealBox.IsChecked == true) Process.Start("explorer.exe", $"/select,\"{file}\"");
    }

    private void ChooseFolder_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { InitialDirectory = outputFolder };
        if (dialog.ShowDialog() == true) { outputFolder = dialog.FolderName; FolderText.Text = outputFolder; }
    }
}
