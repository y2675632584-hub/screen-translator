import XCTest
@testable import ScreenTranslator

final class MissionWindowMatchTests: XCTestCase {
    func testTitleAndBundleIdentifyOnlyIntendedWindow() {
        let windows = [
            MissionWindowCandidate(title: "报告", appName: "编辑器", bundleIdentifier: "example.a"),
            MissionWindowCandidate(title: "报告", appName: "编辑器", bundleIdentifier: "example.b")
        ]
        XCTAssertEqual(MissionWindowMatch.uniqueIndex(label: "报告", thumbnailIdentifier: "example.b.space.4", candidates: windows), 1)
        XCTAssertNil(MissionWindowMatch.uniqueIndex(label: "报告", thumbnailIdentifier: "", candidates: windows))
    }

    func testAmbiguousWindowsAreNeverClosed() {
        let window = MissionWindowCandidate(title: "无标题", appName: "编辑器", bundleIdentifier: "example.a")
        XCTAssertNil(MissionWindowMatch.uniqueIndex(label: "无标题", thumbnailIdentifier: "example.a.space.1", candidates: [window, window]))
        XCTAssertNil(MissionWindowMatch.uniqueIndex(label: "编辑器", thumbnailIdentifier: "example.a.space.1", candidates: [window, window]))
    }

    func testAppNameMatchesOnlyOneWindowAndUnknownIdentifierDoesNotFilter() {
        let window = MissionWindowCandidate(title: "", appName: "计算器", bundleIdentifier: "com.apple.calculator")
        XCTAssertEqual(MissionWindowMatch.uniqueIndex(label: "计算器", thumbnailIdentifier: "mc.preview", candidates: [window]), 0)
        XCTAssertNil(MissionWindowMatch.uniqueIndex(label: "其他", thumbnailIdentifier: "", candidates: [window]))
    }
}
