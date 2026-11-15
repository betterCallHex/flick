import AppKit
import QuickLookThumbnailing

final class LibraryView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    static let itemSize = NSSize(width: 208, height: 172)
    static let headerHeight: CGFloat = 92

    var onPlay: ((URL) -> Void)?
    var onAddFiles: (() -> Void)?
    var onAddLink: (() -> Void)?
    private let library: Library
    private let thumbnails = Thumbnails()
    private let collectionView = NSCollectionView()
    private let scrollView = NSScrollView()
    private let header = NSStackView()
    private let emptyState = EmptyStateView()

    init(library: Library) {
        self.library = library
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.07, alpha: 1).cgColor
        buildHeader()
        buildGrid()
        layoutSubviews()
        emptyState.onOpen = { NSApp.sendAction(#selector(AppDelegate.openDocument(_:)), to: nil, from: nil) }
        library.onChange = { [weak self] in self?.reload() }
        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("LibraryView is created in code only")
    }

    var isEmpty: Bool { library.items.isEmpty }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {}

    override func scrollWheel(with event: NSEvent) {}

    override func magnify(with event: NSEvent) {}

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        library.items.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: LibraryCell.identifier, for: indexPath)
        guard let cell = cell as? LibraryCell else { return cell }
        let item = library.items[indexPath.item]
        cell.show(item, menu: menu(for: item))
        cell.onPlay = { [weak self] in self?.onPlay?(item.url) }
        Task { @MainActor [thumbnails] in
            let image = await thumbnails.image(for: item, size: Self.itemSize)
            cell.showThumbnail(image, for: item.url)
        }
        return cell
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        collectionView.deselectItems(at: indexPaths)
        guard let index = indexPaths.first?.item, library.items.indices.contains(index) else { return }
        onPlay?(library.items[index].url)
    }

    private func menu(for item: LibraryItem) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(menuItem("Play", #selector(playClicked(_:)), for: item))
        if item.url.isFileURL {
            menu.addItem(menuItem("Show in Finder", #selector(showClickedInFinder(_:)), for: item))
        } else {
            menu.addItem(menuItem("Copy Link", #selector(copyClickedLink(_:)), for: item))
        }
        menu.addItem(.separator())
        menu.addItem(menuItem("Remove from Library", #selector(removeClicked(_:)), for: item))
        return menu
    }

    private func buildHeader() {
        let title = NSTextField(labelWithString: "Library")
        title.font = .systemFont(ofSize: 22, weight: .bold)
        title.textColor = .white
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let addLink = headerButton("Add Link…", symbol: "link", action: #selector(addLinkPressed))
        let addFiles = headerButton("Add Files…", symbol: "plus", action: #selector(addFilesPressed))
        header.orientation = .horizontal
        header.spacing = 8
        header.setViews([title, spacer, addLink, addFiles], in: .leading)
    }

    private func headerButton(_ title: String, symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.bezelStyle = .push
        return button
    }

    private func buildGrid() {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = Self.itemSize
        layout.minimumInteritemSpacing = 16
        layout.minimumLineSpacing = 20
        layout.sectionInset = NSEdgeInsets(top: 4, left: 24, bottom: 24, right: 24)
        collectionView.collectionViewLayout = layout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(LibraryCell.self, forItemWithIdentifier: LibraryCell.identifier)
        scrollView.documentView = collectionView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
    }

    private func layoutSubviews() {
        for view in [header, scrollView, emptyState] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 40),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: Self.headerHeight),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            emptyState.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func reload() {
        header.isHidden = isEmpty
        scrollView.isHidden = isEmpty
        emptyState.isHidden = !isEmpty
        collectionView.reloadData()
    }

    @objc private func addLinkPressed() {
        onAddLink?()
    }

    @objc private func addFilesPressed() {
        onAddFiles?()
    }

    private func menuItem(_ title: String, _ action: Selector, for item: LibraryItem) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        menuItem.representedObject = item.url
        return menuItem
    }

    @objc private func playClicked(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        onPlay?(url)
    }

    @objc private func showClickedInFinder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func copyClickedLink(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
    }

    @objc private func removeClicked(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        library.remove(url)
    }
}

final class LibraryCell: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("LibraryCell")
    static let thumbnailHeight: CGFloat = 117

    var onPlay: (() -> Void)?
    private let tile = TileView()
    private let thumbnail = ThumbnailView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let sourceLabel = NSTextField(labelWithString: "")
    private var shownURL: URL?

    override func loadView() {
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.92)
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.cell?.wraps = true
        titleLabel.cell?.truncatesLastVisibleLine = true
        titleLabel.preferredMaxLayoutWidth = LibraryView.itemSize.width - 4
        sourceLabel.font = .systemFont(ofSize: 11)
        sourceLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        sourceLabel.lineBreakMode = .byTruncatingTail
        tile.onPress = { [weak self] in self?.onPlay?() }
        let container = tile
        for subview in [thumbnail, titleLabel, sourceLabel] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
        }
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            thumbnail.topAnchor.constraint(equalTo: container.topAnchor),
            thumbnail.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            thumbnail.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            thumbnail.heightAnchor.constraint(equalToConstant: Self.thumbnailHeight),
            titleLabel.topAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: 7),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
            sourceLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            sourceLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            sourceLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
        ])
        view = container
    }

    func show(_ item: LibraryItem, menu: NSMenu) {
        shownURL = item.url
        tile.menu = menu
        tile.setAccessibilityLabel(item.displayTitle)
        titleLabel.stringValue = item.displayTitle
        titleLabel.toolTip = item.displayTitle
        sourceLabel.stringValue = [item.source, item.duration > 0 ? item.duration.clockText : nil]
            .compactMap { $0 }
            .joined(separator: "  ·  ")
        thumbnail.progress = item.progress
        thumbnail.image = nil
        thumbnail.placeholderSymbol = item.url.isFileURL ? "film" : "play.rectangle"
    }

    func showThumbnail(_ image: NSImage?, for url: URL) {
        guard url == shownURL else { return }
        thumbnail.image = image
    }
}

