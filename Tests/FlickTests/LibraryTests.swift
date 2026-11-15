import Foundation
import Testing
@testable import Flick

struct LibraryTests {
    let youtube = URL(string: "https://www.youtube.com/watch?v=aqz-KE-bpKQ")!
    let loom = URL(string: "https://www.loom.com/share/ae4bdcb7209f4769b5e5e43194a2b76d")!
    let movie = URL(fileURLWithPath: "/Users/me/Movies/Trip.mkv")

    @Test func playingSomethingPutsItAtTheTop() throws {
        let clock = TestClock()
        let library = try Library(file: temporaryDirectory().appending(path: "library.json"), now: clock.now)

        library.notePlayed(youtube)
        clock.advance()
        library.notePlayed(movie)

        #expect(library.items.map(\.url) == [movie, youtube])
    }

    @Test func playingSomethingAgainMovesItUpWithoutADuplicate() throws {
        let clock = TestClock()
        let library = try Library(file: temporaryDirectory().appending(path: "library.json"), now: clock.now)
        library.notePlayed(youtube)
        clock.advance()
        library.notePlayed(movie)
        clock.advance()

        library.notePlayed(youtube)

        #expect(library.items.map(\.url) == [youtube, movie])
    }

    @Test func recognisesTheSameFileWrittenTwoWays() throws {
        let library = try Library(file: temporaryDirectory().appending(path: "library.json"))

        library.notePlayed(URL(fileURLWithPath: "/Users/me/Movies/../Movies/Trip.mkv"))
        library.notePlayed(movie)

        #expect(library.items.map(\.url) == [movie])
    }

    @Test func savingALinkAddsItWithoutPlayingIt() throws {
        let library = try Library(file: temporaryDirectory().appending(path: "library.json"))

        library.save(loom)

        #expect(library.items.map(\.url) == [loom])
        #expect(library.items.first?.lastPlayedAt == nil)
    }

    @Test func savingSomethingAlreadyThereKeepsItsPlace() throws {
        let clock = TestClock()
        let library = try Library(file: temporaryDirectory().appending(path: "library.json"), now: clock.now)
        library.save(loom)
        clock.advance()
        library.notePlayed(youtube)
        clock.advance()

        library.save(loom)

        #expect(library.items.map(\.url) == [youtube, loom])
    }

    @Test func remembersTitleThumbnailAndProgressOfWhatIsPlaying() throws {
        let library = try Library(file: temporaryDirectory().appending(path: "library.json"))
        library.notePlayed(youtube)
        let thumbnail = URL(string: "https://i.ytimg.com/vi/aqz-KE-bpKQ/maxresdefault.jpg")!

        library.record(PlaybackState(url: youtube, title: "Big Buck Bunny", thumbnail: thumbnail, position: 150, duration: 600))

        let item = try #require(library.items.first)
        #expect(item.title == "Big Buck Bunny")
        #expect(item.thumbnail == thumbnail)
        #expect(item.progress == 0.25)
    }

