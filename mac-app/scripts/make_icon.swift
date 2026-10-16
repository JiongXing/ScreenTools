// 生成 ScreenTools 的 App 图标（1024×1024 PNG）。
// 用法：swift scripts/make_icon.swift <输出.png>
// 再由 scripts/make_icon.sh 转成 Resources/AppIcon.icns。
import AppKit

let size = 1024.0
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

guard let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("no context") }

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
    )
}

// 1. 底板：macOS 图标网格（824 见方，圆角 185），带投影和渐变
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let platePath = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.28))
ctx.addPath(platePath)
ctx.setFillColor(color(0x3D5AFE))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(platePath)
ctx.clip()
let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
    colors: [color(0x2EC8FF), color(0x4A5BF5), color(0x7B3FF2)] as CFArray,
    locations: [0, 0.55, 1]
)!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 260, y: 924), end: CGPoint(x: 764, y: 100), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
// 顶部柔光
let gloss = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
    colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1]
)!
ctx.drawRadialGradient(gloss, startCenter: CGPoint(x: 512, y: 980), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 980), endRadius: 620, options: [])
ctx.restoreGState()

let white = color(0xFFFFFF)

// 2. 取景框四角
let frame = CGRect(x: 232, y: 232, width: 560, height: 560)
let arm = 118.0
ctx.setStrokeColor(white)
ctx.setLineWidth(40)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
for (x, y, dx, dy) in [
    (frame.minX, frame.maxY, 1.0, -1.0), (frame.maxX, frame.maxY, -1.0, -1.0),
    (frame.minX, frame.minY, 1.0, 1.0), (frame.maxX, frame.minY, -1.0, 1.0),
] {
    ctx.move(to: CGPoint(x: x, y: y + dy * arm))
    ctx.addLine(to: CGPoint(x: x, y: y))
    ctx.addLine(to: CGPoint(x: x + dx * arm, y: y))
}
ctx.strokePath()

// 3. 手机（不区分品牌的通用造型）
let phone = CGRect(x: 512 - 132, y: 512 - 232, width: 264, height: 464)
let phonePath = CGPath(roundedRect: phone, cornerWidth: 58, cornerHeight: 58, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x1A1060, 0.35))
ctx.addPath(phonePath)
ctx.setFillColor(white)
ctx.fillPath()
ctx.restoreGState()

// 屏幕
let screen = phone.insetBy(dx: 20, dy: 20)
ctx.addPath(CGPath(roundedRect: screen, cornerWidth: 40, cornerHeight: 40, transform: nil))
ctx.saveGState()
ctx.clip()
let screenGradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
    colors: [color(0x2EC8FF), color(0x5B4CF5)] as CFArray, locations: [0, 1]
)!
ctx.drawLinearGradient(screenGradient, start: CGPoint(x: screen.midX, y: screen.maxY),
                       end: CGPoint(x: screen.midX, y: screen.minY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
ctx.restoreGState()

// 屏幕中央的快门光圈
let center = CGPoint(x: screen.midX, y: screen.midY)
ctx.setStrokeColor(white)
ctx.setLineWidth(18)
ctx.addEllipse(in: CGRect(x: center.x - 62, y: center.y - 62, width: 124, height: 124))
ctx.strokePath()
ctx.setFillColor(white)
ctx.addEllipse(in: CGRect(x: center.x - 30, y: center.y - 30, width: 60, height: 60))
ctx.fillPath()

// 顶部听筒
ctx.setFillColor(color(0xFFFFFF, 0.9))
ctx.addPath(CGPath(roundedRect: CGRect(x: center.x - 34, y: screen.maxY - 34, width: 68, height: 14),
                   cornerWidth: 7, cornerHeight: 7, transform: nil))
ctx.fillPath()

// 4. 右下角「压暗」徽章：深色圆底 + 白色月牙
let badgeCenter = CGPoint(x: 722, y: 262)
let badgeR = 128.0
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: color(0x000000, 0.4))
ctx.setFillColor(color(0x141C3A))
ctx.fillEllipse(in: CGRect(x: badgeCenter.x - badgeR, y: badgeCenter.y - badgeR, width: badgeR * 2, height: badgeR * 2))
ctx.restoreGState()
ctx.setStrokeColor(white)
ctx.setLineWidth(12)
ctx.strokeEllipse(in: CGRect(x: badgeCenter.x - badgeR, y: badgeCenter.y - badgeR, width: badgeR * 2, height: badgeR * 2))
let moonR = 72.0
ctx.saveGState()
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
ctx.setFillColor(white)
ctx.fillEllipse(in: CGRect(x: badgeCenter.x - moonR, y: badgeCenter.y - moonR, width: moonR * 2, height: moonR * 2))
ctx.setBlendMode(.clear)
ctx.fillEllipse(in: CGRect(x: badgeCenter.x - moonR + 38, y: badgeCenter.y - moonR + 30, width: moonR * 1.7, height: moonR * 1.7))
ctx.endTransparencyLayer()
ctx.restoreGState()

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil)
else { fatalError("encode failed") }
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out)")
