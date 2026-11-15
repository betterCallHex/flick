import Foundation
import Testing
@testable import Flick

struct PlaybackStateTests {
    @Test func remembersAPositionPartWayThrough() {
        #expect(PlaybackState(position: 60, duration: 600).isWorthResuming)
    }

    @Test func forgetsAPositionInTheFirstSeconds() {
        #expect(!PlaybackState(position: 3, duration: 600).isWorthResuming)
    }

    @Test func forgetsAPositionInTheLastSeconds() {
        #expect(!PlaybackState(position: 597, duration: 600).isWorthResuming)
    }

    @Test func forgetsAFinishedFile() {
        #expect(!PlaybackState(position: 300, duration: 600, isAtEnd: true).isWorthResuming)
    }

    @Test func remembersAStreamWithoutDuration() {
        #expect(PlaybackState(position: 60, duration: 0).isWorthResuming)
    }
}

@Suite(.serialized)
struct ResumeTests {
    @Test func reopeningAFileResumesWhereItWasLeft() async throws {
        let video = try VideoFixture.shared()
        let watchLater = try temporaryDirectory()

        let first = try HeadlessSession(watchLater: watchLater)
        try await first.open(video)
        first.perform { $0.seek(to: 12, precise: true) }
        try await first.waitUntil { abs($0.position - 12) < 0.5 }
        first.perform { $0.saveResumePoint() }

        let second = try HeadlessSession(watchLater: watchLater)
        let resumed = try await second.open(video)
        #expect(abs(resumed.position - 12) < 0.5)
    }

    @Test func reopeningAFinishedFileStartsOver() async throws {
        let video = try VideoFixture.shared()
        let watchLater = try temporaryDirectory()

        let first = try HeadlessSession(watchLater: watchLater)
        try await first.open(video)
        first.perform { $0.seek(to: 12, precise: true) }
        try await first.waitUntil { abs($0.position - 12) < 0.5 }
        first.perform { $0.saveResumePoint() }
        first.perform { $0.seek(to: 19.9, precise: true) }
        try await first.waitUntil(\.isAtEnd)
        first.perform { $0.saveResumePoint() }

        let second = try HeadlessSession(watchLater: watchLater)
        let reopened = try await second.open(video)
        #expect(reopened.position < 1)
    }
}

final class HeadlessSession: @unchecked Sendable {
    private let queue = DispatchQueue(label: "HeadlessSession")
    private let player: Player
    private let states: AsyncStream<PlaybackState>
    private var iterator: AsyncStream<PlaybackState>.Iterator
    private let heartbeat: DispatchSourceTimer

    init(watchLater: URL, volume: Double = 0) throws {
        let options = Player.options(watchLaterDirectory: watchLater, volume: volume) + [("vo", "null"), ("ao", "null")]
        player = Player(mpv: try Mpv(options: options, eventQueue: queue))
        let (states, continuation) = AsyncStream<PlaybackState>.makeStream()
        self.states = states
        iterator = states.makeAsyncIterator()
        heartbeat = DispatchSource.makeTimerSource(queue: queue)
        queue.sync { player.onStateChange = { continuation.yield($0) } }
        heartbeat.schedule(deadline: .now(), repeating: .milliseconds(100))
        let player = player
        heartbeat.setEventHandler { continuation.yield(player.state) }
        heartbeat.resume()
    }

    deinit {
        heartbeat.cancel()
    }

    @discardableResult
    func open(_ url: URL, timeout: Duration = .seconds(10)) async throws -> PlaybackState {
        perform { $0.open(url) }
        return try await waitUntil(timeout: timeout) { $0.duration > 0 && $0.videoSize != nil && !$0.isLoading }
    }

    func perform(_ action: (Player) -> Void) {
        queue.sync { action(player) }
    }

    @discardableResult
    func waitUntil(timeout: Duration = .seconds(10), _ condition: (PlaybackState) -> Bool) async throws -> PlaybackState {
        let deadline = ContinuousClock.now + timeout
        var lastState: PlaybackState?
        while ContinuousClock.now < deadline {
            guard let state = await iterator.next() else { break }
            if condition(state) { return state }
            lastState = state
        }
        throw HeadlessSessionTimeout(lastState: lastState)
    }
}

struct HeadlessSessionTimeout: Error {
    var lastState: PlaybackState?
}

enum VideoFixture {
    private static let generated = Result { try generate(width: 320, height: 240) }
    private static let generatedHalfSize = Result { try generate(width: 160, height: 120) }

    static func shared() throws -> URL {
        try generated.get()
    }

    static func halfSize() throws -> URL {
        try generatedHalfSize.get()
    }

    private static func generate(width: Int, height: Int) throws -> URL {
        let size = "\(width)x\(height)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("flick-fixture-20s-\(size)-faststart.mp4")
        guard !FileManager.default.fileExists(atPath: url.path) else { return url }
        let partial = url.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).mp4")
        let ffmpeg = Process()
        ffmpeg.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        ffmpeg.arguments = [
            "-y", "-loglevel", "error",
            "-f", "lavfi", "-i", "testsrc2=size=\(size):rate=30:duration=20",
            "-c:v", "libx264", "-g", "30", "-pix_fmt", "yuv420p", "-movflags", "+faststart", partial.path,
        ]
        try ffmpeg.run()
        ffmpeg.waitUntilExit()
        try FileManager.default.moveItem(at: partial, to: url)
        return url
    }
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
