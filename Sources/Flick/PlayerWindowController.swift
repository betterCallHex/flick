import AppKit

final class PlayerWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    static let messageSeconds = 4.0

    let player: Player
    let library: Library
    let lookup = WebVideoLookup.installed
    let libraryView: LibraryView
    let chrome: PlayerChrome
    private let playerView: PlayerView
    private let windowFit: WindowFit
    private var previousState = PlaybackState()
    private var phoneUpload: PhoneUpload?

    var onReveal: (() -> Void)?

    var hasFile: Bool { player.state.url != nil }

    init(player: Player, library: Library, videoLayer: VideoLayer) {
        self.player = player
        self.library = library
        libraryView = LibraryView(library: library)
        playerView = PlayerView(videoLayer: videoLayer)
        chrome = PlayerChrome(player: player, playerView: playerView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        windowFit = WindowFit(window: window)
        super.init(window: window)
        configure(window)
        bindChrome()
        installLibrary(in: playerView)
        bindPlayer()
    }

    required init?(coder: NSCoder) {
        fatalError("PlayerWindowController is created in code only")
    }

    func open(_ url: URL) {
        guard let window else { return }
        library.record(player.state)
        library.notePlayed(url)
        libraryView.isHidden = true
        guard url.libraryKey != player.state.url?.libraryKey || player.state.loadFailure != nil else {
            resumeFromLibrary()
            return
        }
        discardPhoneUpload()
        player.open(url)
        window.title = url.isFileURL ? url.lastPathComponent : url.displayHost
        window.representedURL = url.isFileURL ? url : nil
        if url.isFileURL { NSDocumentController.shared.noteNewRecentDocumentURL(url) }
        show(window)
    }

    func play(_ upload: PhoneUpload) {
        guard let window else { return }
        library.record(player.state)
        libraryView.isHidden = true
        discardPhoneUpload()
        phoneUpload = upload
        player.open(upload.file, streamingFrom: upload.streamTarget)
        window.title = upload.file.lastPathComponent
        window.representedURL = nil
        show(window)
    }

    func discardPhoneUpload() {
        phoneUpload?.discard()
        phoneUpload = nil
    }

    private func show(_ window: NSWindow) {
        window.standardWindowButton(.documentIconButton)?.image = NSApp.applicationIconImage
        guard !window.isVisible else {
            revealChrome()
            return
        }
        windowFit.showOnceFitted()
    }

    func revealChrome() {
        chrome.reveal()
    }

    func hideChromeIfIdle() {
        guard hasFile, !isLibraryShowing, !player.state.isPaused, !player.state.isAtEnd,
              !chrome.controls.isHovered, !chrome.controls.isScrubbing else { return }
        chrome.setVisible(false)
        if playerView.isMouseInside { NSCursor.setHiddenUntilMouseMoves(true) }
    }

    func handleClick() {
        guard hasFile else { return }
        player.togglePause()
        revealChrome()
    }

    func handleDoubleClick() {
        guard hasFile else { return }
        player.togglePause()
        window?.toggleFullScreen(nil)
    }

    func handleEscape() {
        guard !isLibraryShowing || !hasFile else { return resumeFromLibrary() }
        guard isFullScreen else { return }
        window?.toggleFullScreen(nil)
    }

    var isFullScreen: Bool { window?.styleMask.contains(.fullScreen) == true }

    func seek(by seconds: Double) {
        player.seek(by: seconds)
        revealChrome()
    }

    func changeVolume(by delta: Double) {
        player.changeVolume(by: delta)
        let volume = (player.state.volume + delta).clamped(to: 0...100)
        chrome.showHud("Volume \(Int(volume.rounded()))%")
    }

    @objc func togglePlayback(_ sender: Any?) {
        player.togglePause()
        revealChrome()
    }

    @objc func seekBySeconds(_ sender: NSMenuItem) {
        seek(by: Double(sender.tag))
    }

    @objc func stepForward(_ sender: Any?) {
        player.stepFrame(forward: true)
        revealChrome()
    }

    @objc func stepBackward(_ sender: Any?) {
        player.stepFrame(forward: false)
        revealChrome()
    }

    @objc func speedUp(_ sender: Any?) {
        changeSpeed(by: 0.25)
    }

    @objc func slowDown(_ sender: Any?) {
        changeSpeed(by: -0.25)
    }

    @objc func resetSpeed(_ sender: Any?) {
        player.resetSpeed()
        chrome.showHud("Speed 1×")
    }

    @objc func changeVolumeBySteps(_ sender: NSMenuItem) {
        changeVolume(by: Double(sender.tag))
    }

    @objc func toggleMute(_ sender: Any?) {
        player.toggleMute()
        chrome.showHud(player.state.isMuted ? "Sound On" : "Muted")
    }

    @objc func toggleSubtitles(_ sender: Any?) {
        let wasShowing = player.state.subtitles.isShowing
        player.toggleSubtitles()
        chrome.showHud(wasShowing ? "Subtitles Off" : "Subtitles On")
    }

    @objc func paste(_ sender: Any?) {
        guard let url = Self.playableURL(on: NSPasteboard.general) else {
            chrome.showHud("Copy a video link or file first", seconds: Self.messageSeconds)
            return
        }
        open(url)
    }

    static func playableURL(on pasteboard: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let file = pasteboard.readObjects(forClasses: [NSURL.self], options: options)?.first as? URL { return file }
        if let link = pasteboard.readObjects(forClasses: [NSURL.self])?.first as? URL, let web = URL(webVideoString: link.absoluteString) { return web }
        return pasteboard.string(forType: .string).flatMap(URL.init(webVideoString:))
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(paste(_:)), #selector(toggleLibrary(_:)), #selector(addFilesToLibrary(_:)), #selector(addLinkToLibrary(_:)):
            return true
        case #selector(toggleSubtitles(_:)):
            menuItem.state = player.state.subtitles.isShowing ? .on : .off
            return player.state.subtitles.hasSubtitles
        default:
            return hasFile && !isLibraryShowing
        }
    }

    func windowDidResize(_ notification: Notification) {
        chrome.positionSubtitles()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        chrome.controls.setFullScreen(true)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        chrome.controls.setFullScreen(false)
    }

    private func configure(_ window: NSWindow) {
        window.delegate = self
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.collectionBehavior = [.fullScreenPrimary]
        window.tabbingMode = .disallowed
        window.isRestorable = false
        window.minSize = NSSize(width: 360, height: 220)
        window.contentView = playerView
        window.initialFirstResponder = playerView
        playerView.controller = self
        windowFit.onFirstShow = { [weak self] in
            self?.onReveal?()
            NSApp.activate()
            self?.revealChrome()
        }
    }

    private func bindChrome() {
        chrome.onIdle = { [weak self] in self?.hideChromeIfIdle() }
        chrome.controls.onTogglePause = { [weak self] in self?.togglePlayback(nil) }
        chrome.controls.onToggleFullScreen = { [weak self] in self?.window?.toggleFullScreen(nil) }
        chrome.controls.onToggleSubtitles = { [weak self] in self?.toggleSubtitles(nil) }
        chrome.controls.onScrub = { [weak self] fraction, isFinished in self?.scrub(to: fraction, isFinished: isFinished) }
        chrome.controls.onPickResolution = { [weak self] resolution in self?.player.limitResolution(to: resolution) }
    }

    private func bindPlayer() {
        player.onStateChange = { [weak self] state in self?.render(state) }
    }

    private func render(_ state: PlaybackState) {
        chrome.render(state, isLibraryShowing: isLibraryShowing)
        if let url = state.url, !url.isFileURL, let title = state.title, !state.isLoading { window?.title = title }
        if state.hasNewsForLibrary(since: previousState) { library.record(state) }
        if let failure = state.loadFailure, previousState.loadFailure == nil, let url = state.url {
            showLoadFailure(failure, for: url)
        }
        windowFit.render(state)
        let isPlaying = !state.isPaused && !state.isAtEnd
        let wasPlaying = !previousState.isPaused && !previousState.isAtEnd
        if isPlaying != wasPlaying {
            isPlaying ? chrome.scheduleHide() : chrome.setVisible(true)
        }
        previousState = state
    }

    private func showLoadFailure(_ failure: LoadFailure, for url: URL) {
        windowFit.showIfWaiting()
        chrome.showHud(Self.failureMessage(failure, for: url), seconds: Self.messageSeconds)
    }

    private static func failureMessage(_ failure: LoadFailure, for url: URL) -> String {
        if failure == .timedOut { return "\(url.displayHost) isn’t responding. Paste the link again to retry." }
        if url.isFileURL { return "Can’t play “\(url.lastPathComponent)”" }
        if url.resolvesThroughYtdl && !HomebrewTools.hasYtdlp { return "Install yt-dlp to play web videos: brew install yt-dlp" }
        return "Can’t play this link. It may be private or unsupported."
    }

    private func scrub(to fraction: Double, isFinished: Bool) {
        player.seek(to: fraction * player.state.duration, precise: isFinished)
        revealChrome()
    }

    private func changeSpeed(by delta: Double) {
        player.changeSpeed(by: delta)
        let speed = (player.state.speed + delta).clamped(to: Player.speedRange)
        chrome.showHud("Speed \(speed.formatted(.number.precision(.fractionLength(0...2))))×")
    }
}
