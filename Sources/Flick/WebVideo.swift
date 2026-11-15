import Foundation

extension URL {
    static let directMediaExtensions: Set<String> = [
        "mp4", "m4v", "mov", "mkv", "webm", "avi", "ts", "flv", "ogv", "m3u8", "mpd", "mp3", "m4a", "ogg", "flac", "wav",
    ]

    init?(webVideoString string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host() != nil else { return nil }
        self = url
    }

    var displayHost: String {
        guard let host = host() else { return absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var resolvesThroughYtdl: Bool {
        !isFileURL && !Self.directMediaExtensions.contains(pathExtension.lowercased())
    }

    var mpvTarget: String {
        if isFileURL { return path }
        return resolvesThroughYtdl ? "ytdl://\(absoluteString)" : absoluteString
    }
}

enum SignedSegments {
    static func cookieHeader(fromYtdlResult result: String) -> String? {
        guard let output = jsonObject(result)?["stdout"] as? String, let info = jsonObject(output) else { return nil }
        let formats = (info["requested_formats"] as? [[String: Any]] ?? []) + (info["formats"] as? [[String: Any]] ?? [])
        let parameters = formats.lazy.compactMap { $0["extra_param_to_segment_url"] as? String }.first
        return parameters.flatMap(cloudFrontCookie(fromQuery:))
    }

    static func cloudFrontCookie(fromQuery query: String) -> String? {
        var components = URLComponents()
        components.query = query
        let values = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        let names = ["Policy", "Signature", "Key-Pair-Id"]
        guard names.allSatisfy({ values[$0] != nil }) else { return nil }
        return names.map { "CloudFront-\($0)=\(values[$0]!)" }.joined(separator: "; ")
    }

    private static func jsonObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

enum HomebrewTools {
    static let directories = ["/opt/homebrew/bin", "/usr/local/bin"]

    static func exposeToChildProcesses() {
        let inherited = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        setenv("PATH", (directories + [inherited]).joined(separator: ":"), 1)
    }

    static var hasYtdlp: Bool {
        directories.contains { FileManager.default.isExecutableFile(atPath: "\($0)/yt-dlp") }
    }
}
