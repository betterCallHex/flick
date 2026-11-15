import AppKit

final class ControlsView: NSView {
    var onTogglePause: (() -> Void)?
    var onToggleFullScreen: (() -> Void)?
    var onScrub: ((_ fraction: Double, _ isFinished: Bool) -> Void)?
    private(set) var isHovered = false
    var isScrubbing: Bool { scrubber.isDragging }

    private let background = NSVisualEffectView()
    private let playButton = ControlsView.makeButton()
    private let fullScreenButton = ControlsView.makeButton()
    private let elapsedLabel = ControlsView.makeTimeLabel()
    private let remainingLabel = ControlsView.makeTimeLabel()
    private let scrubber = Scrubber()
    private let hoverBubble = PillLabel(fontSize: 11)
    private var duration = 0.0
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        background.material = .hudWindow
        background.blendingMode = .withinWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true
        playButton.target = self
        playButton.action = #selector(playPressed)
        fullScreenButton.target = self
        fullScreenButton.action = #selector(fullScreenPressed)
        scrubber.onScrub = { [weak self] fraction, isFinished in self?.onScrub?(fraction, isFinished) }
        scrubber.onHover = { [weak self] fraction in self?.showHoverTime(at: fraction) }
        hoverBubble.alphaValue = 0
        layoutContent()
        update(with: PlaybackState())
        setFullScreen(false)
    }

    required init?(coder: NSCoder) {
        fatalError("ControlsView is created in code only")
    }

    func update(with state: PlaybackState) {
        duration = state.duration
        let showsPlay = state.isPaused || state.isAtEnd
        playButton.image = Self.symbol(showsPlay ? "play.fill" : "pause.fill", label: showsPlay ? "Play" : "Pause")
        elapsedLabel.stringValue = state.position.clockText
        let remaining = max(state.duration.rounded(.down) - state.position.rounded(.down), 0)
        remainingLabel.stringValue = "-" + remaining.clockText
        scrubber.setProgress(state.progress)
    }

    func setFullScreen(_ isFullScreen: Bool) {
        let name = isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
        fullScreenButton.image = Self.symbol(name, label: isFullScreen ? "Exit Full Screen" : "Enter Full Screen")
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {}

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    @objc private func playPressed() {
        onTogglePause?()
    }

    @objc private func fullScreenPressed() {
        onToggleFullScreen?()
    }

    private func layoutContent() {
        let row = NSStackView(views: [playButton, elapsedLabel, scrubber, remainingLabel, fullScreenButton])
        row.orientation = .horizontal
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        row.setCustomSpacing(14, after: playButton)
        for subview in [background, row, hoverBubble] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        scrubber.setContentHuggingPriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            hoverBubble.bottomAnchor.constraint(equalTo: topAnchor, constant: -8),
        ])
        hoverBubble.pinCenterX(to: 0)
    }

    private func showHoverTime(at fraction: Double?) {
        guard let fraction, duration > 0 else {
            hoverBubble.animator().alphaValue = 0
            return
        }
        hoverBubble.text = (fraction * duration).clockText
        let scrubberFrame = scrubber.convert(scrubber.bounds, to: self)
        let centerX = scrubberFrame.minX + Scrubber.inset + fraction * (scrubberFrame.width - 2 * Scrubber.inset)
        hoverBubble.pinCenterX(to: centerX)
        hoverBubble.alphaValue = 1
    }

    private static func makeButton() -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.contentTintColor = .white
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }

    private static func makeTimeLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "0:00")
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.85)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }

    private static func symbol(_ name: String, label: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: label)
    }
}

final class Scrubber: NSView {
    static let inset: CGFloat = 6

    var onScrub: ((_ fraction: Double, _ isFinished: Bool) -> Void)?
    var onHover: ((Double?) -> Void)?
    private(set) var isDragging = false
    private var progress = 0.0
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 24) }

    override var mouseDownCanMoveWindow: Bool { false }

    func setProgress(_ progress: Double) {
        guard !isDragging, progress != self.progress else { return }
        self.progress = progress
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let isActive = isHovered || isDragging
        let thickness: CGFloat = isActive ? 6 : 4
        let track = NSRect(x: Self.inset, y: bounds.midY - thickness / 2, width: bounds.width - 2 * Self.inset, height: thickness)
        NSColor.white.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: track, xRadius: thickness / 2, yRadius: thickness / 2).fill()
        var played = track
        played.size.width = track.width * progress
        NSColor.white.setFill()
        NSBezierPath(roundedRect: played, xRadius: thickness / 2, yRadius: thickness / 2).fill()
        guard isActive else { return }
        let knobDiameter: CGFloat = 12
        let knob = NSRect(x: played.maxX - knobDiameter / 2, y: bounds.midY - knobDiameter / 2, width: knobDiameter, height: knobDiameter)
        NSBezierPath(ovalIn: knob).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect]
        let area = NSTrackingArea(rect: .zero, options: options, owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
        onHover?(fraction(of: event))
    }

    override func mouseMoved(with event: NSEvent) {
        onHover?(fraction(of: event))
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
        if !isDragging { onHover?(nil) }
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        scrub(to: event, isFinished: false)
    }

    override func mouseDragged(with event: NSEvent) {
        scrub(to: event, isFinished: false)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        scrub(to: event, isFinished: true)
        if !isHovered { onHover?(nil) }
    }

    private func scrub(to event: NSEvent, isFinished: Bool) {
        let fraction = fraction(of: event)
        progress = fraction
        needsDisplay = true
        onHover?(fraction)
        onScrub?(fraction, isFinished)
    }

    private func fraction(of event: NSEvent) -> Double {
        let x = convert(event.locationInWindow, from: nil).x
        return Double((x - Self.inset) / (bounds.width - 2 * Self.inset)).clamped(to: 0...1)
    }
}

final class PillLabel: NSView {
    private let label = NSTextField(labelWithString: "")
    private var centerXConstraint: NSLayoutConstraint?

    init(fontSize: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        label.font = .monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: fontSize * 0.8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -fontSize * 0.8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: fontSize * 0.4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -fontSize * 0.4),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("PillLabel is created in code only")
    }

    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func pinCenterX(to x: CGFloat) {
        guard let superview else { return }
        if centerXConstraint == nil {
            centerXConstraint = centerXAnchor.constraint(equalTo: superview.leadingAnchor)
            centerXConstraint?.isActive = true
        }
        centerXConstraint?.constant = x
    }
}

extension TimeInterval {
    var clockText: String {
        let totalSeconds = isFinite ? max(Int(rounded(.down)), 0) : 0
        let hours = totalSeconds / 3600
        let minutes = totalSeconds % 3600 / 60
        let seconds = totalSeconds % 60
        guard hours > 0 else { return String(format: "%d:%02d", minutes, seconds) }
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
}
