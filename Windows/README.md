# 轻录屏 Windows

这是与 macOS 版对应的 Windows 10/11 WPF 客户端。

功能：全屏、可移动缩放区域、三档画质、系统音频、麦克风、计时、资源管理器定位、`Ctrl + Alt + R` 全局快捷键。

Windows 的音频设备名称因驱动而异。系统音频默认使用 `Stereo Mix`，麦克风默认使用 `default`；若 FFmpeg 报设备不存在，请运行：

```powershell
ffmpeg -list_devices true -f dshow -i dummy
```

然后在 `RecorderService.cs` 中替换对应设备名称。生产版本建议在此基础上增加设备下拉选择。
