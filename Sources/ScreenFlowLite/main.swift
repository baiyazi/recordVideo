import AppKit
import SwiftUI
import ScreenCaptureKit
import AVFoundation
import Carbon
import CoreImage

final class DiagnosticLogger: @unchecked Sendable {
    static let shared = DiagnosticLogger()
    let url: URL
    private let queue = DispatchQueue(label: "screenflowlite.diagnostics")
    private let formatter = ISO8601DateFormatter()

    private init() {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        url = directory.appendingPathComponent("轻录屏-诊断日志.txt")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
    }

    func beginSession() {
        queue.sync {
            let header = "\n\n========== New recording session \(formatter.string(from: Date())) ==========\n"
            append(header)
        }
    }

    func log(_ message: String) {
        queue.async { [self] in append("[\(formatter.string(from: Date()))] \(message)\n") }
    }

    private func append(_ text: String) {
        let data = Data(text.utf8)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: data)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        try? handle.seekToEnd(); try? handle.write(contentsOf: data)
    }
}

@main
struct ScreenFlowLiteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands { CommandGroup(replacing: .appSettings) {} }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let recorder = ScreenRecorder()
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 550),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "轻录屏"
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.delegate = self
        window.contentView = NSHostingView(rootView:
            ContentView().environmentObject(recorder).frame(width: 460, height: 550)
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        mainWindow = window
        NSApp.activate(ignoringOtherApps: true)
        closePlaceholderSettingsWindows()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        closePlaceholderSettingsWindows()
    }

    private func closePlaceholderSettingsWindows() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for window in NSApp.windows where window !== self.mainWindow {
                if window.title.localizedCaseInsensitiveContains("settings") ||
                   window.title.localizedCaseInsensitiveContains("设置") {
                    window.orderOut(nil)
                    window.close()
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { mainWindow?.makeKeyAndOrderFront(nil) }
        sender.activate(ignoringOtherApps: true)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

struct ContentView: View {
    @EnvironmentObject var recorder: ScreenRecorder

    var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "record.circle.fill")
                    .font(.system(size: 38)).foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 3) {
                    Text("轻录屏").font(.title2.bold())
                    Text("简单、快速的 macOS 原生录屏工具")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Picker("录制范围", selection: $recorder.captureMode) {
                Label("划定区域", systemImage: "viewfinder").tag(CaptureMode.region)
                Label("全屏", systemImage: "rectangle.inset.filled").tag(CaptureMode.fullScreen)
            }
            .pickerStyle(.segmented)

            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("开始倒计时", systemImage: "timer")
                        Spacer()
                        Picker("", selection: $recorder.countdownSeconds) {
                            Text("立即").tag(0)
                            Text("3 秒").tag(3)
                            Text("5 秒").tag(5)
                        }.frame(width: 100)
                    }
                    Divider()
                    HStack {
                        Label("全局快捷键", systemImage: "command")
                        Spacer()
                        Picker("", selection: $recorder.hotKeyChoice) {
                            ForEach(HotKeyChoice.allCases, id: \.self) { choice in
                                Text(choice.title).tag(choice)
                            }
                        }
                        .frame(width: 150)
                        .onChange(of: recorder.hotKeyChoice) { _ in recorder.configureShortcut() }
                    }
                    Divider()
                    HStack {
                        Label("录制画质", systemImage: "sparkles.tv")
                        Spacer()
                        Picker("", selection: $recorder.quality) {
                            ForEach(RecordingQuality.allCases, id: \.self) { quality in
                                Text(quality.title).tag(quality)
                            }
                        }
                        .frame(width: 160)
                        .disabled(recorder.state == .recording)
                    }
                    Divider()
                    HStack {
                        Label("保存到", systemImage: "folder")
                        Spacer()
                        Text(recorder.outputDirectory.lastPathComponent)
                            .foregroundStyle(.secondary).lineLimit(1)
                        Button("更改…") { recorder.chooseOutputDirectory() }
                    }
                    Toggle("录制完成后在访达中显示", isOn: $recorder.revealAfterRecording)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Toggle("录制系统音频", isOn: $recorder.recordSystemAudio)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .disabled(recorder.state == .recording)
                    Toggle("录制麦克风", isOn: $recorder.recordMicrophone)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .disabled(recorder.state == .recording)
                }.padding(6)
            }

            if recorder.state == .recording {
                HStack(spacing: 10) {
                    Circle().fill(.red).frame(width: 10, height: 10)
                    Text(recorder.elapsedText).font(.system(.title3, design: .monospaced))
                    Spacer()
                    Button("停止录制", role: .destructive) {
                        Task { await recorder.stop(reveal: recorder.revealAfterRecording) }
                    }.controlSize(.large)
                }
            } else if recorder.state == .countingDown {
                Text("即将开始录制：\(recorder.countdownValue)")
                    .font(.title2.bold()).foregroundStyle(.orange)
            } else {
                Button {
                    Task { await recorder.begin(mode: recorder.captureMode, countdown: recorder.countdownSeconds) }
                } label: {
                    Label(recorder.captureMode == .region ? "选择区域并录制" : "开始全屏录制",
                          systemImage: "record.circle")
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
            }

            Text(recorder.statusMessage)
                .font(.caption).foregroundStyle(recorder.hasError ? .red : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if recorder.permissionDenied {
                Button("重新请求权限并打开系统设置") { recorder.retryScreenPermission() }
                    .buttonStyle(.link)
            }
            Button("打开诊断日志") { recorder.openDiagnosticLog() }
                .buttonStyle(.link)
        }
        .padding(26)
        .onAppear { recorder.requestPermissionIfNeeded(); recorder.configureShortcut() }
    }
}

