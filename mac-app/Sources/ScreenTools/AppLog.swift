import Foundation

/// 简单的文件日志：~/Library/Logs/ScreenTools/app.log（iOS 辅助进程另写 ios-helper.log）
enum AppLog {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/ScreenTools")
    private static let file = directory.appendingPathComponent("app.log")
    private static let queue = DispatchQueue(label: "screentools.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            // 超过 1MB 就从头写，避免无限增长
            if let size = try? fm.attributesOfItem(atPath: file.path)[.size] as? Int, size > 1_000_000 {
                try? fm.removeItem(at: file)
            }
            if let handle = try? FileHandle(forWritingTo: file) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: file)
            }
        }
    }
}
