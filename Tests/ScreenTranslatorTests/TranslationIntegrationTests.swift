import XCTest
import Translation

final class TranslationIntegrationTests: XCTestCase {
    @MainActor
    func testInstalledEnglishBatchTranslation() async throws {
        let source = Locale.Language(identifier: "en")
        let target = Locale.Language(identifier: "zh-Hans")
        let availability = await LanguageAvailability().status(from: source, to: target)
        guard availability == .installed else {
            throw XCTSkip("请先在屏幕译中下载英语和简体中文语言包，再运行系统翻译集成测试。")
        }
        let session = TranslationSession(installedSource: source, target: target)
        let responses = try await session.translations(from: [
            .init(sourceText: "Open Settings", clientIdentifier: "en\u{0}Open Settings"),
            .init(sourceText: "Save the document", clientIdentifier: "en\u{0}Save the document")
        ])
        XCTAssertEqual(responses.count, 2)
        XCTAssertEqual(Set(responses.compactMap(\.clientIdentifier)), Set(["en\u{0}Open Settings", "en\u{0}Save the document"]))
        for response in responses {
            XCTAssertNotEqual(response.sourceText, response.targetText)
            XCTAssertNotNil(response.targetText.range(of: "\\p{Han}", options: .regularExpression))
        }
    }

    @MainActor
    func testMacOS264TranslationStrategiesWorkWithInstalledLanguages() async throws {
        guard #available(macOS 26.4, *) else { throw XCTSkip("需要 macOS 26.4 的翻译策略接口。") }
        let source = Locale.Language(identifier: "en")
        let target = Locale.Language(identifier: "zh-Hans")
        guard await LanguageAvailability().status(from: source, to: target) == .installed else {
            throw XCTSkip("需要已安装的英语和中文语言包。")
        }
        for strategy in [TranslationSession.Strategy.lowLatency, .highFidelity] {
            let session = TranslationSession(installedSource: source, target: target, preferredStrategy: strategy)
            let response = try await session.translate("The app translates complete sentences with more context.")
            XCTAssertNotNil(response.targetText.range(of: "\\p{Han}", options: .regularExpression))
        }
    }

    @MainActor
    func testCancelledSessionDoesNotTranslate() async throws {
        let source = Locale.Language(identifier: "en")
        let target = Locale.Language(identifier: "zh-Hans")
        guard await LanguageAvailability().status(from: source, to: target) == .installed else {
            throw XCTSkip("需要已安装的英语和中文语言包。")
        }
        let session = TranslationSession(installedSource: source, target: target)
        session.cancel()
        do {
            _ = try await session.translate("Open Settings")
            XCTFail("取消后的翻译会话不应返回新译文")
        } catch {
            XCTAssertTrue(error is TranslationError || error is CancellationError)
        }
    }
}
