import AppKit

final class PlayerChrome {
    static let idleSeconds = 2.0
    static let hudSeconds = 1.0
    static let margin: CGFloat = 16
    static let controlsHeight: CGFloat = 44

    let controls = ControlsView()
    var onIdle: (() -> Void)?
    private let hud = PillLabel(fontSize: 13)
    private let status = PillLabel(fontSize: 13)
    private let titleShade = TitleShade()
    private let player: Player
    private let playerView: PlayerView
    private var isVisible = true
    private var hideTimer: Timer?
    private var hudHideTimer: Timer?

    init(player: Player, playerView: PlayerView) {
        self.player = player
        self.playerView = playerView
        hud.alphaValue = 0
        status.isHidden = true
        controls.isHidden = true
        install()
    }

    func render(_ state: PlaybackState, isLibraryShowing: Bool) {
        controls.update(with: state)
        controls.isHidden = state.url == nil || state.isLoading || isLibraryShowing
        status.isHidden = !(state.isLoading || state.isBuffering) || state.url?.isFileURL == true
        status.text = state.isLoading ? "Loading \(state.url?.displayHost ?? "video")…" : "Buffering…"
    }

    func reveal() {
        setVisible(true)
        scheduleHide()
    }

    func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: Self.idleSeconds, repeats: false) { [weak self] _ in
            self?.onIdle?()
        }
    }

    func setVisible(_ isVisible: Bool) {
        guard isVisible != self.isVisible else { return }
        self.isVisible = isVisible
        positionSubtitles()
        let alpha: CGFloat = isVisible ? 1 : 0
        let window = playerView.window
        let isFullScreen = window?.styleMask.contains(.fullScreen) == true
        let titlebar = isFullScreen ? nil : window?.standardWindowButton(.closeButton)?.superview?.superview
        NSAnimationContext.runAnimationGroup { context in
            context.duration = isVisible ? 0.15 : 0.4
            controls.animator().alphaValue = alpha
            titleShade.animator().alphaValue = alpha
            titlebar?.animator().alphaValue = alpha
        }
    }

    func showHud(_ text: String, seconds: Double = PlayerChrome.hudSeconds) {
        hud.text = text
        hud.alphaValue = 1
        hudHideTimer?.invalidate()
        hudHideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            NSAnimationContext.runAnimationGroup { _ in self?.hud.animator().alphaValue = 0 }
        }
    }

    func positionSubtitles() {
        let height = playerView.bounds.height
        guard height > 0 else { return }
        let covered = isVisible ? Self.margin + Self.controlsHeight : 0
        player.keepSubtitlesAbove(bottomFraction: Double(covered / height))
    }

    private func install() {
        for overlay in [titleShade, controls, hud, status] as [NSView] {
            overlay.translatesAutoresizingMaskIntoConstraints = false
            playerView.addSubview(overlay)
        }
        let fullWidth = controls.widthAnchor.constraint(equalTo: playerView.widthAnchor, constant: -2 * Self.margin)
        fullWidth.priority = .dragThatCannotResizeWindow
        NSLayoutConstraint.activate([
            titleShade.topAnchor.constraint(equalTo: playerView.topAnchor),
            titleShade.leadingAnchor.constraint(equalTo: playerView.leadingAnchor),
            titleShade.trailingAnchor.constraint(equalTo: playerView.trailingAnchor),
            titleShade.heightAnchor.constraint(equalToConstant: 72),
            controls.centerXAnchor.constraint(equalTo: playerView.centerXAnchor),
            controls.bottomAnchor.constraint(equalTo: playerView.bottomAnchor, constant: -Self.margin),
            controls.heightAnchor.constraint(equalToConstant: Self.controlsHeight),
            controls.widthAnchor.constraint(lessThanOrEqualToConstant: 720),
            controls.widthAnchor.constraint(lessThanOrEqualTo: playerView.widthAnchor, constant: -2 * Self.margin),
            fullWidth,
            hud.centerXAnchor.constraint(equalTo: playerView.centerXAnchor),
            hud.topAnchor.constraint(equalTo: playerView.topAnchor, constant: 56),
            status.centerXAnchor.constraint(equalTo: playerView.centerXAnchor),
            status.centerYAnchor.constraint(equalTo: playerView.centerYAnchor),
        ])
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
