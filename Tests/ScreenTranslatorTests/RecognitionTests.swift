import XCTest
import AppKit
@testable import ScreenTranslator

final class RecognitionTests: XCTestCase {
    func testChineseAndNumbersStayUnchanged() {
        XCTAssertNil(TextAnalysis.language(for: "这是中文设置页面", preferred: "auto"))
        XCTAssertNil(TextAnalysis.language(for: "1234 · 09:30", preferred: "en"))
        XCTAssertNil(TextAnalysis.language(for: "保存文件", preferred: "en"))
        XCTAssertEqual(TextAnalysis.language(for: "Settings", preferred: "auto"), "en")
        XCTAssertEqual(TextAnalysis.language(for: "Polish your writing with one click", preferred: "auto"), "en")
        XCTAssertEqual(TextAnalysis.language(for: "Łódź", preferred: "auto"), "en")
        XCTAssertNil(TextAnalysis.language(for: "Настройки", preferred: "auto"))
        XCTAssertEqual(TextAnalysis.language(for: "Настройки", preferred: "ru"), "ru")
    }

    func testAutomaticRecognitionUsesAvailableLanguagesAndSkipsTarget() {
        let supported: Set<String> = ["en", "ru", "ja", "zh-Hans"]
        XCTAssertEqual(TextAnalysis.language(for: "Open Settings", preferred: "auto", supported: supported), "en")
        XCTAssertEqual(TextAnalysis.language(for: "Открыть настройки", preferred: "auto", supported: supported), "ru")
        XCTAssertEqual(TextAnalysis.language(for: "設定を開く", preferred: "auto", supported: supported), "ja")
        XCTAssertNil(TextAnalysis.language(for: "打开设置", preferred: "auto", target: "zh-Hans", supported: supported))
        XCTAssertNil(TextAnalysis.language(for: "Open Settings", preferred: "auto", target: "en", supported: supported))
    }

    func testManualSourceCannotMatchTarget() {
        XCTAssertNil(TextAnalysis.language(for: "Open Settings", preferred: "en", target: "en"))
        XCTAssertEqual(TextAnalysis.language(for: "Open Settings", preferred: "en", target: "fr"), "en")
    }

    func testParagraphLinesMergeButShortLabelsAndColumnsStaySeparate() {
        let paragraph = [
            TextRegion(text: "Translate complete sentences with enough", language: "en", bounds: .init(x: 0.1, y: 0.70, width: 0.5, height: 0.04)),
            TextRegion(text: "context to improve the final result.", language: "en", bounds: .init(x: 0.1, y: 0.65, width: 0.45, height: 0.04))
        ]
        XCTAssertEqual(TextAnalysis.mergeLines(paragraph).count, 1)

        let labels = [
            TextRegion(text: "Cancel", language: "en", bounds: .init(x: 0.1, y: 0.4, width: 0.1, height: 0.04)),
            TextRegion(text: "Save", language: "en", bounds: .init(x: 0.1, y: 0.35, width: 0.1, height: 0.04))
        ]
        XCTAssertEqual(TextAnalysis.mergeLines(labels).count, 2)

        let columns = [
            TextRegion(text: "This is the first column of content.", language: "en", bounds: .init(x: 0.05, y: 0.7, width: 0.35, height: 0.04)),
            TextRegion(text: "This is the second column content.", language: "en", bounds: .init(x: 0.6, y: 0.65, width: 0.35, height: 0.04))
        ]
        XCTAssertEqual(TextAnalysis.mergeLines(columns).count, 2)
    }

    func testMixedChineseKeepsOnlyEnglishRanges() {
        let text = "保存 Save file 设置 Settings"
        let pieces = TextAnalysis.ranges(in: text, language: "en").map { String(text[$0]).trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(pieces, ["Save file", "Settings"])
    }

    func testRetinaGeometryUsesPointsAndBottomLeftOrigin() {
        let normalized = CGRect(x: 0.25, y: 0.75, width: 0.5, height: 0.1)
        let result = TextAnalysis.screenRect(normalized, size: CGSize(width: 1440, height: 900))
        XCTAssertEqual(result, CGRect(x: 360, y: 675, width: 720, height: 90))
    }

    func testCacheSeparatesLanguagesAndClearsSensitiveText() {
        var cache = TranslationCache()
        cache.set("文件", for: "en\u{0}File")
        XCTAssertEqual(cache["en\u{0}File"], "文件")
        XCTAssertNil(cache["de\u{0}File"])
        cache.clear()
        XCTAssertNil(cache["en\u{0}File"])
    }

    func testImageFingerprintDetectsTextChange() {
        let first = fixture("Open Settings")
        let second = fixture("Close Settings")
        XCTAssertEqual(RecognitionService.fingerprint(first), RecognitionService.fingerprint(first))
        XCTAssertNotEqual(RecognitionService.fingerprint(first), RecognitionService.fingerprint(second))
        XCTAssertTrue(RecognitionService.isMeaningfullyDifferent(
            RecognitionService.fingerprint(first), from: RecognitionService.fingerprint(second)))
    }

    func testImageFingerprintIgnoresTinyAnimation() {
        let base = fixture("Open Settings")
        let changed = fixture("Open Settings", tinyDot: true)
        XCTAssertFalse(RecognitionService.isMeaningfullyDifferent(
            RecognitionService.fingerprint(base), from: RecognitionService.fingerprint(changed)))
    }

    func testRealOCRRecognizesImageTextAndPositions() async throws {
        let image = fixture("Open Settings")
        let regions = try await RecognitionService().recognize(image, preferred: "en")
        let region = try XCTUnwrap(regions.first(where: { $0.text.contains("Open Settings") }))
        XCTAssertEqual(region.language, "en")
        XCTAssertGreaterThan(region.bounds.width, 0.1)
        XCTAssertGreaterThan(region.bounds.minY, 0.2)
        XCTAssertLessThan(region.bounds.maxY, 0.95)
    }

    func testRealOCRMixedTextDoesNotCoverChinese() async throws {
        let regions = try await RecognitionService().recognize(fixture("保存 Save file 设置 Settings"), preferred: "en")
        XCTAssertTrue(regions.contains { $0.text.contains("Save") })
        XCTAssertTrue(regions.contains { $0.text.contains("Settings") })
        XCTAssertFalse(regions.contains { $0.text.contains("保存") || $0.text.contains("设置") })
    }

    private func fixture(_ text: String, tinyDot: Bool = false) -> CGImage {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 900, pixelsHigh: 250,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 900, height: 250).fill()
        (text as NSString).draw(at: NSPoint(x: 70, y: 100), withAttributes: [
            .font: NSFont.systemFont(ofSize: 44), .foregroundColor: NSColor.black
        ])
        if tinyDot {
            NSColor.black.setFill()
            NSRect(x: 850, y: 20, width: 2, height: 2).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage!
    }
}