enum CaptureMode { case region, fullScreen }
enum HotKeyChoice: String, CaseIterable {
    case commandSpace, commandShift2, commandOptionR, controlOptionR
    var title: String {
        switch self {
        case .commandSpace: return "⌘ Space"
        case .commandShift2: return "⌘ ⇧ 2"
        case .commandOptionR: return "⌘ ⌥ R"
        case .controlOptionR: return "⌃ ⌥ R"
        }
    }
    var keyCode: UInt32 {
        switch self {
        case .commandSpace: return UInt32(kVK_Space)
        case .commandShift2: return UInt32(kVK_ANSI_2)
        case .commandOptionR, .controlOptionR: return UInt32(kVK_ANSI_R)
        }
    }
    var modifiers: UInt32 {
        switch self {
        case .commandSpace: return UInt32(cmdKey)
        case .commandShift2: return UInt32(cmdKey | shiftKey)
        case .commandOptionR: return UInt32(cmdKey | optionKey)
        case .controlOptionR: return UInt32(controlKey | optionKey)
        }
    }
}
enum RecorderState { case idle, countingDown, recording, finishing }

private func globalHotKeyHandler(_ nextHandler: EventHandlerCallRef?, _ event: EventRef?,
                                 _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.fire()
    return noErr
}

final class GlobalHotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                  eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), globalHotKeyHandler, 1, &event,
                            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    func register(_ choice: HotKeyChoice) -> OSStatus {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef); self.hotKeyRef = nil }
        let id = EventHotKeyID(signature: OSType(0x53464C54), id: 1) // "SFLT"
        return RegisterEventHotKey(choice.keyCode, choice.modifiers, id,
                                   GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    fileprivate func fire() { DispatchQueue.main.async { [action] in action() } }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

enum RecordingQuality: CaseIterable {
    case standard, high, ultra
    var title: String {
        switch self { case .standard: return "标准（省空间）"; case .high: return "高清（原生）"; case .ultra: return "超清 ProRes" }
    }
    func outputScale(nativeScale: CGFloat) -> CGFloat {
        switch self {
        case .standard: return nativeScale > 1 ? 1 : 0.75
        case .high, .ultra: return nativeScale
        }
    }
    var maximumBitrate: Int {
        switch self { case .standard: return 10_000_000; case .high: return 24_000_000; case .ultra: return 48_000_000 }
    }
    var bitsPerPixel: Int {
        switch self { case .standard: return 5; case .high: return 8; case .ultra: return 14 }
    }
}

@MainActor
final class ScreenRecorder: NSObject, ObservableObject {
    @Published var state: RecorderState = .idle
    @Published var countdownValue = 0
    @Published var elapsedText = "00:00"
    @Published var statusMessage = "准备就绪"
    @Published var hasError = false
    @Published var permissionDenied = false
    @Published var revealAfterRecording = true
    @Published var recordSystemAudio = true
    @Published var recordMicrophone = false
    @Published var quality: RecordingQuality = .high
    @Published var captureMode: CaptureMode = .region
    @Published var countdownSeconds = 3
    @Published var hotKeyChoice: HotKeyChoice = HotKeyChoice(
        rawValue: UserDefaults.standard.string(forKey: "hotKeyChoice") ?? ""
    ) ?? .commandSpace
    @Published var outputDirectory = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]

    private var stream: SCStream?
    nonisolated(unsafe) private var captureWriter: CaptureWriter?
    private var microphoneCapture: MicrophoneCapture?
    private var timer: Timer?
    private var startDate: Date?
    private var recordingBorder: RecordingBorder?
    private var recordingControls: RecordingControlPanel?
    private let sampleQueue = DispatchQueue(label: "screenflowlite.samples")
    private lazy var hotKeyManager = GlobalHotKeyManager { [weak self] in
        guard let self else { return }
        Task { @MainActor in
            guard self.state == .idle else { return }
            await self.begin(mode: self.captureMode, countdown: self.countdownSeconds)
        }
    }

    func configureShortcut() {
        UserDefaults.standard.set(hotKeyChoice.rawValue, forKey: "hotKeyChoice")
        let result = hotKeyManager.register(hotKeyChoice)
        if result != noErr {
            statusMessage = "快捷键 \(hotKeyChoice.title) 已被系统占用，请选择其他组合"
            hasError = true
        } else if statusMessage.contains("快捷键") || statusMessage == "准备就绪" {
            statusMessage = "快捷键已启用：\(hotKeyChoice.title)"
            hasError = false
        }
    }

    func requestPermissionIfNeeded() {
        if CGPreflightScreenCaptureAccess() {
            permissionDenied = false
            return
        }
        let granted = CGRequestScreenCaptureAccess()
        if granted {
            permissionDenied = false
            statusMessage = "授权成功，请退出并重新打开轻录屏后再开始录制"
        } else {
            permissionDenied = true
            fail("macOS 尚未授予屏幕录制权限。请打开系统设置并启用“轻录屏”。")
            // 部分临时签名应用仅调用 CGRequest 不会出现在 TCC 列表中；
            // 实际访问一次 ScreenCaptureKit 可促使系统完成应用登记。
            Task {
                _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            }
        }
    }

    func retryScreenPermission() {
        if CGPreflightScreenCaptureAccess() {
            permissionDenied = false
            statusMessage = "屏幕录制权限已生效"
            hasError = false
            return
        }
        _ = CGRequestScreenCaptureAccess()
        Task {
            _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            await MainActor.run { self.openPermissionSettings() }
        }
    }

    func openPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func openDiagnosticLog() {
        NSWorkspace.shared.activateFileViewerSelecting([DiagnosticLogger.shared.url])
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { outputDirectory = url }
    }

    func begin(mode: CaptureMode, countdown: Int) async {
        hasError = false
        guard CGPreflightScreenCaptureAccess() else {
            permissionDenied = true
            fail("屏幕录制权限尚未生效。请在系统设置中允许“轻录屏”，然后完全退出并重新打开应用。")
            openPermissionSettings()
            return
        }
        permissionDenied = false
        if recordMicrophone {
            let microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
            guard microphoneGranted else {
                fail("需要麦克风权限。请在系统设置 → 隐私与安全性 → 麦克风中允许“轻录屏”。")
                return
            }
        }
        do {
            let rect: CGRect?
            if mode == .region {
                statusMessage = "拖动鼠标框选录制区域，按 Esc 取消"
                guard let selected = await RegionSelector.select() else {
                    statusMessage = "已取消选择"; return
                }
                rect = selected
            } else { rect = nil }

            if countdown > 0 {
                state = .countingDown
                let countdownFrame = rect ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })?.frame
                    ?? NSScreen.main?.frame ?? .zero
                let overlay = CountdownOverlay(frame: countdownFrame)
                for value in stride(from: countdown, through: 1, by: -1) {
                    countdownValue = value
                    overlay.show(value: value)
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
                overlay.close()
            }
            try await startCapture(sourceRect: rect)
        } catch { fail("启动录制失败：\(Self.detailedError(error))") }
    }

    private func startCapture(sourceRect: CGRect?) async throws {
        let diagnostics = DiagnosticLogger.shared
        diagnostics.beginSession()
        diagnostics.log("quality=\(quality.title), mode=\(sourceRect == nil ? "fullscreen" : "region"), sourceRect(AppKit)=\(String(describing: sourceRect))")
        let indicatorFrame = sourceRect ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })?.frame
            ?? NSScreen.main?.frame
        if let indicatorFrame {
            recordingBorder = RecordingBorder(frame: indicatorFrame)
            recordingBorder?.show()
        }
        recordingControls = RecordingControlPanel(owner: self, near: sourceRect)
        recordingControls?.show()
        // 给 WindowServer 一个刷新周期，确保边角提示和控制条可以从采集内容中排除。
        try? await Task.sleep(nanoseconds: 120_000_000)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard !content.displays.isEmpty else { throw RecorderError.noDisplay }
        // 先在 AppKit 坐标系中确定用户真正选择的屏幕，再通过 displayID 映射到 ScreenCaptureKit。
        // 不能直接用 SCDisplay.frame 与 AppKit 选区求交：两套多屏坐标系的 Y 轴方向不同。
        let selectedScreen: NSScreen
        if let rect = sourceRect {
            selectedScreen = NSScreen.screens.max {
                $0.frame.intersection(rect).area < $1.frame.intersection(rect).area
            } ?? NSScreen.main ?? NSScreen.screens[0]
        } else {
            selectedScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main ?? NSScreen.screens[0]
        }
        let selectedDisplayID = (selectedScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        let display = content.displays.first(where: { $0.displayID == selectedDisplayID }) ?? content.displays[0]
        diagnostics.log("NSScreen id=\(String(describing: selectedDisplayID)), frame=\(selectedScreen.frame), backingScale=\(selectedScreen.backingScaleFactor)")
        diagnostics.log("SCDisplay id=\(display.displayID), width=\(display.width), height=\(display.height), frame=\(display.frame)")
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let appWindows = content.windows.filter { $0.owningApplication?.processID == ownPID }
        let filter = SCContentFilter(display: display, excludingWindows: appWindows)
        diagnostics.log("filter contentRect=\(filter.contentRect), pointPixelScale=\(filter.pointPixelScale), excludedOwnWindows=\(appWindows.count)")
        let config = SCStreamConfiguration()
        config.capturesAudio = recordSystemAudio
        if recordSystemAudio {
            config.sampleRate = 48_000
            config.channelCount = 2
            config.excludesCurrentProcessAudio = true
        }
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 6
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.scalesToFit = false

        // 使用 ScreenCaptureKit 针对当前内容计算的真实点到像素倍率。
        let nativeScale = max(1, max(CGFloat(filter.pointPixelScale), selectedScreen.backingScaleFactor))
        let outputScale = quality.outputScale(nativeScale: nativeScale)
        var physicalCropRect: CGRect?
        let outputWidth: Int
        let outputHeight: Int
        if let rect = sourceRect {
            let clipped = rect.intersection(selectedScreen.frame)
            guard clipped.width >= 20, clipped.height >= 20 else { throw RecorderError.invalidRegion }
            // AppKit 以左下角为原点，ScreenCaptureKit 的 sourceRect 以显示器左上角为原点。
            let local = CGRect(x: clipped.minX - selectedScreen.frame.minX,
                               y: selectedScreen.frame.maxY - clipped.maxY,
                               width: clipped.width, height: clipped.height)
            // 始终采集完整显示器的原生像素，再在写入器中精确裁剪。
            // 避免 ScreenCaptureKit 对 sourceRect 做内部缩放，导致文字在编码前已经变糊。
            physicalCropRect = CGRect(x: local.minX * nativeScale,
                                      y: local.minY * nativeScale,
                                      width: local.width * nativeScale,
                                      height: local.height * nativeScale)
            config.sourceRect = CGRect(origin: .zero, size: selectedScreen.frame.size)
            config.width = max(2, Int(selectedScreen.frame.width * nativeScale) / 2 * 2)
            config.height = max(2, Int(selectedScreen.frame.height * nativeScale) / 2 * 2)
            outputWidth = max(2, Int(local.width * outputScale) / 2 * 2)
            outputHeight = max(2, Int(local.height * outputScale) / 2 * 2)
            diagnostics.log("localRect(points)=\(local), physicalCropRect=\(String(describing: physicalCropRect)), fullCapture=\(config.width)x\(config.height), output=\(outputWidth)x\(outputHeight)")
        } else {
            config.width = max(2, Int(selectedScreen.frame.width * outputScale) / 2 * 2)
            config.height = max(2, Int(selectedScreen.frame.height * outputScale) / 2 * 2)
            outputWidth = config.width; outputHeight = config.height
            diagnostics.log("fullscreen capture/output=\(outputWidth)x\(outputHeight)")
        }
        diagnostics.log("config pixelFormat=BGRA, scalesToFit=\(config.scalesToFit), queueDepth=\(config.queueDepth), minFrameInterval=\(config.minimumFrameInterval.seconds), nativeScale=\(nativeScale), outputScale=\(outputScale)")

        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let fileExtension = quality == .ultra ? "mov" : "mp4"
        let url = outputDirectory.appendingPathComponent("录屏_\(formatter.string(from: Date())).\(fileExtension)")
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any]
        let fileType: AVFileType
        if quality == .ultra {
            // ProRes 422 HQ 保留屏幕文字和彩色细线的边缘，避免 H.264 4:2:0 色度模糊。
            settings = [
                AVVideoCodecKey: AVVideoCodecType.proRes422HQ,
                AVVideoWidthKey: outputWidth,
                AVVideoHeightKey: outputHeight
            ]
            fileType = .mov
        } else {
            settings = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: outputWidth,
                AVVideoHeightKey: outputHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: min(quality.maximumBitrate,
                                                  outputWidth * outputHeight * quality.bitsPerPixel),
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoMaxKeyFrameIntervalKey: 60,
                    AVVideoAllowFrameReorderingKey: false
                ]
            ]
            fileType = .mp4
        }
        let newWriter = try CaptureWriter(url: url, videoSettings: settings,
                                          fileType: fileType,
                                          targetWidth: outputWidth, targetHeight: outputHeight,
                                          physicalCropRect: physicalCropRect,
                                          sharpenUpscale: quality != .standard,
                                          includeSystemAudio: recordSystemAudio,
                                          includeMicrophone: recordMicrophone)
        captureWriter = newWriter
        diagnostics.log("writer codec=\(quality == .ultra ? "ProRes422HQ" : "H264"), file=\(url.path)")
        if recordMicrophone {
            let microphone = try MicrophoneCapture(writer: newWriter)
            microphoneCapture = microphone
            microphone.start()
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        if recordSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        }
        self.stream = stream
        try await stream.startCapture()
        diagnostics.log("SCStream.startCapture succeeded")
        state = .recording
        statusMessage = "正在录制：\(url.lastPathComponent) · \(outputWidth) × \(outputHeight) · \(String(format: "%.1f", nativeScale))× 原生裁剪"
        startDate = Date(); elapsedText = "00:00"
        timer = Timer.scheduledTimer(timeInterval: 1, target: self,
                                     selector: #selector(timerTick), userInfo: nil, repeats: true)
    }

    func stop(reveal: Bool) async {
        guard state == .recording else { return }
        state = .finishing; timer?.invalidate(); timer = nil
        recordingBorder?.close(); recordingBorder = nil
        recordingControls?.close(); recordingControls = nil
        microphoneCapture?.stop(); microphoneCapture = nil
        do { try await stream?.stopCapture() } catch {}
        stream = nil
        let result = await captureWriter?.finish()
        let url = result?.url
        captureWriter = nil
        state = .idle; elapsedText = "00:00"
        if let result, result.succeeded,
           FileManager.default.fileExists(atPath: result.url.path),
           (try? FileManager.default.attributesOfItem(atPath: result.url.path)[.size] as? NSNumber)?.intValue ?? 0 > 0 {
            statusMessage = "录制完成：\(result.url.lastPathComponent)"
            DiagnosticLogger.shared.log("finish succeeded, frames=\(result.frameCount), sourceFrame=\(result.sourceWidth)x\(result.sourceHeight), fileBytes=\((try? FileManager.default.attributesOfItem(atPath: result.url.path)[.size]) ?? "?")")
            if reveal { revealInFinder(result.url) }
        } else {
            DiagnosticLogger.shared.log("finish failed: \(result?.errorMessage ?? "unknown")")
            if let url { try? FileManager.default.removeItem(at: url) }
            fail(result?.errorMessage ?? "录制失败：没有收到有效的视频帧")
        }
    }

    private func updateElapsed() {
        let seconds = Int(Date().timeIntervalSince(startDate ?? Date()))
        elapsedText = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        recordingControls?.update(time: elapsedText)
    }

    private func revealInFinder(_ url: URL) {
        // 先让文件系统完成最终落盘，再激活访达并选中文件。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if !NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path) {
                    NSWorkspace.shared.open(url.deletingLastPathComponent())
                }
            }
        }
    }

    @objc private func timerTick() { updateElapsed() }

    private func fail(_ message: String) {
        recordingBorder?.close(); recordingBorder = nil
        recordingControls?.close(); recordingControls = nil
        microphoneCapture?.stop(); microphoneCapture = nil
        hasError = true; statusMessage = message; state = .idle
    }

    private static func detailedError(_ error: Error) -> String {
        let ns = error as NSError
        var text = ns.localizedDescription
        if text == "The operation could not be completed." || text == "操作无法完成。" {
            text = ns.localizedFailureReason ?? ns.localizedRecoverySuggestion ?? String(describing: error)
        }
        return "\(text) [\(ns.domain) \(ns.code)]"
    }

    @objc fileprivate func stopFromFloatingControls() {
        Task { await stop(reveal: revealAfterRecording) }
    }
}

