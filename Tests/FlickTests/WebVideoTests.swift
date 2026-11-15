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

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FLICK_NETWORK_TESTS"] != nil))
    func playsAYouTubeVideo() async throws {
        let session = try HeadlessSession(watchLater: try temporaryDirectory())
        let playing = try await session.open(URL(string: "https://www.youtube.com/watch?v=aqz-KE-bpKQ")!, timeout: .seconds(30))
        #expect(playing.title?.contains("Big Buck Bunny") == true)
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
        let info = #"{"formats":[{"format_id":"a"},{"format_id":"b","extra_param_to_segment_url":"Policy=p&Signature=s&Key-Pair-Id=k"}]}"#
        let result = String(data: try! JSONSerialization.data(withJSONObject: ["status": 0, "stdout": info]), encoding: .utf8)!
        #expect(SignedSegments.cookieHeader(fromYtdlResult: result) == "CloudFront-Policy=p; CloudFront-Signature=s; CloudFront-Key-Pair-Id=k")
    }

    @Test func sendsWebPagesThroughYtdlButPlaysMediaLinksDirectly() {
        #expect(URL(string: "https://www.loom.com/share/abc")!.mpvTarget == "ytdl://https://www.loom.com/share/abc")
        #expect(URL(string: "https://cdn.example.com/clip.MP4")!.mpvTarget == "https://cdn.example.com/clip.MP4")
    }
}
