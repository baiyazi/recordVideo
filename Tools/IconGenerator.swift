import AppKit

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else { fatalError("No context") }
context.setAllowsAntialiasing(true)

let outer = NSBezierPath(roundedRect: NSRect(x: 62, y: 62, width: 900, height: 900), xRadius: 218, yRadius: 218)
context.saveGState()
let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
shadow.shadowBlurRadius = 42; shadow.shadowOffset = NSSize(width: 0, height: -20); shadow.set()
NSColor(red: 0.08, green: 0.07, blue: 0.23, alpha: 1).setFill(); outer.fill()
context.restoreGState()

context.saveGState(); outer.addClip()
let gradient = NSGradient(colors: [
    NSColor(red: 0.16, green: 0.10, blue: 0.42, alpha: 1),
    NSColor(red: 0.055, green: 0.075, blue: 0.20, alpha: 1)
])!
gradient.draw(in: outer.bounds, angle: -55)

// “梦”：月牙与柔和的梦境光晕。
let glow = NSBezierPath(ovalIn: NSRect(x: 178, y: 562, width: 430, height: 430))
NSColor(red: 0.44, green: 0.38, blue: 1.0, alpha: 0.12).setFill(); glow.fill()
let moon = NSBezierPath(ovalIn: NSRect(x: 220, y: 620, width: 272, height: 272))
NSColor(red: 0.91, green: 0.90, blue: 1.0, alpha: 1).setFill(); moon.fill()
let cutout = NSBezierPath(ovalIn: NSRect(x: 310, y: 676, width: 250, height: 250))
NSColor(red: 0.13, green: 0.09, blue: 0.35, alpha: 1).setFill(); cutout.fill()

// 录制符号：镜头圆环与红色录制核心。
let lensShadow = NSShadow(); lensShadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
lensShadow.shadowBlurRadius = 26; lensShadow.shadowOffset = NSSize(width: 0, height: -10); lensShadow.set()
let lens = NSBezierPath(ovalIn: NSRect(x: 280, y: 250, width: 464, height: 464))
NSColor(red: 0.96, green: 0.96, blue: 1, alpha: 0.96).setFill(); lens.fill()
NSShadow().set()
let inner = NSBezierPath(ovalIn: NSRect(x: 342, y: 312, width: 340, height: 340))
NSColor(red: 0.10, green: 0.09, blue: 0.28, alpha: 1).setFill(); inner.fill()
let record = NSBezierPath(ovalIn: NSRect(x: 414, y: 384, width: 196, height: 196))
NSColor(red: 1.0, green: 0.20, blue: 0.18, alpha: 1).setFill(); record.fill()
let highlight = NSBezierPath(ovalIn: NSRect(x: 447, y: 500, width: 66, height: 35))
NSColor.white.withAlphaComponent(0.22).setFill(); highlight.fill()

// “否”的抽象横画：同时像视频时间轴，避免直接堆叠文字。
let bar = NSBezierPath(roundedRect: NSRect(x: 334, y: 184, width: 356, height: 28), xRadius: 14, yRadius: 14)
NSColor(red: 0.58, green: 0.54, blue: 0.95, alpha: 0.75).setFill(); bar.fill()
let shortBar = NSBezierPath(roundedRect: NSRect(x: 421, y: 137, width: 182, height: 24), xRadius: 12, yRadius: 12)
NSColor(red: 0.58, green: 0.54, blue: 0.95, alpha: 0.48).setFill(); shortBar.fill()
context.restoreGState()

image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let data = rep.representation(using: .png, properties: [.compressionFactor: 1.0])!
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