    @Test func fillsInASavedLinkFromItsLookup() throws {
        let library = try Library(file: temporaryDirectory().appending(path: "library.json"))
        library.save(loom)

        library.describe(loom, with: try #require(YtdlInfo(json: #"{"title":"Demo","duration":120,"thumbnail":"https://cdn.loom.com/demo.jpg"}"#)))

        let item = try #require(library.items.first)
        #expect(item.title == "Demo")
        #expect(item.duration == 120)
        #expect(item.thumbnail == URL(string: "https://cdn.loom.com/demo.jpg"))
    }

    @Test func doesNotWriteWhilePlaybackIsStillLoading() throws {
        let library = try Library(file: temporaryDirectory().appending(path: "library.json"))
        library.notePlayed(youtube)
        library.record(PlaybackState(url: youtube, title: "Big Buck Bunny", position: 150, duration: 600))

        library.record(PlaybackState(url: youtube, title: "watch?v=aqz-KE-bpKQ", isLoading: true))

        #expect(library.items.first?.title == "Big Buck Bunny")
        #expect(library.items.first?.progress == 0.25)
    }

    @Test func countsAFinishedVideoAsFullyWatched() throws {
        let library = try Library(file: temporaryDirectory().appending(path: "library.json"))
        library.notePlayed(movie)

        library.record(PlaybackState(url: movie, position: 599.9, duration: 600, isAtEnd: true))

        #expect(library.items.first?.progress == 1)
    }

    @Test func keepsATitleWhenTheNextReadingHasNone() throws {
        let library = try Library(file: temporaryDirectory().appending(path: "library.json"))
        library.notePlayed(youtube)
        library.record(PlaybackState(url: youtube, title: "Big Buck Bunny"))

        library.record(PlaybackState(url: youtube, position: 10))

        #expect(library.items.first?.title == "Big Buck Bunny")
    }

    @Test func ignoresPlaybackOfSomethingRemovedFromTheLibrary() throws {
        let library = try Library(file: temporaryDirectory().appending(path: "library.json"))
        library.notePlayed(youtube)
        library.remove(youtube)

        library.record(PlaybackState(url: youtube, title: "Big Buck Bunny", position: 30, duration: 600))

        #expect(library.items.isEmpty)
    }

    @Test func comesBackAfterARelaunch() throws {
        let file = try temporaryDirectory().appending(path: "library.json")
        let first = Library(file: file)
        first.notePlayed(youtube)
        first.record(PlaybackState(url: youtube, title: "Big Buck Bunny", position: 150, duration: 600))
        first.save(movie)

        let second = Library(file: file)

        #expect(second.items == first.items)
    }

    @Test func matchesAFileSavedUnderAnotherSpellingOfItsPath() throws {
        let file = try temporaryDirectory().appending(path: "library.json")
        try #"[{"url":"file:///Users/me/Movies/../Movies/Trip.mkv","addedAt":0,"position":20,"duration":60}]"#.write(to: file, atomically: true, encoding: .utf8)
        let library = Library(file: file)

        library.notePlayed(movie)

        #expect(library.items.map(\.url) == [movie])
        #expect(library.items.first?.position == 20)
    }

    @Test func startsEmptyWhenNothingWasSavedYet() throws {
        let library = try Library(file: temporaryDirectory().appending(components: "missing", "library.json"))
        #expect(library.items.isEmpty)
    }

    @Test func tellsWhoeverIsListeningAboutEachChange() throws {
        let library = try Library(file: temporaryDirectory().appending(path: "library.json"))
        var changes = 0
        library.onChange = { changes += 1 }

        library.save(loom)
        library.notePlayed(loom)
        library.remove(loom)

        #expect(changes == 3)
    }
}

struct LibraryItemTests {
    @Test func namesAnUnplayedLinkByItsSite() {
        let item = LibraryItem(url: URL(string: "https://www.loom.com/share/abc")!, addedAt: .now)
        #expect(item.displayTitle == "loom.com")
        #expect(item.source == "loom.com")
    }

    @Test func namesAFileByItsNameWithoutExtension() {
        let item = LibraryItem(url: URL(fileURLWithPath: "/Users/me/Movies/Trip to Rome.mkv"), addedAt: .now, title: "Trip to Rome.mkv")
        #expect(item.displayTitle == "Trip to Rome")
        #expect(item.source == "Movies")
    }

    @Test func hasNoProgressBeforeTheLengthIsKnown() {
        #expect(LibraryItem(url: URL(string: "https://youtu.be/x")!, addedAt: .now).progress == 0)
    }
}

struct WebVideoInfoTests {
    @Test func readsTitleLengthAndThumbnail() {
        let info = YtdlInfo(stdout: #"{"title":"Big Buck Bunny","duration":634.5,"thumbnail":"https://i.ytimg.com/vi/x/maxresdefault.jpg"}"#)
        #expect(info?.title == "Big Buck Bunny")
        #expect(info?.duration == 634.5)
        #expect(info?.thumbnail == URL(string: "https://i.ytimg.com/vi/x/maxresdefault.jpg"))
    }

    @Test func looksUpALinkWithoutPlayingIt() async throws {
        let lookup = try FakeYtdlp(hangingCalls: 0, answer: URL(string: "http://127.0.0.1:9/fake.mp4")!)

        let info = await WebVideoLookup(executable: lookup.executable).info(for: URL(string: "https://www.youtube.com/watch?v=fake")!)

        #expect(info?.title == "Fake")
        #expect(info?.thumbnail == FakeYtdlp.thumbnail)
    }

    @Test func givesNothingBackWhenTheLookupFails() async {
        let info = await WebVideoLookup(executable: URL(fileURLWithPath: "/usr/bin/false")).info(for: URL(string: "https://www.youtube.com/watch?v=x")!)
        #expect(info == nil)
    }
}

@Suite(.serialized)
struct WebThumbnailPlaybackTests {
    @Test func picksUpTheThumbnailOfAPlayingLink() async throws {
        let video = try VideoFixture.shared()
        let server = try LocalFileServer(directory: video.deletingLastPathComponent())
        defer { server.stop() }
        let lookup = try FakeYtdlp(hangingCalls: 0, answer: server.url(for: video.lastPathComponent))
        let session = try HeadlessSession(watchLater: try temporaryDirectory(), extraOptions: lookup.mpvOptions)

        let playing = try await session.open(URL(string: "https://www.youtube.com/watch?v=fake")!)

        #expect(playing.thumbnail == FakeYtdlp.thumbnail)
    }
}

final class TestClock {
    private var current = Date(timeIntervalSince1970: 1_800_000_000)

    var now: () -> Date { { [unowned self] in current } }

    func advance() {
        current += 60
    }
}
