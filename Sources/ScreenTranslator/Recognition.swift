import AppKit
import NaturalLanguage
import Vision

struct TextRegion: Sendable, Equatable {
    let text: String
    let language: String
    let bounds: CGRect
    var cacheKey: String { language + "\u{0}" + text }
}

enum RecognitionProfile: Sendable {
    case lowLatency
    case highAccuracy
}

enum TextAnalysis {
    static func language(
        for text: String,
        preferred: String,
        target: String = "zh-Hans",
        supported: Set<String> = []
    ) -> String? {
        guard text.unicodeScalars.contains(where: CharacterSet.letters.contains) else { return nil }
        let hasLatin = text.range(of: "\\p{Latin}", options: .regularExpression) != nil
        let hasKana = text.range(of: "[\\p{Hiragana}\\p{Katakana}]", options: .regularExpression) != nil
        let hasHan = text.range(of: "\\p{Han}", options: .regularExpression) != nil
        if preferred != "auto" {
            let sourceBase = baseCode(preferred)
            if hasHan, !hasLatin, !hasKana, sourceBase != "zh", sourceBase != "ja" { return nil }
            if hasKana, sourceBase != "ja" { return nil }
            return sameLanguage(preferred, target) ? nil : preferred
        }

        let candidates = supported
        if hasKana, let japanese = canonicalIdentifier("ja", from: candidates) {
            return sameLanguage(japanese, target) ? nil : japanese
        }
        if hasHan, !hasLatin, !hasKana {
            if Locale.Language(identifier: target).languageCode?.identifier == "zh" { return nil }
            if let chinese = canonicalIdentifier("zh-Hans", from: candidates) { return chinese }
        }
        let recognizer = NLLanguageRecognizer()
        if !candidates.isEmpty {
            recognizer.languageHints = candidates.reduce(into: [:]) {
                $0[NLLanguage(rawValue: baseCode($1))] = 1
            }
        }
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 5).sorted { $0.value > $1.value }
        for (language, confidence) in hypotheses where confidence >= 0.2 {
            if let matched = canonicalIdentifier(language.rawValue, from: candidates) {
                return sameLanguage(matched, target) ? nil : matched
            }
        }

        // Short labels often provide too little context for statistical language
        // recognition. English is the safest fallback for Latin interface text.
        if hasLatin, !sameLanguage("en", target),
           let english = canonicalIdentifier("en", from: candidates.isEmpty ? ["en"] : candidates) {
            return english
        }
        return nil
    }

    static func sameLanguage(_ lhs: String, _ rhs: String) -> Bool {
        let left = Locale.Language(identifier: lhs)
        let right = Locale.Language(identifier: rhs)
        guard left.languageCode == right.languageCode else { return false }
        if left.languageCode?.identifier == "zh", let leftScript = left.script, let rightScript = right.script {
            return leftScript == rightScript
        }
        return true
    }

    private static func baseCode(_ identifier: String) -> String {
        Locale.Language(identifier: identifier).languageCode?.identifier ?? identifier
    }

    private static func canonicalIdentifier(_ detected: String, from supported: Set<String>) -> String? {
        if supported.contains(detected) { return detected }
        let detectedLanguage = Locale.Language(identifier: detected)
        let sameBase = supported.filter {
            Locale.Language(identifier: $0).languageCode == detectedLanguage.languageCode
        }
        if let script = detectedLanguage.script,
           let exactScript = sameBase.first(where: { Locale.Language(identifier: $0).script == script }) {
            return exactScript
        }
        return sameBase.sorted().first
    }

    static func mergeLines(_ regions: [TextRegion]) -> [TextRegion] {
        Dictionary(grouping: regions, by: \.language).values.flatMap { languageRegions in
            let sorted = languageRegions.sorted {
                if abs($0.bounds.maxY - $1.bounds.maxY) > 0.004 { return $0.bounds.maxY > $1.bounds.maxY }
                return $0.bounds.minX < $1.bounds.minX
            }
            var result: [TextRegion] = []
            for region in sorted {
                guard let previous = result.last, shouldMerge(previous, region) else {
                    result.append(region)
                    continue
                }
                result[result.count - 1] = TextRegion(
                    text: previous.text + "\n" + region.text,
                    language: previous.language,
                    bounds: previous.bounds.union(region.bounds)
                )
            }
            return result
        }
    }

    private static func shouldMerge(_ upper: TextRegion, _ lower: TextRegion) -> Bool {
        guard upper.language == lower.language,
              upper.text.count + lower.text.count <= 480,
              max(upper.text.count, lower.text.count) >= 24 else { return false }
        let tallest = max(upper.bounds.height, lower.bounds.height)
        let shortest = min(upper.bounds.height, lower.bounds.height)
        guard tallest > 0, shortest / tallest >= 0.55 else { return false }
        let verticalGap = upper.bounds.minY - lower.bounds.maxY
        guard verticalGap >= -tallest * 0.25, verticalGap <= tallest * 1.15 else { return false }
        let overlap = max(0, min(upper.bounds.maxX, lower.bounds.maxX) - max(upper.bounds.minX, lower.bounds.minX))
        let overlapRatio = overlap / max(0.001, min(upper.bounds.width, lower.bounds.width))
        let leadingAligned = abs(upper.bounds.minX - lower.bounds.minX) <= tallest * 1.8
        return overlapRatio >= 0.45 || leadingAligned
    }

    static func ranges(in text: String, language: String) -> [Range<String.Index>] {
        // Keep Chinese runs visible when an English UI label includes Chinese text.
        if language == "en", text.range(of: "\\p{Han}", options: .regularExpression) != nil {
            let regex = try! NSRegularExpression(pattern: "[^\\p{Han}\\p{Hiragana}\\p{Katakana}]+")
            return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
                guard let range = Range($0.range, in: text), text[range].range(of: "[A-Za-z]", options: .regularExpression) != nil else { return nil }
                return range
            }
        }
        return [text.startIndex..<text.endIndex]
    }

    static func screenRect(_ normalized: CGRect, size: CGSize) -> CGRect {
        CGRect(x: normalized.minX * size.width, y: normalized.minY * size.height,
               width: normalized.width * size.width, height: normalized.height * size.height)
    }
}

