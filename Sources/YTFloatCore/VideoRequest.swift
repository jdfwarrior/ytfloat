import Foundation

public struct VideoRequest: Codable, Equatable, Sendable {
    public let id: String
    public let start: Int

    public init(id: String, start: Int = 0) throws {
        guard id.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil,
              (0...604_800).contains(start) else { throw InputError.invalidVideo }
        self.id = id
        self.start = start
    }

    public init(url text: String) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let supplied = text.contains("://") ? text : "https://" + text
        guard let url = URLComponents(string: supplied),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.port == nil,
              let host = url.host?.lowercased() else { throw InputError.invalidURL }
        let parts = url.path.split(separator: "/").map(String.init)
        let query = url.queryItems ?? []
        var candidate: String?
        if ["youtu.be", "www.youtu.be"].contains(host), parts.count == 1 {
            candidate = parts.first
        } else if ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"].contains(host) {
            if parts == ["watch"] {
                let ids = query.filter { $0.name == "v" }
                guard ids.count == 1 else { throw InputError.invalidURL }
                candidate = ids.first?.value
            } else if parts.count == 2, ["shorts", "live", "embed"].contains(parts[0]) {
                candidate = parts[1]
            }
        }
        guard let candidate else { throw InputError.invalidURL }
        let times = query.filter { $0.name == "t" || $0.name == "start" }
        guard times.count <= 1 else { throw InputError.invalidTime }
        var time = times.first?.value
        if time == nil, let fragment = url.fragment, fragment.hasPrefix("t=") {
            time = String(fragment.dropFirst(2))
        }
        try self.init(id: candidate, start: try time.map(Self.seconds) ?? 0)
    }

    public var url: URL {
        URL(string: "https://www.youtube.com/watch?v=\(id)\(start > 0 ? "&t=\(start)s" : "")")!
    }

    private static func seconds(_ value: String) throws -> Int {
        if let seconds = Int(value), (0...604_800).contains(seconds) { return seconds }
        let pattern = "^(?:(\\d+)h)?(?:(\\d+)m)?(?:(\\d+)s)?$"
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(value.startIndex..., in: value)
        guard !value.isEmpty, let match = expression.firstMatch(in: value, range: range) else {
            throw InputError.invalidTime
        }
        var total = 0
        for (index, multiplier) in [(1, 3600), (2, 60), (3, 1)] {
            if let range = Range(match.range(at: index), in: value) {
                guard let n = Int(value[range]), n <= 604_800 else { throw InputError.invalidTime }
                total += n * multiplier
            }
        }
        guard total <= 604_800 else { throw InputError.invalidTime }
        return total
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: values.decode(String.self, forKey: .id), start: values.decode(Int.self, forKey: .start))
    }
}

public enum InputError: LocalizedError {
    case invalidURL, invalidVideo, invalidTime
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Enter a YouTube watch, Shorts, live, embed, or youtu.be URL."
        case .invalidVideo: return "The YouTube video ID or start time is invalid."
        case .invalidTime: return "Use a start time in seconds or a duration such as 1h2m30s (up to 7 days)."
        }
    }
}