extension ScreenRecorder: SCStreamOutput, SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in self.fail("录制中断：\(error.localizedDescription)") }
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        if type == .screen { captureWriter?.appendVideo(sampleBuffer) }
        else if type == .audio { captureWriter?.appendAudio(sampleBuffer) }
    }
}

final class CaptureWriter: @unchecked Sendable {
    struct Result {
        let url: URL; let succeeded: Bool; let errorMessage: String?
        let frameCount: Int; let sourceWidth: Int; let sourceHeight: Int
    }
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let pixelAdaptor: AVAssetWriterInputPixelBufferAdaptor
    private let systemAudioInput: AVAssetWriterInput?
    private let microphoneInput: AVAssetWriterInput?
    private let targetWidth: Int
    private let targetHeight: Int
    private let physicalCropRect: CGRect?
    private let sharpenUpscale: Bool
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let url: URL
    private var started = false
    private var frameCount = 0
    private var sourceWidth = 0
    private var sourceHeight = 0

    init(url: URL, videoSettings: [String: Any], fileType: AVFileType,
         targetWidth: Int, targetHeight: Int, physicalCropRect: CGRect?, sharpenUpscale: Bool,
         includeSystemAudio: Bool, includeMicrophone: Bool) throws {
        self.url = url
        self.targetWidth = targetWidth; self.targetHeight = targetHeight
        self.physicalCropRect = physicalCropRect
        self.sharpenUpscale = sharpenUpscale
        writer = try AVAssetWriter(url: url, fileType: fileType)
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput) else { throw RecorderError.writerSetup }
        writer.add(videoInput)
        pixelAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: targetWidth,
                kCVPixelBufferHeightKey as String: targetHeight,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ])
        let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000
        ]
        if includeSystemAudio {
            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audio.expectsMediaDataInRealTime = true
            guard writer.canAdd(audio) else { throw RecorderError.writerSetup }
            writer.add(audio); systemAudioInput = audio
        } else { systemAudioInput = nil }
        if includeMicrophone {
            let microphone = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            microphone.expectsMediaDataInRealTime = true
            guard writer.canAdd(microphone) else { throw RecorderError.writerSetup }
            writer.add(microphone); microphoneInput = microphone
        } else { microphoneInput = nil }
    }

    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete else { return }
        guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }
        if !started {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            started = true
        }
        guard writer.status == .writing, videoInput.isReadyForMoreMediaData,
              let source = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let sourceWidth = CVPixelBufferGetWidth(source), sourceHeight = CVPixelBufferGetHeight(source)
        if frameCount == 0 { self.sourceWidth = sourceWidth; self.sourceHeight = sourceHeight }
        if frameCount < 3 {
            DiagnosticLogger.shared.log("frame#\(frameCount + 1) sourceBuffer=\(sourceWidth)x\(sourceHeight), target=\(targetWidth)x\(targetHeight), crop=\(String(describing: physicalCropRect)), attachments=\(String(describing: attachments.first))")
        }
        if physicalCropRect == nil, sourceWidth == targetWidth, sourceHeight == targetHeight {
            if videoInput.append(sampleBuffer) { frameCount += 1 }
            else { DiagnosticLogger.shared.log("direct append failed: \(String(describing: writer.error))") }
            return
        }
        guard let pool = pixelAdaptor.pixelBufferPool else { return }
        var destination: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &destination) == kCVReturnSuccess,
              let destination else { return }
        var image = CIImage(cvPixelBuffer: source)
        var workingWidth = CGFloat(sourceWidth), workingHeight = CGFloat(sourceHeight)
        if let crop = physicalCropRect {
            // ScreenCaptureKit 使用左上原点，Core Image 使用左下原点。
            let ciCrop = CGRect(x: crop.minX,
                                y: CGFloat(sourceHeight) - crop.maxY,
                                width: crop.width, height: crop.height).integral
                .intersection(CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight))
            guard !ciCrop.isEmpty else { return }
            image = image.cropped(to: ciCrop)
                .transformed(by: CGAffineTransform(translationX: -ciCrop.minX, y: -ciCrop.minY))
            workingWidth = ciCrop.width; workingHeight = ciCrop.height
            if frameCount < 3 { DiagnosticLogger.shared.log("CI crop=\(ciCrop), working=\(workingWidth)x\(workingHeight)") }
        }
        let scaleX = CGFloat(targetWidth) / workingWidth
        let scaleY = CGFloat(targetHeight) / workingHeight
        let isOneToOne = abs(scaleX - 1) < 0.01 && abs(scaleY - 1) < 0.01
        if !isOneToOne {
            // Lanczos 比普通仿射缩放更适合屏幕文字；宽高比微小差异通过 aspectRatio 处理。
            image = image.applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scaleX,
                kCIInputAspectRatioKey: scaleY / scaleX
            ])
            // 仅在确实放大时做非常轻的补偿，避免文字产生黑白描边和光晕。
            if sharpenUpscale && scaleX > 1.01 {
                image = image.applyingFilter("CISharpenLuminance", parameters: ["inputSharpness": 0.12])
            }
        }
        ciContext.render(image, to: destination,
                         bounds: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight),
                         colorSpace: CGColorSpaceCreateDeviceRGB())
        if pixelAdaptor.append(destination, withPresentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) {
            frameCount += 1
        } else { DiagnosticLogger.shared.log("pixel adaptor append failed: \(String(describing: writer.error))") }
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard started, writer.status == .writing,
              let systemAudioInput, systemAudioInput.isReadyForMoreMediaData,
              CMSampleBufferDataIsReady(sampleBuffer) else { return }
        _ = systemAudioInput.append(sampleBuffer)
    }

    func appendMicrophone(_ sampleBuffer: CMSampleBuffer) {
        guard started, writer.status == .writing,
              let microphoneInput, microphoneInput.isReadyForMoreMediaData,
              CMSampleBufferDataIsReady(sampleBuffer) else { return }
        _ = microphoneInput.append(sampleBuffer)
    }

    func finish() async -> Result {
        guard started, frameCount > 0 else {
            writer.cancelWriting()
            let error = writer.error as NSError?
            let detail = error.map { "\($0.localizedDescription) [\($0.domain) \($0.code)]" }
            return Result(url: url, succeeded: false,
                          errorMessage: detail ?? "录制失败：ScreenCaptureKit 未返回完整画面，请确认屏幕录制权限已生效",
                          frameCount: frameCount, sourceWidth: sourceWidth, sourceHeight: sourceHeight)
        }
        videoInput.markAsFinished()
        systemAudioInput?.markAsFinished()
        microphoneInput?.markAsFinished()
        await writer.finishWriting()
        let ok = writer.status == .completed
        let error = writer.error as NSError?
        return Result(url: url, succeeded: ok,
                      errorMessage: ok ? nil : error.map { "视频编码失败：\($0.localizedDescription) [\($0.domain) \($0.code)]" } ?? "视频编码结束失败",
                      frameCount: frameCount, sourceWidth: sourceWidth, sourceHeight: sourceHeight)
    }
}

