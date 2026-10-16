import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ShotFormat {
    case jpeg // 压缩版
    case png  // 原图
}

enum ImageOutput {
    static var saveDirectory: URL {
        if let path = Settings.saveDirectoryPath { return URL(fileURLWithPath: path, isDirectory: true) }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    /// 把辅助进程写出的 PNG 存到「下载」文件夹，返回最终文件路径。
    static func save(pngAt source: URL, as format: ShotFormat, prefix: String) throws -> URL {
        let dir = saveDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = format == .png ? "png" : "jpg"
        let dest = uniqueURL(in: dir, base: "\(prefix)_" + timestamp(), ext: ext)

        switch format {
        case .png:
            try FileManager.default.copyItem(at: source, to: dest)
        case .jpeg:
            guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
                  let out = CGImageDestinationCreateWithURL(dest as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
            else { throw OutputError.encodeFailed }
            let options = [kCGImageDestinationLossyCompressionQuality: Settings.jpegQuality] as CFDictionary
            CGImageDestinationAddImageFromSource(out, src, 0, options)
            guard CGImageDestinationFinalize(out) else { throw OutputError.encodeFailed }
        }
        return dest
    }

    /// 与原脚本一致：剪贴板里放图片数据本身（PNG 或 JPEG）。
    @MainActor
    static func copyToPasteboard(_ data: Data, format: ShotFormat) {
        let type: NSPasteboard.PasteboardType = format == .png ? .png : NSPasteboard.PasteboardType(UTType.jpeg.identifier)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: type)
    }

    /// 缩小到 32×32 采样，几乎全黑则认为截到的是黑屏（如 Android 的 FLAG_SECURE 页面）。
    static func looksBlank(_ url: URL) -> Bool {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 64,
              ] as CFDictionary)
        else { return false }
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            ctx.draw(thumb, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return false }
        var brightest: UInt8 = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            brightest = max(brightest, pixels[i], pixels[i + 1], pixels[i + 2])
        }
        return brightest < 12
    }

    enum OutputError: LocalizedError {
        case encodeFailed
        var errorDescription: String? { "JPEG 压缩失败" }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }

    private static func uniqueURL(in dir: URL, base: String, ext: String) -> URL {
        var url = dir.appendingPathComponent("\(base).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base)_\(n).\(ext)")
            n += 1
        }
        return url
    }
}
