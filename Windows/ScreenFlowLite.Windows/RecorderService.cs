using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Windows;

namespace ScreenFlowLite.Windows;

public enum RecordingQuality { Standard, High, Ultra }

public sealed class RecorderService
{
    private Process? process;
    private readonly Stopwatch watch = new();
    private System.Timers.Timer? timer;
    private string? outputFile;
    public bool IsRecording => process is { HasExited: false };
    public event Action<TimeSpan>? ElapsedChanged;

    public Task StartAsync(string folder, Rect? region, RecordingQuality quality, bool systemAudio, bool microphone)
    {
        var ffmpeg = FindFfmpeg();
        Directory.CreateDirectory(folder);
        outputFile = Path.Combine(folder, $"录屏_{DateTime.Now:yyyy-MM-dd_HH-mm-ss}.mp4");
        var bitrate = quality switch { RecordingQuality.Standard => "8M", RecordingQuality.High => "20M", _ => "40M" };
        var sizeArgs = region is null ? "" : string.Create(CultureInfo.InvariantCulture,
            $"-offset_x {(int)region.Value.X} -offset_y {(int)region.Value.Y} -video_size {(int)region.Value.Width}x{(int)region.Value.Height} ");
        var inputs = $"-f gdigrab -framerate 30 -draw_mouse 1 {sizeArgs}-i desktop ";
        var maps = "-map 0:v ";
        var inputIndex = 1;
        if (systemAudio) { inputs += "-f dshow -i audio=\"Stereo Mix\" "; maps += $"-map {inputIndex++}:a? "; }
        if (microphone) { inputs += "-f dshow -i audio=\"default\" "; maps += $"-map {inputIndex}:a? "; }
        var args = $"-y {inputs}{maps}-c:v libx264 -preset veryfast -b:v {bitrate} -pix_fmt yuv420p -c:a aac -b:a 192k \"{outputFile}\"";
        process = new Process { StartInfo = new ProcessStartInfo(ffmpeg, args) { UseShellExecute = false, RedirectStandardInput = true, RedirectStandardError = true, CreateNoWindow = true } };
        process.Start();
        watch.Restart(); timer = new System.Timers.Timer(500); timer.Elapsed += (_, _) => ElapsedChanged?.Invoke(watch.Elapsed); timer.Start();
        return Task.CompletedTask;
    }

    public async Task<string> StopAsync()
    {
        if (process is null || outputFile is null) throw new InvalidOperationException("当前没有录制任务");
        await process.StandardInput.WriteLineAsync("q");
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(8));
        try { await process.WaitForExitAsync(timeout.Token); } catch { process.Kill(true); }
        timer?.Stop(); timer?.Dispose(); watch.Stop();
        if (!File.Exists(outputFile) || new FileInfo(outputFile).Length == 0) throw new InvalidOperationException("FFmpeg 未生成有效视频，请检查音频设备名称和权限");
        return outputFile;
    }

    private static string FindFfmpeg()
    {
        var local = Path.Combine(AppContext.BaseDirectory, "ffmpeg.exe");
        if (File.Exists(local)) return local;
        return "ffmpeg.exe";
    }
}