final class MicrophoneCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let writer: CaptureWriter
    private let queue = DispatchQueue(label: "screenflowlite.microphone")

    init(writer: CaptureWriter) throws {
        self.writer = writer
        super.init()
        session.beginConfiguration()
        guard let device = AVCaptureDevice.default(for: .audio) else {
            session.commitConfiguration(); throw RecorderError.noMicrophone
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { session.commitConfiguration(); throw RecorderError.noMicrophone }
        session.addInput(input)
        let output = AVCaptureAudioDataOutput()
        guard session.canAddOutput(output) else { session.commitConfiguration(); throw RecorderError.writerSetup }
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: queue)
        session.commitConfiguration()
    }

    func start() { queue.async { [session] in session.startRunning() } }
    func stop() { if session.isRunning { session.stopRunning() } }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        writer.appendMicrophone(sampleBuffer)
    }
}

enum RecorderError: LocalizedError {
    case noDisplay, writerSetup, invalidRegion, noMicrophone
    var errorDescription: String? {
        switch self {
        case .noDisplay: return "没有找到可录制的显示器"
        case .writerSetup: return "视频编码器初始化失败"
        case .invalidRegion: return "所选区域无效，请在同一块屏幕内重新选择"
        case .noMicrophone: return "没有找到可用的麦克风设备"
        }
    }
}