final class RecognitionService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.screen-translator.vision", qos: .userInitiated)
    private let lock = NSLock()
    private var activeRequest: VNRecognizeTextRequest?

    func cancel() {
        lock.lock()
        activeRequest?.cancel()
        lock.unlock()
    }

    func recognize(
        _ image: CGImage,
        preferred: String,
        target: String = "zh-Hans",
        supportedSources: Set<String> = [],
        profile: RecognitionProfile = .highAccuracy
    ) async throws -> [TextRegion] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = profile == .lowLatency ? .fast : .accurate
                request.usesLanguageCorrection = profile == .highAccuracy
                request.automaticallyDetectsLanguage = preferred == "auto"
                request.minimumTextHeight = 0.006
                let visionLanguages = (try? request.supportedRecognitionLanguages()) ?? ["en-US"]
                let requestedLanguages = preferred == "auto" ? Array(supportedSources) : [preferred]
                request.recognitionLanguages = Self.visionIdentifiers(
                    for: requestedLanguages + [target],
                    supported: visionLanguages
                )
                self.lock.lock()
                self.activeRequest = request
                self.lock.unlock()
                defer {
                    self.lock.lock()
                    self.activeRequest = nil
                    self.lock.unlock()
                }
                do {
                    try VNImageRequestHandler(cgImage: image).perform([request])
                    let regions = (request.results ?? []).flatMap { observation -> [TextRegion] in
                        guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.35,
                              let language = TextAnalysis.language(
                                for: candidate.string,
                                preferred: preferred,
                                target: target,
                                supported: supportedSources
                              ) else { return [] }
                        return TextAnalysis.ranges(in: candidate.string, language: language).compactMap { range in
                            let value = String(candidate.string[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !value.isEmpty else { return nil }
                            let bounds = (try? candidate.boundingBox(for: range))?.boundingBox ?? observation.boundingBox
                            return TextRegion(text: value, language: language, bounds: bounds)
                        }
                    }
                    continuation.resume(returning: regions)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func visionIdentifiers(for languages: [String], supported: [String]) -> [String] {
        var seen = Set<String>()
        let result = languages.compactMap { requested -> String? in
            let language = Locale.Language(identifier: requested)
            let match = supported.first { candidate in
                let candidateLanguage = Locale.Language(identifier: candidate)
                guard candidateLanguage.languageCode == language.languageCode else { return false }
                if let script = language.script, let candidateScript = candidateLanguage.script {
                    return script == candidateScript
                }
                return true
            }
            guard let match, seen.insert(match).inserted else { return nil }
            return match
        }
        return result.isEmpty ? [supported.first ?? "en-US"] : result
    }

    static func fingerprint(_ image: CGImage) -> Data {
        let width = min(320, image.width)
        let height = max(1, Int((Double(image.height) / Double(max(1, image.width)) * Double(width)).rounded()))
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drewImage = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drewImage else { return Data() }
        return Data(pixels)
    }

    static func isMeaningfullyDifferent(_ previous: Data?, from current: Data) -> Bool {
        guard let previous, previous.count == current.count, !current.isEmpty else { return true }
        var changedPixels = 0
        var totalDifference = 0
        previous.withUnsafeBytes { oldBuffer in
            current.withUnsafeBytes { newBuffer in
                let old = oldBuffer.bindMemory(to: UInt8.self)
                let new = newBuffer.bindMemory(to: UInt8.self)
                for index in old.indices {
                    let difference = abs(Int(old[index]) - Int(new[index]))
                    totalDifference += difference
                    if difference >= 18 { changedPixels += 1 }
                }
            }
        }
        let count = Double(current.count)
        let changedRatio = Double(changedPixels) / count
        let averageDifference = Double(totalDifference) / count
        // Ignore tiny UI animations such as a clock digit or blinking insertion
        // point. Scrolling, window movement, and changed text exceed these limits.
        return changedRatio >= 0.006 || averageDifference >= 1.5
    }
}

/// A result must belong to both the active toggle session and current captured frame.
struct FrameStamp: Equatable, Sendable {
    let generation: UInt64
    let revision: UInt64
}

struct TranslationCache {
    private var values: [String: String] = [:]
    mutating func set(_ value: String, for key: String) {
        if values.count >= 1200 { values.removeAll(keepingCapacity: true) }
        values[key] = value
    }
    subscript(key: String) -> String? { values[key] }
    mutating func clear() { values.removeAll() }
}
