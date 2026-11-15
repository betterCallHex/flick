import AppKit

final class PlayerWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    static let chromeIdleSeconds = 2.0
    static let hudSeconds = 1.0
    static let showFallbackSeconds = 0.75
    static let messageSeconds = 4.0

    private let player: Player
    private let playerView: PlayerView
    private let controls = ControlsView()
    private let hud = PillLabel(fontSize: 13)
    private let status = PillLabel(fontSize: 13)
    private let titleShade = TitleShade()
    private let emptyState = EmptyStateView()
    private var previousState = PlaybackState()
    private var displayedVideoSize: CGSize?
    private var isWaitingToShow = false
    private var isChromeVisible = true
    private var chromeHideTimer: Timer?
    private var hudHideTimer: Timer?
    private var scrollGesture = ScrollGesture()
    private var magnification = 0.0

    var onReveal: (() -> Void)?

    var hasFile: Bool { player.state.url != nil }

    init(player: Player, videoLayer: VideoLayer) {
        self.player = player
        playerView = PlayerView(videoLayer: videoLayer)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        configure(window)
        layoutOverlays()
        bindPlayer()
        controls.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("PlayerWindowController is created in code only")
    }

    func open(_ url: URL) {
        guard let window else { return }
        player.open(url)
        window.title = url.isFileURL ? url.lastPathComponent : url.displayHost
        window.representedURL = url.isFileURL ? url : nil
        window.standardWindowButton(.documentIconButton)?.image = NSApp.applicationIconImage
        emptyState.isHidden = true
        displayedVideoSize = nil
        if url.isFileURL { NSDocumentController.shared.noteNewRecentDocumentURL(url) }
        guard !window.isVisible else {
            revealChrome()
            return
        }
        isWaitingToShow = true
        window.alphaValue = 0
        window.center()
        window.orderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.showFallbackSeconds) { [weak self] in
            self?.showWindowIfWaiting()
        }
    }

    func showEmptyState() {
        emptyState.isHidden = false
        window?.setContentSize(NSSize(width: 640, height: 400))
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func revealChrome() {
        setChromeVisible(true)
        scheduleChromeHide()
    }

    func hideChromeIfIdle() {
        guard hasFile, !player.state.isPaused, !player.state.isAtEnd, !controls.isHovered, !controls.isScrubbing else { return }
        setChromeVisible(false)
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

    func handleScroll(_ event: NSEvent) {
        guard hasFile else { return }
        switch scrollGesture.action(for: ScrollInput(event)) {
        case .none:
            return
        case let .seek(seconds):
            player.seek(by: seconds)
            revealChrome()
        case let .changeVolume(delta):
            changeVolume(by: delta)
        }
    }

    func handleMagnify(_ event: NSEvent) {
        if event.phase.contains(.began) { magnification = 0 }
        magnification += event.magnification
        let threshold = 0.25
        let isFullScreen = self.isFullScreen
        guard (magnification > threshold && !isFullScreen) || (magnification < -threshold && isFullScreen) else { return }
        magnification = 0
        window?.toggleFullScreen(nil)
    }

    func handleEscape() {
        guard isFullScreen else { return }
        window?.toggleFullScreen(nil)
    }

    var isFullScreen: Bool { window?.styleMask.contains(.fullScreen) == true }

    @objc func togglePlayback(_ sender: Any?) {
        player.togglePause()
        revealChrome()
    }

    @objc func seekBySeconds(_ sender: NSMenuItem) {
        player.seek(by: Double(sender.tag))
        revealChrome()
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
        showHud("Speed 1×")
    }

    @objc func changeVolumeBySteps(_ sender: NSMenuItem) {
        changeVolume(by: Double(sender.tag))
    }

    @objc func toggleMute(_ sender: Any?) {
        player.toggleMute()
        showHud(player.state.isMuted ? "Sound On" : "Muted")
    }

    @objc func paste(_ sender: Any?) {
        guard let url = Self.playableURL(on: NSPasteboard.general) else {
            showHud("Copy a video link or file first", seconds: Self.messageSeconds)
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
        menuItem.action == #selector(paste(_:)) || hasFile
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        controls.setFullScreen(true)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        controls.setFullScreen(false)
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
    }

    private func layoutOverlays() {
        controls.onTogglePause = { [weak self] in self?.togglePlayback(nil) }
        controls.onToggleFullScreen = { [weak self] in self?.window?.toggleFullScreen(nil) }
        controls.onScrub = { [weak self] fraction, isFinished in self?.scrub(to: fraction, isFinished: isFinished) }
        controls.onPickResolution = { [weak self] resolution in self?.player.limitResolution(to: resolution) }
        hud.alphaValue = 0
        status.isHidden = true
        for overlay in [titleShade, emptyState, controls, hud, status] as [NSView] {
            overlay.translatesAutoresizingMaskIntoConstraints = false
            playerView.addSubview(overlay)
        }
        let sideMargin: CGFloat = 16
        let fullWidth = controls.widthAnchor.constraint(equalTo: playerView.widthAnchor, constant: -2 * sideMargin)
        fullWidth.priority = .dragThatCannotResizeWindow
        NSLayoutConstraint.activate([
            titleShade.topAnchor.constraint(equalTo: playerView.topAnchor),
            titleShade.leadingAnchor.constraint(equalTo: playerView.leadingAnchor),
            titleShade.trailingAnchor.constraint(equalTo: playerView.trailingAnchor),
            titleShade.heightAnchor.constraint(equalToConstant: 72),
            emptyState.centerXAnchor.constraint(equalTo: playerView.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: playerView.centerYAnchor),
            controls.centerXAnchor.constraint(equalTo: playerView.centerXAnchor),
            controls.bottomAnchor.constraint(equalTo: playerView.bottomAnchor, constant: -sideMargin),
            controls.heightAnchor.constraint(equalToConstant: 44),
            controls.widthAnchor.constraint(lessThanOrEqualToConstant: 720),
            controls.widthAnchor.constraint(lessThanOrEqualTo: playerView.widthAnchor, constant: -2 * sideMargin),
            fullWidth,
            hud.centerXAnchor.constraint(equalTo: playerView.centerXAnchor),
            hud.topAnchor.constraint(equalTo: playerView.topAnchor, constant: 56),
            status.centerXAnchor.constraint(equalTo: playerView.centerXAnchor),
            status.centerYAnchor.constraint(equalTo: playerView.centerYAnchor),
        ])
        emptyState.onOpen = { NSApp.sendAction(#selector(AppDelegate.openDocument(_:)), to: nil, from: nil) }
    }

    private func bindPlayer() {
        player.onStateChange = { [weak self] state in self?.render(state) }
        player.onLoadFailure = { [weak self] url in self?.showLoadFailure(for: url) }
    }

    private func render(_ state: PlaybackState) {
        controls.update(with: state)
        renderStatus(of: state)
        if let size = state.videoSize, !size.hasSameShape(as: displayedVideoSize) {
            displayedVideoSize = size
            fit(to: size)
        }
        let isPlaying = !state.isPaused && !state.isAtEnd
        let wasPlaying = !previousState.isPaused && !previousState.isAtEnd
        if isPlaying != wasPlaying {
            isPlaying ? scheduleChromeHide() : setChromeVisible(true)
        }
        previousState = state
    }

    private func renderStatus(of state: PlaybackState) {
        controls.isHidden = state.url == nil || state.isLoading
        if let url = state.url, !url.isFileURL, let title = state.title, !state.isLoading { window?.title = title }
        status.isHidden = !(state.isLoading || state.isBuffering) || state.url?.isFileURL == true
        status.text = state.isLoading ? "Loading \(state.url?.displayHost ?? "video")…" : "Buffering…"
    }

    private func fit(to videoSize: CGSize) {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        window.contentAspectRatio = videoSize
        guard !isFullScreen else { return }
        let visible = screen.visibleFrame
        let center = isWaitingToShow ? CGPoint(x: visible.midX, y: visible.midY) : CGPoint(x: window.frame.midX, y: window.frame.midY)
        let frame = NSRect(fittingVideo: videoSize, centeredAt: center, within: visible)
        window.setFrame(frame, display: true, animate: !isWaitingToShow)
        showWindowIfWaiting()
    }

    private func showWindowIfWaiting() {
        guard isWaitingToShow, let window else { return }
        isWaitingToShow = false
        window.alphaValue = 1
        window.makeKeyAndOrderFront(nil)
        onReveal?()
        NSApp.activate()
        revealChrome()
    }

    private func showLoadFailure(for url: URL) {
        showWindowIfWaiting()
        showHud(Self.failureMessage(for: url), seconds: Self.messageSeconds)
    }

    private static func failureMessage(for url: URL) -> String {
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
        showHud("Speed \(speed.formatted(.number.precision(.fractionLength(0...2))))×")
    }

    private func changeVolume(by delta: Double) {
        player.changeVolume(by: delta)
        let volume = (player.state.volume + delta).clamped(to: 0...100)
        showHud("Volume \(Int(volume.rounded()))%")
    }

    private func showHud(_ text: String, seconds: Double = PlayerWindowController.hudSeconds) {
        hud.text = text
        hud.alphaValue = 1
        hudHideTimer?.invalidate()
        hudHideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            NSAnimationContext.runAnimationGroup { _ in self?.hud.animator().alphaValue = 0 }
        }
    }

    private func scheduleChromeHide() {
        chromeHideTimer?.invalidate()
        chromeHideTimer = Timer.scheduledTimer(withTimeInterval: Self.chromeIdleSeconds, repeats: false) { [weak self] _ in
            self?.hideChromeIfIdle()
        }
    }

    private func setChromeVisible(_ isVisible: Bool) {
        guard isVisible != isChromeVisible else { return }
        isChromeVisible = isVisible
        let alpha: CGFloat = isVisible ? 1 : 0
        let titlebar = isFullScreen ? nil : window?.standardWindowButton(.closeButton)?.superview?.superview
        NSAnimationContext.runAnimationGroup { context in
            context.duration = isVisible ? 0.15 : 0.4
            controls.animator().alphaValue = alpha
            titleShade.animator().alphaValue = alpha
            titlebar?.animator().alphaValue = alpha
        }
    }
}

final class PlayerView: NSView {
    weak var controller: PlayerWindowController?
    private(set) var isMouseInside = false
    private let videoLayer: VideoLayer
    private var mouseDownEvent: NSEvent?
    private var didDragWindow = false
    private var trackingArea: NSTrackingArea?

    init(videoLayer: VideoLayer) {
        self.videoLayer = videoLayer
        super.init(frame: .zero)
        wantsLayer = true
        registerForDraggedTypes([.fileURL, .URL, .string])
    }

    required init?(coder: NSCoder) {
        fatalError("PlayerView is created in code only")
    }

    override func makeBackingLayer() -> CALayer {
        videoLayer
    }

    override var acceptsFirstResponder: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        videoLayer.requestDraw()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        videoLayer.contentsScale = window?.backingScaleFactor ?? 2
        videoLayer.requestDraw()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let area = NSTrackingArea(rect: .zero, options: options, owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
        controller?.revealChrome()
    }

    override func mouseMoved(with event: NSEvent) {
        controller?.revealChrome()
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        controller?.hideChromeIfIdle()
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        didDragWindow = false
        if event.clickCount == 2 { controller?.handleDoubleClick() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didDragWindow, let mouseDownEvent, controller?.isFullScreen == false else { return }
        didDragWindow = true
        window?.performDrag(with: mouseDownEvent)
    }

    override func mouseUp(with event: NSEvent) {
        guard !didDragWindow, event.clickCount == 1 else { return }
        controller?.handleClick()
    }

    override func scrollWheel(with event: NSEvent) {
        controller?.handleScroll(event)
    }

    override func magnify(with event: NSEvent) {
        controller?.handleMagnify(event)
    }

    override func keyDown(with event: NSEvent) {
        let escapeKeyCode: UInt16 = 53
        guard event.keyCode == escapeKeyCode else { return super.keyDown(with: event) }
        controller?.handleEscape()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        PlayerWindowController.playableURL(on: sender.draggingPasteboard) == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = PlayerWindowController.playableURL(on: sender.draggingPasteboard) else { return false }
        controller?.open(url)
        return true
    }
}

final class TitleShade: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("TitleShade is created in code only")
    }

    override func makeBackingLayer() -> CALayer {
        let gradient = CAGradientLayer()
        gradient.colors = [NSColor.black.withAlphaComponent(0.55).cgColor, NSColor.clear.cgColor]
        gradient.startPoint = CGPoint(x: 0.5, y: 1)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        return gradient
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class EmptyStateView: NSStackView {
    var onOpen: (() -> Void)?

    init() {
        super.init(frame: .zero)
        let icon = NSImageView(image: NSImage(systemSymbolName: "play.rectangle", accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 44, weight: .light)
        icon.contentTintColor = NSColor.white.withAlphaComponent(0.35)
        let title = NSTextField(labelWithString: "Drop a video or link here")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = NSColor.white.withAlphaComponent(0.9)
        let hint = NSTextField(labelWithString: "⌘O to choose a file  ·  ⌘V to paste a YouTube, Loom or other link")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = NSColor.white.withAlphaComponent(0.5)
        let openButton = NSButton(title: "Open…", target: self, action: #selector(openPressed))
        openButton.bezelStyle = .push
        orientation = .vertical
        spacing = 8
        setViews([icon, title, hint, openButton], in: .center)
        setCustomSpacing(14, after: icon)
        setCustomSpacing(16, after: hint)
    }

    required init?(coder: NSCoder) {
        fatalError("EmptyStateView is created in code only")
    }

    @objc private func openPressed() {
        onOpen?()
    }
}

extension ScrollInput {
    init(_ event: NSEvent) {
        self.init(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            isPrecise: event.hasPreciseScrollingDeltas,
            isNaturalScrolling: event.isDirectionInvertedFromDevice,
            phase: Self.phase(of: event)
        )
    }

    private static func phase(of event: NSEvent) -> Phase {
        if !event.momentumPhase.isEmpty { return .momentum }
        if event.phase.isEmpty { return .wheel }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) { return .began }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) { return .ended }
        return .changed
    }
}

extension CGSize {
    func hasSameShape(as other: CGSize?) -> Bool {
        guard let other, other.height > 0, height > 0 else { return false }
        let tolerance = 0.01
        return abs(width / height - other.width / other.height) <= tolerance * (other.width / other.height)
    }
}

extension NSRect {
    init(fittingVideo videoSize: CGSize, centeredAt center: CGPoint, within visible: NSRect) {
        let screenShare = 0.85
        let minimumWidth = 480.0
        let maximum = CGSize(width: visible.width * screenShare, height: visible.height * screenShare)
        let growTiny = max(1, minimumWidth / videoSize.width)
        let scale = min(growTiny, maximum.width / videoSize.width, maximum.height / videoSize.height)
        let size = CGSize(width: (videoSize.width * scale).rounded(), height: (videoSize.height * scale).rounded())
        let x = (center.x - size.width / 2).clamped(to: visible.minX...max(visible.minX, visible.maxX - size.width))
        let y = (center.y - size.height / 2).clamped(to: visible.minY...max(visible.minY, visible.maxY - size.height))
        self.init(origin: CGPoint(x: x.rounded(), y: y.rounded()), size: size)
    }
}