@MainActor
final class RegionSelector: NSObject, NSWindowDelegate {
    private static var activeSelector: RegionSelector?
    private var window: NSWindow?
    private var continuation: CheckedContinuation<CGRect?, Never>?

    static func select() async -> CGRect? {
        await withCheckedContinuation { continuation in
            let selector = RegionSelector()
            activeSelector = selector
            selector.continuation = continuation
            selector.present()
        }
    }

    private func present() {
        guard let screen = NSScreen.main else { finish(nil); return }
        let visible = screen.visibleFrame
        // 默认覆盖屏幕的大部分区域，避免固定 960×640 选框天然产生低分辨率视频。
        let width = visible.width * 0.82
        let height = visible.height * 0.78
        let initialFrame = CGRect(x: visible.midX - width / 2, y: visible.midY - height / 2,
                                  width: width, height: height)
        let view = RegionPanelContent(frame: CGRect(origin: .zero, size: initialFrame.size))
        view.owner = self
        let window = SelectionWindow(contentRect: initialFrame,
                                     styleMask: [.titled, .resizable, .closable, .fullSizeContentView],
                                     backing: .buffered, defer: false)
        window.title = "红框内为录制区域"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = NSColor.systemRed.withAlphaComponent(0.10)
        window.minSize = NSSize(width: 320, height: 220)
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        window.contentView = view
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    fileprivate func confirm(_ local: CGRect) {
        guard local.width >= 20, local.height >= 20, let window else { finish(nil); return }
        let screenRect = window.convertToScreen(local)
        finish(screenRect)
    }
    fileprivate func cancel() { finish(nil) }
    @objc fileprivate func confirmCurrentWindow() {
        guard let window else { finish(nil); return }
        finish(window.frame)
    }
    func windowWillClose(_ notification: Notification) { if continuation != nil { finish(nil) } }
    private func finish(_ rect: CGRect?) {
        window?.orderOut(nil); window = nil
        continuation?.resume(returning: rect); continuation = nil
        RegionSelector.activeSelector = nil
    }
}

final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class RegionPanelContent: NSView {
    weak var owner: RegionSelector?
    private let confirmButton = NSButton(title: "开始录制此区域", target: nil, action: nil)

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.borderColor = NSColor.systemRed.cgColor
        layer?.borderWidth = 4
        layer?.cornerRadius = 6

        confirmButton.bezelStyle = .rounded
        confirmButton.controlSize = .large
        confirmButton.font = .systemFont(ofSize: 16, weight: .bold)
        confirmButton.contentTintColor = .systemRed
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(confirmButton)
        NSLayoutConstraint.activate([
            confirmButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            confirmButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -28),
            confirmButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 190),
            confirmButton.heightAnchor.constraint(equalToConstant: 42)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self)
        confirmButton.target = owner
        confirmButton.action = #selector(RegionSelector.confirmCurrentWindow)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let title = "录制区域"
        let tip = "拖动红框内部移动 · 拖动窗口边缘调整大小"
        title.draw(at: CGPoint(x: 28, y: bounds.maxY - 74), withAttributes: [
            .font: NSFont.systemFont(ofSize: 28, weight: .bold), .foregroundColor: NSColor.systemRed
        ])
        tip.draw(at: CGPoint(x: 30, y: bounds.maxY - 102), withAttributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.labelColor
        ])
        let size = "\(Int(window?.frame.width ?? bounds.width)) × \(Int(window?.frame.height ?? bounds.height))"
        size.draw(at: CGPoint(x: 30, y: 30), withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.systemRed
        ])
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { owner?.cancel() }
        else if event.keyCode == 36 || event.keyCode == 76 { owner?.confirmCurrentWindow() }
        else { super.keyDown(with: event) }
    }
}

