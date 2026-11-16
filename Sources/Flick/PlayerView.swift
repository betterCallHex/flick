import AppKit

final class PlayerView: NSView {
    weak var controller: PlayerWindowController?
    private(set) var isMouseInside = false
    private let videoLayer: VideoLayer
    private var mouseDownEvent: NSEvent?
    private var didDragWindow = false
    private var trackingArea: NSTrackingArea?
    private var scrollGesture = ScrollGesture()
    private var magnification = 0.0

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
        guard !didDragWindow, let mouseDownEvent, !isFullScreen else { return }
        didDragWindow = true
        window?.performDrag(with: mouseDownEvent)
    }

    override func mouseUp(with event: NSEvent) {
        guard !didDragWindow, event.clickCount == 1 else { return }
        controller?.handleClick()
    }

    override func scrollWheel(with event: NSEvent) {
        guard let controller, controller.hasFile else { return }
        switch scrollGesture.action(for: ScrollInput(event)) {
        case .none:
            return
        case let .seek(seconds):
            controller.seek(by: seconds)
        case let .changeVolume(delta):
            controller.changeVolume(by: delta)
        }
    }

    override func magnify(with event: NSEvent) {
        if event.phase.contains(.began) { magnification = 0 }
        magnification += event.magnification
        let threshold = 0.25
        guard (magnification > threshold && !isFullScreen) || (magnification < -threshold && isFullScreen) else { return }
        magnification = 0
        window?.toggleFullScreen(nil)
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

    private var isFullScreen: Bool { window?.styleMask.contains(.fullScreen) == true }
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
