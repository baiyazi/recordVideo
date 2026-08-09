import AppKit
import ScreenCaptureKit

@main struct DisplayProbe {
    static func main() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        for display in content.displays {
            print("SC", display.displayID, display.width, display.height, display.frame)
        }
        for screen in NSScreen.screens {
            print("NS", screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? "?",
                  screen.frame, "scale", screen.backingScaleFactor)
        }
    }
}