private extension CGRect {
    var area: CGFloat { isNull || isEmpty ? 0 : width * height }
}

@MainActor
final class CountdownOverlay {
    private let window: NSWindow
    private let circle = CountdownCircleView(frame: CGRect(x: 0, y: 0, width: 150, height: 150))

    init(frame: CGRect) {
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let content = NSView(frame: CGRect(origin: .zero, size: frame.size))
        let circleSize: CGFloat = 150
        circle.frame.origin = CGPoint(x: (frame.width - circleSize) / 2,
                                      y: (frame.height - circleSize) / 2)
        content.addSubview(circle); window.contentView = content
    }

    func show(value: Int) {
        circle.value = value
        circle.needsDisplay = true
        window.orderFrontRegardless()
    }
    func close() { window.orderOut(nil) }
}

final class CountdownCircleView: NSView {
    var value = 3
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 3, dy: 3))
        NSColor.black.withAlphaComponent(0.72).setFill(); circle.fill()
        NSColor.systemRed.setStroke(); circle.lineWidth = 5; circle.stroke()

        let text = String(value) as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 82, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        // AppKit 文本基线并非几何中心，向上微调字体下行空间。
        let origin = CGPoint(x: bounds.midX - textSize.width / 2,
                             y: bounds.midY - textSize.height / 2 + 7)
        text.draw(at: origin, withAttributes: attributes)
    }
}

