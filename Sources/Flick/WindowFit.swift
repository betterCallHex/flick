import AppKit

final class WindowFit {
    static let showFallbackSeconds = 0.75

    var onFirstShow: (() -> Void)?
    private weak var window: NSWindow?
    private var displayedVideoSize: CGSize?
    private var isWaitingToShow = false

    init(window: NSWindow) {
        self.window = window
    }

    func showOnceFitted() {
        guard let window else { return }
        isWaitingToShow = true
        window.alphaValue = 0
        window.center()
        window.orderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.showFallbackSeconds) { [weak self] in
            self?.showIfWaiting()
        }
    }

    func render(_ state: PlaybackState) {
        guard let size = state.shape.size, !size.hasSameShape(as: displayedVideoSize) else { return }
        displayedVideoSize = size
        fit(to: size)
    }

    func showIfWaiting() {
        guard isWaitingToShow, let window else { return }
        isWaitingToShow = false
        window.alphaValue = 1
        window.makeKeyAndOrderFront(nil)
        onFirstShow?()
    }

    private func fit(to videoSize: CGSize) {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        window.contentAspectRatio = videoSize
        guard !window.styleMask.contains(.fullScreen) else { return }
        let visible = screen.visibleFrame
        let center = isWaitingToShow ? CGPoint(x: visible.midX, y: visible.midY) : CGPoint(x: window.frame.midX, y: window.frame.midY)
        let frame = NSRect(fittingVideo: videoSize, centeredAt: center, within: visible)
        window.setFrame(frame, display: true, animate: !isWaitingToShow)
        showIfWaiting()
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
