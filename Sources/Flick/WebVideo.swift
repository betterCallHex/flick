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

struct YtdlInfo {
    let title: String?
    let duration: Double?
    let thumbnail: URL?
    private let formats: [[String: Any]]

    init?(subprocessResult: String) {
        guard let output = Self.jsonObject(subprocessResult)?["stdout"] as? String else { return nil }
        self.init(json: output)
    }

    init?(json: String) {
        guard let info = Self.jsonObject(json) else { return nil }
        title = info["title"] as? String
        duration = info["duration"] as? Double
        thumbnail = (info["thumbnail"] as? String).flatMap(URL.init(webVideoString:))
        formats = (info["requested_formats"] as? [[String: Any]] ?? []) + (info["formats"] as? [[String: Any]] ?? [])
    }

    var signedSegmentCookie: String? {
        formats.lazy.compactMap { $0["extra_param_to_segment_url"] as? String }.first.flatMap(SignedSegments.cloudFrontCookie(fromQuery:))
    }

    var resolutions: [Int] {
        let videoFormats = formats.filter { ($0["vcodec"] as? String) != "none" }
        let shortSides = videoFormats.compactMap { format -> Int? in
            guard let width = format["width"] as? Int, let height = format["height"] as? Int else { return nil }
            return min(width, height)
        }
        return Set(shortSides).sorted(by: >)
    }

    private static func jsonObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

struct WebVideoLookup {
    let executable: URL

    static var installed: WebVideoLookup? {
        HomebrewTools.ytdlp.map(WebVideoLookup.init(executable:))
    }

    func info(for url: URL) async -> YtdlInfo? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: run(for: url))
            }
        }
    }

    private func run(for url: URL) -> YtdlInfo? {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["--dump-single-json", "--no-playlist", "--skip-download", "--no-warnings", url.absoluteString]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return YtdlInfo(json: String(decoding: data, as: UTF8.self))
    }
}

enum VideoQuality {
    static func ytdlRawOptions(maxResolution: Int?) -> String {
        maxResolution.map { "format-sort=res:\($0)" } ?? ""
    }
}

enum SignedSegments {
    static func cloudFrontCookie(fromQuery query: String) -> String? {
        var components = URLComponents()
        components.query = query
        let values = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        let names = ["Policy", "Signature", "Key-Pair-Id"]
        guard names.allSatisfy({ values[$0] != nil }) else { return nil }
        return names.map { "CloudFront-\($0)=\(values[$0]!)" }.joined(separator: "; ")
    }
}

enum HomebrewTools {
    static let directories = ["/opt/homebrew/bin", "/usr/local/bin"]

    static func exposeToChildProcesses() {
        let inherited = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        setenv("PATH", (directories + [inherited]).joined(separator: ":"), 1)
    }

    static var hasYtdlp: Bool { ytdlp != nil }

    static var ytdlp: URL? {
        directories.lazy.map { URL(fileURLWithPath: $0).appending(path: "yt-dlp") }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