@MainActor
final class RecordingBorder {
    private let window: NSWindow

    init(frame: CGRect) {
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.title = "ScreenFlowLite Recording Border"
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = RecordingBorderView(frame: CGRect(origin: .zero, size: frame.size))
    }

    func show() { window.orderFrontRegardless() }
    func close() { window.orderOut(nil) }
}

final class RecordingBorderView: NSView {
    override func viewDidMoveToWindow() {
        wantsLayer = true
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.18
        pulse.duration = 0.75
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(pulse, forKey: "recordingCornerPulse")
    }

    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); bounds.fill()
        NSColor.systemRed.setStroke()
        let inset: CGFloat = 7
        let length = min(48, max(26, min(bounds.width, bounds.height) * 0.075))
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let corners = NSBezierPath()
        // 左下
        corners.move(to: CGPoint(x: rect.minX, y: rect.minY + length)); corners.line(to: CGPoint(x: rect.minX, y: rect.minY))
        corners.line(to: CGPoint(x: rect.minX + length, y: rect.minY))
        // 右下
        corners.move(to: CGPoint(x: rect.maxX - length, y: rect.minY)); corners.line(to: CGPoint(x: rect.maxX, y: rect.minY))
        corners.line(to: CGPoint(x: rect.maxX, y: rect.minY + length))
        // 左上
        corners.move(to: CGPoint(x: rect.minX, y: rect.maxY - length)); corners.line(to: CGPoint(x: rect.minX, y: rect.maxY))
        corners.line(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        // 右上
        corners.move(to: CGPoint(x: rect.maxX - length, y: rect.maxY)); corners.line(to: CGPoint(x: rect.maxX, y: rect.maxY))
        corners.line(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        corners.lineWidth = 4
        corners.lineCapStyle = .round
        corners.lineJoinStyle = .round
        corners.stroke()
    }
}

@MainActor
final class RecordingControlPanel {
    private let window: NSPanel
    private let timeLabel = NSTextField(labelWithString: "00:00")

    init(owner: ScreenRecorder, near region: CGRect?) {
        let size = NSSize(width: 286, height: 64)
        let screenFrame = (region.flatMap { rect in
            NSScreen.screens.first(where: { $0.frame.intersects(rect) })?.visibleFrame
        }) ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let x: CGFloat
        let y: CGFloat
        if let region {
            x = min(max(screenFrame.minX + 12, region.midX - size.width / 2), screenFrame.maxX - size.width - 12)
            y = min(region.maxY + 12, screenFrame.maxY - size.height - 12)
        } else {
            x = screenFrame.maxX - size.width - 24
            y = screenFrame.maxY - size.height - 24
        }
        window = NSPanel(contentRect: CGRect(origin: CGPoint(x: x, y: y), size: size),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "ScreenFlowLite Recording Controls"
        window.level = .screenSaver
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.isOpaque = false
        window.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96)
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let content = NSView(frame: CGRect(origin: .zero, size: size))
        content.wantsLayer = true
        content.layer?.cornerRadius = 14
        content.layer?.borderWidth = 2
        content.layer?.borderColor = NSColor.systemRed.cgColor

        let dot = NSTextField(labelWithString: "●")
        dot.textColor = .systemRed; dot.font = .systemFont(ofSize: 18, weight: .bold)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        timeLabel.alignment = .center
        let stopButton = NSButton(title: "停止录制", target: owner,
                                  action: #selector(ScreenRecorder.stopFromFloatingControls))
        stopButton.bezelStyle = .rounded; stopButton.controlSize = .large
        stopButton.contentTintColor = .systemRed

        [dot, timeLabel, stopButton].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; content.addSubview($0) }
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            dot.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            timeLabel.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            timeLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            timeLabel.widthAnchor.constraint(equalToConstant: 72),
            stopButton.leadingAnchor.constraint(equalTo: timeLabel.trailingAnchor, constant: 14),
            stopButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            stopButton.centerYAnchor.constraint(equalTo: content.centerYAnchor)
        ])
        window.contentView = content
    }

    func show() { window.orderFrontRegardless() }
    func update(time: String) { timeLabel.stringValue = time }
    func close() { window.orderOut(nil) }
}

