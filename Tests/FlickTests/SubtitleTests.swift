import Foundation
import Testing
@testable import Flick

struct SubtitleTrackTests {
    @Test func readsOnlySubtitleTracksFromMpvsTrackList() {
        let json = #"[{"id":1,"type":"video","selected":true},{"id":1,"type":"sub","lang":"de","selected":false},{"id":2,"type":"sub","lang":"en","selected":true}]"#
        #expect(SubtitleTrack.tracks(inTrackList: json) == [
            SubtitleTrack(id: 1, language: "de", isSelected: false),
            SubtitleTrack(id: 2, language: "en", isSelected: true),
        ])
    }

    @Test func picksTheTrackInTheReadersLanguage() {
        let tracks = [SubtitleTrack(id: 1, language: "de", isSelected: false), SubtitleTrack(id: 2, language: "eng", isSelected: false)]
        #expect(SubtitleTrack.preferred(among: tracks, languages: ["en-GB", "de"])?.id == 2)
    }

    @Test func fallsBackToTheFirstTrackWhenNoLanguageMatches() {
        let tracks = [SubtitleTrack(id: 1, language: "ar", isSelected: false), SubtitleTrack(id: 2, language: nil, isSelected: false)]
        #expect(SubtitleTrack.preferred(among: tracks, languages: ["fr"])?.id == 1)
    }

    @Test func asksYtdlForCaptionsInTheReadersLanguagesAndTheSpokenOne() {
        #expect(WebSubtitles.ytdlRawOptions(languages: ["fr-CA", "fr-FR", "en-US"]) == "sub-langs=[fr,en,.*-orig],write-auto-subs=")
    }
}

@Suite(.serialized)
struct SubtitleToggleTests {
    @Test func hidesAndShowsSubtitlesNextToALocalFile() async throws {
        let session = try HeadlessSession(watchLater: try temporaryDirectory())
        let opened = try await session.open(try SubtitledVideoFixture.make())
        #expect(opened.isShowingSubtitles)

        session.perform { $0.toggleSubtitles() }
        try await session.waitUntil { !$0.isShowingSubtitles }

        session.perform { $0.toggleSubtitles() }
        try await session.waitUntil(\.isShowingSubtitles)
    }

    @Test func turningSubtitlesOnPicksATrackWhenNoneIsSelected() async throws {
        let session = try HeadlessSession(watchLater: try temporaryDirectory())
        try await session.open(try SubtitledVideoFixture.make())
        session.perform { $0.mpv.set("sid", "no") }
        try await session.waitUntil { $0.hasSubtitles && !$0.isShowingSubtitles }

        session.perform { $0.toggleSubtitles() }
        try await session.waitUntil(\.isShowingSubtitles)
    }

    @Test func startsHiddenWhenTheReaderTurnedSubtitlesOff() async throws {
        let options = Player.options(watchLaterDirectory: try temporaryDirectory(), volume: 0, showsSubtitles: false)
        let session = try HeadlessSession(options: options)
        let opened = try await session.open(try SubtitledVideoFixture.make())
        #expect(opened.hasSubtitles && !opened.isShowingSubtitles)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FLICK_NETWORK_TESTS"] != nil))
    func showsYouTubeCaptions() async throws {
        let showing = try await retryingWhenYouTubeRefusesAStream {
            let session = try HeadlessSession(watchLater: try temporaryDirectory())
            let playing = try await session.open(URL(string: "https://www.youtube.com/watch?v=jNQXAC9IVRw")!, timeout: .seconds(45))
            #expect(playing.hasSubtitles)

            session.perform { $0.toggleSubtitles(preferredLanguages: ["en"]) }
            return try await session.waitUntil(\.isShowingSubtitles)
        }
        #expect(showing.subtitleTracks.first(where: \.isSelected)?.language?.hasPrefix("en") == true)
    }
}

enum SubtitledVideoFixture {
    static func make() throws -> URL {
        let directory = try temporaryDirectory()
        let video = directory.appendingPathComponent("clip.mp4")
        try FileManager.default.copyItem(at: try VideoFixture.shared(), to: video)
        try "1\n00:00:00,000 --> 00:00:19,000\nHello\n".write(to: directory.appendingPathComponent("clip.srt"), atomically: true, encoding: .utf8)
        return video
    }
}
