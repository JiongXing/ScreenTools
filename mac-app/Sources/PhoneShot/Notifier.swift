import AppKit
@preconcurrency import UserNotifications

/// 只在失败或需要提醒时通知。系统通知需要以 .app 形式运行（swift run 开发时退化为日志）。
@MainActor
enum Notifier {
    static func failure(_ message: String) {
        NSSound.beep()
        post(title: "截图失败", body: message)
    }

    static func warning(title: String, body: String) {
        post(title: title, body: body)
    }

    private static func post(title: String, body: String) {
        AppLog.write("\(title): \(body)")
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request)
        }
    }
}
