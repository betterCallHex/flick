import Foundation
import Testing
@testable import Flick

struct WebVideoLinkTests {
    @Test func acceptsAPastedLinkWithSurroundingWhitespace() {
        let url = URL(webVideoString: "  https://www.youtube.com/watch?v=aqz-KE-bpKQ\n")
        #expect(url?.absoluteString == "https://www.youtube.com/watch?v=aqz-KE-bpKQ")
    }

    @Test func rejectsTextThatIsNotAWebLink() {
        #expect(URL(webVideoString: "watch this later") == nil)
        #expect(URL(webVideoString: "ftp://example.com/video.mp4") == nil)
        #expect(URL(webVideoString: "file:///Users/me/video.mp4") == nil)
        #expect(URL(webVideoString: "https://") == nil)
    }

    @Test func handsMpvOnlyThePathForLocalFiles() {
        #expect(URL(fileURLWithPath: "/tmp/a b.mkv").mpvTarget == "/tmp/a b.mkv")
    }
}

struct VideoQualityTests {
    @Test func listsEachVideoResolutionOnceFromHighestToLowest() {
        let info = YtdlInfo(stdout: #"""
        {"formats":[
          {"format_id":"140","vcodec":"none","acodec":"mp4a"},
          {"format_id":"134","vcodec":"avc1","width":640,"height":360},
          {"format_id":"137","vcodec":"avc1","width":1920,"height":1080},
          {"format_id":"248","vcodec":"vp9","width":1920,"height":1080},
          {"format_id":"sb0","vcodec":"none","width":160,"height":90},
          {"format_id":"136","vcodec":"avc1","width":1280,"height":720}
        ]}
        """#)
        #expect(info?.resolutions == [1080, 720, 360])
    }

    @Test func namesPortraitVideosByTheirShortSide() {
        let info = YtdlInfo(stdout: #"{"formats":[{"vcodec":"vp9","width":1080,"height":1920},{"vcodec":"vp9","width":720,"height":1280}]}"#)
        #expect(info?.resolutions == [1080, 720])
    }

    @Test func asksYtdlpForTheLargestResolutionUpToTheLimit() {
        #expect(VideoQuality.ytdlRawOptions(maxResolution: 720) == "format-sort=res:720")
        #expect(VideoQuality.ytdlRawOptions(maxResolution: nil) == "")
    }
}

extension YtdlInfo {
    init?(stdout: String) {
        let result = String(data: try! JSONSerialization.data(withJSONObject: ["status": 0, "stdout": stdout]), encoding: .utf8)!
        self.init(subprocessResult: result)
    }
}

@Suite(.serialized)
struct WebPlaybackTests {
    @Test func playsADirectVideoLinkFromAServer() async throws {
        let video = try VideoFixture.shared()
        let server = try LocalFileServer(directory: video.deletingLastPathComponent())
        defer { server.stop() }
        let session = try HeadlessSession(watchLater: try temporaryDirectory())
        let link = server.url(for: video.lastPathComponent)

        let playing = try await session.open(link)

        #expect(playing.url == link)
        #expect(abs(playing.duration - 20) < 0.5)
    }

    @Test func retriesALinkWhoseLookupHangs() async throws {
        let video = try VideoFixture.shared()
        let server = try LocalFileServer(directory: video.deletingLastPathComponent())
        defer { server.stop() }
        let lookup = try FakeYtdlp(hangingCalls: 1, answer: server.url(for: video.lastPathComponent))
        let session = try HeadlessSession(watchLater: try temporaryDirectory(), extraOptions: lookup.mpvOptions)
        session.perform { $0.webLoadTimeoutSeconds = 5 }

        let playing = try await session.open(URL(string: "https://www.youtube.com/watch?v=hangs-once")!, timeout: .seconds(20))

        #expect(abs(playing.duration - 20) < 0.5)
        #expect(try await lookup.callsRunningOnceSettled().isEmpty)
    }

    @Test func givesUpOnALinkWhoseLookupKeepsHanging() async throws {
        let lookup = try FakeYtdlp(hangingCalls: 99, answer: URL(string: "http://127.0.0.1:9/never")!)
        let session = try HeadlessSession(watchLater: try temporaryDirectory(), extraOptions: lookup.mpvOptions)
        session.perform { $0.webLoadTimeoutSeconds = 3 }

        session.perform { $0.open(URL(string: "https://www.youtube.com/watch?v=hangs-always")!) }
        let gaveUp = try await session.waitUntil(timeout: .seconds(15)) { $0.loadFailure != nil }

        #expect(gaveUp.loadFailure == .timedOut)
        #expect(!gaveUp.isLoading)
        #expect(lookup.calls == 2)
        #expect(try await lookup.callsRunningOnceSettled().isEmpty)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FLICK_NETWORK_TESTS"] != nil))
    func playsAYouTubeVideo() async throws {
        let playing = try await retryingWhenYouTubeRefusesAStream {
            let session = try HeadlessSession(watchLater: try temporaryDirectory())
            return try await session.open(URL(string: "https://www.youtube.com/watch?v=aqz-KE-bpKQ")!, timeout: .seconds(30))
        }
        #expect(playing.title?.contains("Big Buck Bunny") == true)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FLICK_NETWORK_TESTS"] != nil))
    func switchesAYouTubeVideoToALowerQualityWhereItWas() async throws {
        let switched = try await retryingWhenYouTubeRefusesAStream {
            let session = try HeadlessSession(watchLater: try temporaryDirectory())
            let opened = try await session.open(URL(string: "https://www.youtube.com/watch?v=aqz-KE-bpKQ")!, timeout: .seconds(30))
            #expect(opened.resolutions.contains(360))
            session.perform { $0.seek(to: 60, precise: true) }
            try await session.waitUntil { abs($0.position - 60) < 1 }

            session.perform { $0.limitResolution(to: 360) }

            return try await session.waitUntil(timeout: .seconds(30)) { !$0.isLoading && $0.videoHeight == 360 }
        }
        #expect(abs(switched.position - 60) < 2)
        #expect(switched.maxResolution == 360)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FLICK_NETWORK_TESTS"] != nil))
    func playsALoomVideo() async throws {
        let session = try HeadlessSession(watchLater: try temporaryDirectory())
        let playing = try await session.open(URL(string: "https://www.loom.com/share/ae4bdcb7209f4769b5e5e43194a2b76d")!, timeout: .seconds(30))
        #expect(playing.title == "Demo of a Loom Video")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FLICK_NETWORK_TESTS"] != nil))
    func playsALoomVideoServedAsHLS() async throws {
        let session = try HeadlessSession(watchLater: try temporaryDirectory())
        let playing = try await session.open(URL(string: "https://www.loom.com/share/56fde5f991b8490d9033dd226ebf3043")!, timeout: .seconds(30))
        #expect(playing.videoSize != nil)
    }
}

func retryingWhenYouTubeRefusesAStream(_ attempt: () async throws -> PlaybackState) async throws -> PlaybackState {
    do {
        return try await attempt()
    } catch is HeadlessSessionTimeout {
        return try await attempt()
    }
}

struct FakeYtdlp {
    static let thumbnail = URL(string: "https://i.ytimg.com/vi/fake/maxresdefault.jpg")!
    let directory: URL

    init(hangingCalls: Int, answer: URL) throws {
        directory = try temporaryDirectory()
        let info = #"{"id":"fake","title":"Fake","ext":"mp4","thumbnail":"\#(Self.thumbnail.absoluteString)","url":"\#(answer.absoluteString)"}"#
        let script = """
        #!/bin/sh
        echo $$ >> '\(directory.path)/calls'
        if [ "$(wc -l < '\(directory.path)/calls')" -le \(hangingCalls) ]; then exec sleep 600; fi
        echo '\(info)'
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    var mpvOptions: [(name: String, value: String)] {
        [("script-opts", "ytdl_hook-ytdl_path=\(executable.path)")]
    }

    var calls: Int { pids.count }

    func callsRunningOnceSettled(within timeout: Duration = .seconds(5)) async throws -> [pid_t] {
        let deadline = ContinuousClock.now + timeout
        while !runningCalls.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        return runningCalls
    }

    private var runningCalls: [pid_t] { pids.filter { kill($0, 0) == 0 } }

    var executable: URL { directory.appendingPathComponent("yt-dlp") }

    private var pids: [pid_t] {
        let text = (try? String(contentsOf: directory.appendingPathComponent("calls"), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").compactMap { pid_t($0) }
    }
}

final class LocalFileServer {
    let port = Int.random(in: 20000...40000)
    private let process = Process()

    init(directory: URL) throws {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-m", "http.server", String(port), "--bind", "127.0.0.1", "--directory", directory.path]
        process.standardError = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        try waitUntilListening()
    }

    func url(for file: String) -> URL {
        URL(string: "http://127.0.0.1:\(port)/\(file)")!
    }

    func stop() {
        process.terminate()
    }

    private func waitUntilListening() throws {
        for _ in 0..<100 {
            if (try? Data(contentsOf: URL(string: "http://127.0.0.1:\(port)/")!)) != nil { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw HeadlessSessionTimeout()
    }
}

struct SignedSegmentsTests {
    @Test func turnsACloudFrontSegmentSignatureIntoCookies() {
        let cookie = SignedSegments.cloudFrontCookie(fromQuery: "Policy=abc&Signature=d~e_f&Key-Pair-Id=K123")
        #expect(cookie == "CloudFront-Policy=abc; CloudFront-Signature=d~e_f; CloudFront-Key-Pair-Id=K123")
    }

    @Test func ignoresSegmentParametersThatAreNotCloudFrontSignatures() {
        #expect(SignedSegments.cloudFrontCookie(fromQuery: "token=xyz") == nil)
    }

    @Test func readsTheSignatureFromYtdlOutput() {
        let info = YtdlInfo(stdout: #"{"formats":[{"format_id":"a"},{"format_id":"b","extra_param_to_segment_url":"Policy=p&Signature=s&Key-Pair-Id=k"}]}"#)
        #expect(info?.signedSegmentCookie == "CloudFront-Policy=p; CloudFront-Signature=s; CloudFront-Key-Pair-Id=k")
    }

    @Test func sendsWebPagesThroughYtdlButPlaysMediaLinksDirectly() {
        #expect(URL(string: "https://www.loom.com/share/abc")!.mpvTarget == "ytdl://https://www.loom.com/share/abc")
        #expect(URL(string: "https://cdn.example.com/clip.MP4")!.mpvTarget == "https://cdn.example.com/clip.MP4")
    }
}