final class TileView: NSView {
    var onPress: (() -> Void)?

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }

    override func accessibilityPerformPress() -> Bool {
        guard let onPress else { return false }
        onPress()
        return true
    }

    override func accessibilityPerformShowMenu() -> Bool {
        guard let menu else { return false }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height), in: self)
        return true
    }
}

final class ThumbnailView: NSView {
    private let imageLayer = CALayer()
    private let placeholder = NSImageView()
    private let track = CALayer()
    private let fill = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.16, alpha: 1).cgColor
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        imageLayer.contentsGravity = .resizeAspectFill
        track.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        fill.backgroundColor = NSColor.white.cgColor
        layer?.addSublayer(imageLayer)
        layer?.addSublayer(track)
        layer?.addSublayer(fill)
        placeholder.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .light)
        placeholder.contentTintColor = NSColor.white.withAlphaComponent(0.3)
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("ThumbnailView is created in code only")
    }

    var image: NSImage? {
        didSet {
            imageLayer.contents = image
            placeholder.isHidden = image != nil
        }
    }

    var placeholderSymbol = "play.rectangle" {
        didSet { placeholder.image = NSImage(systemSymbolName: placeholderSymbol, accessibilityDescription: nil) }
    }

    var progress = 0.0 {
        didSet { needsLayout = true }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        let barHeight: CGFloat = 4
        track.frame = NSRect(x: 0, y: 0, width: bounds.width, height: barHeight)
        fill.frame = NSRect(x: 0, y: 0, width: bounds.width * progress, height: barHeight)
        track.isHidden = progress <= 0
        fill.isHidden = progress <= 0
        CATransaction.commit()
    }
}

@MainActor
final class Thumbnails {
    private let cache = NSCache<NSURL, NSImage>()
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 8 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024,
            directory: URL.cachesDirectory.appending(components: "Flick", "thumbnails")
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: configuration)
    }()

    func image(for item: LibraryItem, size: NSSize) async -> NSImage? {
        guard let source = item.url.isFileURL ? item.url : item.thumbnail else { return nil }
        if let cached = cache.object(forKey: source as NSURL) { return cached }
        let image = source.isFileURL ? await frame(of: source, size: size) : await download(source)
        if let image { cache.setObject(image, forKey: source as NSURL) }
        return image
    }

    private func frame(of file: URL, size: NSSize) async -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: file, size: size, scale: scale, representationTypes: .thumbnail)
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }

    private func download(_ url: URL) async -> NSImage? {
        guard let (data, _) = try? await session.data(from: url) else { return nil }
        return NSImage(data: data)
    }
}
