# 轻录屏

一个使用 macOS ScreenCaptureKit + AVFoundation 开发的原生录屏工具。

## 功能

- 拖拽选择屏幕区域录制
- 全屏录制
- 0 / 3 / 5 秒倒计时
- H.264 MP4 输出，保留 Retina 清晰度
- 自定义保存目录
- 显示鼠标指针，完成后自动在访达定位

## 构建和运行

```bash
chmod +x build-app.sh
./build-app.sh
open dist/轻录屏.app
```

首次录制时，请在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”中授权，然后重新打开应用。

## 文档与 Windows 版本

- 完整使用说明：[`docs/使用说明.md`](docs/使用说明.md)
- Windows 10/11 客户端：[`Windows/ScreenFlowLite.Windows`](Windows/ScreenFlowLite.Windows)
- Windows 构建说明：[`Windows/README.md`](Windows/README.md)
