import Foundation

struct MissionWindowCandidate {
    let title: String
    let appName: String
    let bundleIdentifier: String?
}

enum MissionWindowMatch {
    static func uniqueIndex(label: String, thumbnailIdentifier: String, candidates: [MissionWindowCandidate]) -> Int? {
        guard !label.isEmpty else { return nil }
        let bundle: String? = thumbnailIdentifier.range(of: ".space.", options: .backwards).map {
            String(thumbnailIdentifier[..<$0.lowerBound])
        }.flatMap { $0.isEmpty ? nil : $0 }
        let eligible = candidates.indices.filter { bundle == nil || candidates[$0].bundleIdentifier == bundle }
        let titleMatches = eligible.filter { candidates[$0].title == label }
        if titleMatches.count == 1 { return titleMatches[0] }
        if !titleMatches.isEmpty { return nil }
        // Some apps expose their name instead of a window title. Only accept it when
        // it identifies exactly one window; otherwise the user might close the wrong document.
        let appMatches = eligible.filter { candidates[$0].appName == label }
        return appMatches.count == 1 ? appMatches[0] : nil
    }
}
