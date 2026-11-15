import Foundation

struct LibraryItem: Codable, Equatable {
    var url: URL
    var addedAt: Date
    var lastPlayedAt: Date?
    var title: String?
    var thumbnail: URL?
    var position = 0.0
    var duration = 0.0

    var displayTitle: String {
        url.isFileURL ? url.deletingPathExtension().lastPathComponent : title ?? url.displayHost
    }

    var source: String {
        url.isFileURL ? url.deletingLastPathComponent().lastPathComponent : url.displayHost
    }

    var progress: Double {
        duration > 0 ? (position / duration).clamped(to: 0...1) : 0
    }

    var recency: Date { lastPlayedAt ?? addedAt }
}

final class Library {
    private(set) var items: [LibraryItem]
    var onChange: (() -> Void)?
    private let file: URL
    private let now: () -> Date

    init(file: URL, now: @escaping () -> Date = Date.init) {
        self.file = file
        self.now = now
        let saved = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([LibraryItem].self, from: $0) } ?? []
        items = saved.map { item in
            var item = item
            item.url = item.url.libraryKey
            return item
        }
    }

    func notePlayed(_ url: URL) {
        let url = url.libraryKey
        change { items in
            var item = items.first { $0.url == url } ?? LibraryItem(url: url, addedAt: now())
            item.lastPlayedAt = now()
            items.removeAll { $0.url == url }
            items.append(item)
        }
    }

    func save(_ url: URL) {
        let url = url.libraryKey
        guard !items.contains(where: { $0.url == url }) else { return }
        change { $0.append(LibraryItem(url: url, addedAt: now())) }
    }

    func record(_ state: PlaybackState) {
        guard !state.isLoading, let url = state.url?.libraryKey, let index = items.firstIndex(where: { $0.url == url }) else { return }
        var item = items[index]
        item.title = state.title ?? item.title
        item.thumbnail = state.thumbnail ?? item.thumbnail
        if state.duration > 0 { item.duration = state.duration }
        item.position = state.isAtEnd ? item.duration : state.position
        update(item, at: index)
    }

    func describe(_ url: URL, with info: YtdlInfo) {
        let url = url.libraryKey
        guard let index = items.firstIndex(where: { $0.url == url }) else { return }
        var item = items[index]
        item.title = info.title ?? item.title
        item.thumbnail = info.thumbnail ?? item.thumbnail
        item.duration = info.duration ?? item.duration
        update(item, at: index)
    }

    func remove(_ url: URL) {
        let url = url.libraryKey
        guard items.contains(where: { $0.url == url }) else { return }
        change { $0.removeAll { $0.url == url } }
    }

    private func update(_ item: LibraryItem, at index: Int) {
        guard item != items[index] else { return }
        change { $0[index] = item }
    }

    private func change(_ mutate: (inout [LibraryItem]) -> Void) {
        mutate(&items)
        items.sort { $0.recency > $1.recency }
        persist()
        onChange?()
    }

    private func persist() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(items).write(to: file, options: .atomic)
    }
}

extension URL {
    var libraryKey: URL {
        isFileURL ? standardizedFileURL : self
    }
}
