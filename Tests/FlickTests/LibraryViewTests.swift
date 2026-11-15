import AppKit
import Testing
@testable import Flick

@MainActor
struct LibraryViewTests {
    let youtube = URL(string: "https://www.youtube.com/watch?v=aqz-KE-bpKQ")!
    let loom = URL(string: "https://www.loom.com/share/ae4bdcb7209f4769b5e5e43194a2b76d")!

    @Test func showsTheDropHintUntilSomethingIsInTheLibrary() throws {
        let library = try Library(file: temporaryDirectory().appending(path: "library.json"))
        let view = LibraryView(library: library)
        #expect(view.isEmpty)

        library.save(loom)

        #expect(!view.isEmpty)
    }

    @Test func showsOneTilePerItemNewestFirst() throws {
        let clock = TestClock()
        let library = try Library(file: temporaryDirectory().appending(path: "library.json"), now: clock.now)
        library.notePlayed(youtube)
        clock.advance()
        library.save(loom)
        let view = LibraryView(library: library)
        let grid = NSCollectionView()

        #expect(view.collectionView(grid, numberOfItemsInSection: 0) == 2)
        #expect(library.items.first?.url == loom)
    }

    @Test func choosingATilePlaysIt() throws {
        let library = try Library(file: temporaryDirectory().appending(path: "library.json"))
        library.save(loom)
        let view = LibraryView(library: library)
        var played: URL?
        view.onPlay = { played = $0 }

        view.collectionView(NSCollectionView(), didSelectItemsAt: [IndexPath(item: 0, section: 0)])

        #expect(played == loom)
    }

    @Test func pressingATileWithVoiceOverPlaysIt() throws {
        let library = try Library(file: temporaryDirectory().appending(path: "library.json"))
        library.save(loom)
        let view = LibraryView(library: library)
        var played: URL?
        view.onPlay = { played = $0 }

        let tile = try tile(at: 0, of: view)

        #expect(tile.accessibilityRole() == .button)
        #expect(tile.accessibilityLabel() == "loom.com")
        #expect(tile.accessibilityPerformPress())
        #expect(played == loom)
    }

    @Test func removesAnItemFromItsTileMenu() throws {
        let library = try Library(file: temporaryDirectory().appending(path: "library.json"))
        library.save(loom)
        let view = LibraryView(library: library)
        let menu = try #require(try tile(at: 0, of: view).menu)

        #expect(menu.items.map(\.title) == ["Play", "Copy Link", "", "Remove from Library"])
        menu.performActionForItem(at: try #require(menu.items.firstIndex { $0.title == "Remove from Library" }))

        #expect(library.items.isEmpty)
    }

    @Test func offersFinderInsteadOfCopyForAFile() throws {
        let library = try Library(file: temporaryDirectory().appending(path: "library.json"))
        library.save(URL(fileURLWithPath: "/Users/me/Movies/Trip.mkv"))
        let menu = try #require(try tile(at: 0, of: LibraryView(library: library)).menu)

        #expect(menu.items.map(\.title).contains("Show in Finder"))
    }

    private func tile(at index: Int, of view: LibraryView) throws -> NSView {
        let grid = NSCollectionView()
        grid.collectionViewLayout = NSCollectionViewFlowLayout()
        grid.register(LibraryCell.self, forItemWithIdentifier: LibraryCell.identifier)
        grid.dataSource = view
        return view.collectionView(grid, itemForRepresentedObjectAt: IndexPath(item: index, section: 0)).view
    }

    @Test func rendersOffscreen() throws {
        let video = try VideoFixture.shared()
        let library = try Library(file: temporaryDirectory().appending(path: "library.json"))
        library.notePlayed(video)
        library.record(PlaybackState(url: video, position: 8, duration: 20))
        library.notePlayed(youtube)
        library.record(PlaybackState(url: youtube, title: "Big Buck Bunny 60fps 4K - Official Blender Foundation Short Film", position: 300, duration: 635))
        library.save(loom)

        let image = try OffscreenRender.png(of: LibraryView(library: library), size: NSSize(width: 960, height: 620))

        #expect(image.count > 10_000)
        if let directory = ProcessInfo.processInfo.environment["FLICK_SNAPSHOT_DIR"] {
            try image.write(to: URL(fileURLWithPath: directory).appending(path: "library.png"))
        }
    }
}

@MainActor
enum OffscreenRender {
    static func png(of view: NSView, size: NSSize) throws -> Data {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = view
        RunLoop.main.run(until: .now + 1.5)
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}
