import Foundation

enum TranslationMode: String, CaseIterable, Identifiable {
    case live
    case single
    var id: String { rawValue }
    var label: String { self == .live ? "实时翻译" : "单次翻译" }
    var explanation: String {
        self == .live
            ? "低延迟识别，适合滚动网页和移动窗口；画面变化后自动更新。"
            : "高清识别并保留更多上下文，适合静态页面；再按快捷键隐藏。"
    }
}

enum CaptureLoop {
    /// Single mode ends after the first frame, leaving the displayed translation active.
    static func run(mode: TranslationMode, interval: Duration = .milliseconds(800),
                    capture: () async throws -> Void) async throws {
        while true {
            try Task.checkCancellation()
            let start = ContinuousClock.now
            try await capture()
            try Task.checkCancellation()
            if mode == .single { return }
            let remaining = interval - (ContinuousClock.now - start)
            if remaining > .zero { try await Task.sleep(for: remaining) }
        }
    }
}
