import Foundation
import Testing
@testable import Flick

@Suite(.serialized)
struct PlayerCommandTests {
    @Test func spaceAtTheEndStartsTheVideoAgain() async throws {
        let session = try await openedSession()
        session.perform { $0.seek(to: 19.9, precise: true) }
        try await session.waitUntil(\.isAtEnd)
        session.perform { $0.togglePause() }
        let restarted = try await session.waitUntil { !$0.isAtEnd && !$0.isPaused && $0.position < 2 }
        #expect(restarted.position < 2)
    }

    @Test func seekingForwardMovesByTheGivenSeconds() async throws {
        let session = try await openedSession()
        session.perform { $0.mpv.set("pause", true) }
        session.perform { $0.seek(by: 5) }
        let moved = try await session.waitUntil { $0.position > 4 }
        #expect(abs(moved.position - 5) < 0.5)
    }

    @Test func speedStopsAtFourTimes() async throws {
        let session = try await openedSession()
        session.perform { $0.mpv.set("speed", 3.75) }
        try await session.waitUntil { $0.speed == 3.75 }
        session.perform { $0.changeSpeed(by: 0.25) }
        try await session.waitUntil { $0.speed == 4 }
        session.perform { $0.changeSpeed(by: 0.25) }
        session.perform { $0.toggleMute() }
        let afterMarker = try await session.waitUntil(\.isMuted)
        #expect(afterMarker.speed == 4)
    }

    @Test func raisingVolumeWhileMutedUnmutes() async throws {
        let session = try await openedSession()
        session.perform { $0.toggleMute() }
        try await session.waitUntil(\.isMuted)
        session.perform { $0.changeVolume(by: 5) }
        let unmuted = try await session.waitUntil { !$0.isMuted }
        #expect(!unmuted.isMuted)
    }

    @Test func volumeNeverGoesAboveOneHundred() async throws {
        let session = try await openedSession(volume: 98)
        session.perform { $0.changeVolume(by: 5) }
        let loudest = try await session.waitUntil { $0.volume == 100 }
        #expect(loudest.volume == 100)
    }

    @Test func reportsBothSidesOfANewResolutionTogether() async throws {
        let session = try await openedSession()
        let halfSize = try VideoFixture.halfSize()
        var shapes: [CGSize] = []

        session.perform { $0.mpv.command("loadfile", halfSize.path, "replace") }

        try await session.waitUntil { state in
            if let size = state.videoSize { shapes.append(size) }
            return state.videoSize == CGSize(width: 160, height: 120)
        }
        #expect(shapes.allSatisfy { $0.hasSameShape(as: CGSize(width: 4, height: 3)) })
    }

    @Test func pickingAQualityKeepsAskingForWebSubtitles() async throws {
        let session = try await openedSession()
        var rawOptions: String?
        session.perform { player in
            player.limitResolution(to: 720)
            rawOptions = player.mpv.string("ytdl-raw-options")
        }
        #expect(rawOptions?.contains("format-sort=res:720") == true)
        #expect(rawOptions?.contains("sub-langs=") == true)
    }

    private func openedSession(volume: Double = 0) async throws -> HeadlessSession {
        let session = try HeadlessSession(watchLater: try temporaryDirectory(), volume: volume)
        try await session.open(try VideoFixture.shared())
        return session
    }
}