final class SelectionView: NSView {
    weak var owner: RegionSelector?
    private var selection = CGRect.zero
    private var dragMode: DragMode = .none
    private var dragStart = CGPoint.zero
    private var originalSelection = CGRect.zero
    private let handleSize: CGFloat = 12

    private enum DragMode { case none, move, topLeft, topRight, bottomLeft, bottomRight, left, right, top, bottom }

    override var acceptsFirstResponder: Bool { true }
    override func makeBackingLayer() -> CALayer { CALayer() }
    override func viewDidMoveToWindow() {
        wantsLayer = true
        window?.makeFirstResponder(self)
        let screen = NSScreen.main?.frame ?? bounds
        let localScreen = window?.convertFromScreen(screen) ?? bounds
        let width = max(320, localScreen.width * 0.62)
        let height = max(220, localScreen.height * 0.62)
        selection = CGRect(x: localScreen.midX - width / 2, y: localScreen.midY - height / 2,
                           width: width, height: height).intersection(bounds.insetBy(dx: 24, dy: 24))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.42).setFill(); bounds.fill()
        NSColor.clear.setFill(); selection.fill(using: .copy)
        NSColor.systemRed.setStroke()
        let border = NSBezierPath(rect: selection); border.lineWidth = 3; border.stroke()

        for point in handlePoints {
            let rect = CGRect(x: point.x - handleSize / 2, y: point.y - handleSize / 2,
                              width: handleSize, height: handleSize)
            NSColor.white.setFill(); NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            NSColor.systemRed.setStroke(); NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).stroke()
        }

        let message = "拖动内部移动 · 拖动边框或控制点缩放 · 回车/双击确认 · Esc 取消"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.72)
        ]
        let size = message.size(withAttributes: attrs)
        message.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.maxY - 48), withAttributes: attrs)

        let dimensions = "\(Int(selection.width)) × \(Int(selection.height))"
        dimensions.draw(at: CGPoint(x: selection.minX + 8, y: selection.minY + 8),
                        withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
                                         .foregroundColor: NSColor.white,
                                         .backgroundColor: NSColor.black.withAlphaComponent(0.65)])
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2, selection.contains(point) { owner?.confirm(selection); return }
        dragMode = hitTestMode(at: point); dragStart = point; originalSelection = selection
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let dx = point.x - dragStart.x, dy = point.y - dragStart.y
        var rect = originalSelection
        switch dragMode {
        case .move: rect.origin.x += dx; rect.origin.y += dy
        case .left: rect.origin.x += dx; rect.size.width -= dx
        case .right: rect.size.width += dx
        case .top: rect.size.height += dy
        case .bottom: rect.origin.y += dy; rect.size.height -= dy
        case .topLeft: rect.origin.x += dx; rect.size.width -= dx; rect.size.height += dy
        case .topRight: rect.size.width += dx; rect.size.height += dy
        case .bottomLeft: rect.origin.x += dx; rect.size.width -= dx; rect.origin.y += dy; rect.size.height -= dy
        case .bottomRight: rect.size.width += dx; rect.origin.y += dy; rect.size.height -= dy
        case .none: return
        }
        if rect.width >= 80, rect.height >= 80 { selection = constrained(rect); needsDisplay = true }
    }

    override func mouseUp(with event: NSEvent) { dragMode = .none }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { owner?.cancel() }
        else if event.keyCode == 36 || event.keyCode == 76 { owner?.confirm(selection) }
        else { super.keyDown(with: event) }
    }

    private var handlePoints: [CGPoint] {
        [CGPoint(x: selection.minX, y: selection.minY), CGPoint(x: selection.midX, y: selection.minY),
         CGPoint(x: selection.maxX, y: selection.minY), CGPoint(x: selection.minX, y: selection.midY),
         CGPoint(x: selection.maxX, y: selection.midY), CGPoint(x: selection.minX, y: selection.maxY),
         CGPoint(x: selection.midX, y: selection.maxY), CGPoint(x: selection.maxX, y: selection.maxY)]
    }

    private func hitTestMode(at p: CGPoint) -> DragMode {
        let tolerance: CGFloat = 16
        let left = abs(p.x - selection.minX) <= tolerance, right = abs(p.x - selection.maxX) <= tolerance
        let bottom = abs(p.y - selection.minY) <= tolerance, top = abs(p.y - selection.maxY) <= tolerance
        if left && bottom { return .bottomLeft }; if right && bottom { return .bottomRight }
        if left && top { return .topLeft }; if right && top { return .topRight }
        if left && p.y >= selection.minY && p.y <= selection.maxY { return .left }
        if right && p.y >= selection.minY && p.y <= selection.maxY { return .right }
        if bottom && p.x >= selection.minX && p.x <= selection.maxX { return .bottom }
        if top && p.x >= selection.minX && p.x <= selection.maxX { return .top }
        return selection.contains(p) ? .move : .none
    }

    private func constrained(_ rect: CGRect) -> CGRect {
        var result = rect
        if result.minX < bounds.minX { result.origin.x = bounds.minX }
        if result.minY < bounds.minY { result.origin.y = bounds.minY }
        if result.maxX > bounds.maxX { result.origin.x = bounds.maxX - result.width }
        if result.maxY > bounds.maxY { result.origin.y = bounds.maxY - result.height }
        return result
    }
}
