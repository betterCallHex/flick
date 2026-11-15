import CMpv
import Foundation

struct PlaybackState: Equatable {
    var url: URL?
    var position = 0.0
    var duration = 0.0
    var isPaused = false
    var isAtEnd = false
    var volume = 100.0
    var isMuted = false
    var speed = 1.0
    var videoWidth: Int64 = 0
    var videoHeight: Int64 = 0

    var videoSize: CGSize? {
        guard videoWidth > 0, videoHeight > 0 else { return nil }
        return CGSize(width: Double(videoWidth), height: Double(videoHeight))
    }

    var progress: Double {
        duration > 0 ? min(max(position / duration, 0), 1) : 0
    }

    var isWorthResuming: Bool {
        let resumeFloorSeconds = 5.0
        let creditsMarginSeconds = 5.0
        guard !isAtEnd, position >= resumeFloorSeconds else { return false }
        return duration <= 0 || position < duration - creditsMarginSeconds
    }
}

final class Player {
    static let speedRange = 0.25...4.0

    private(set) var state = PlaybackState()
    var onStateChange: ((PlaybackState) -> Void)?
    var onLoadFailure: ((URL) -> Void)?
    let mpv: Mpv

    static func options(watchLaterDirectory: URL, volume: Double) -> [(name: String, value: String)] {
        [
            ("vo", "libmpv"),
            ("hwdec", "auto-safe"),
            ("keep-open", "yes"),
            ("idle", "yes"),
            ("osc", "no"),
            ("ytdl", "no"),
            ("load-scripts", "no"),
            ("load-stats-overlay", "no"),
            ("load-console", "no"),
            ("load-context-menu", "no"),
            ("load-select", "no"),
            ("load-positioning", "no"),
            ("load-commands", "no"),
            ("load-auto-profiles", "no"),
            ("input-default-bindings", "no"),
            ("input-vo-keyboard", "no"),
            ("sub-auto", "fuzzy"),
            ("resume-playback", "yes"),
            ("watch-later-dir", watchLaterDirectory.path),
            ("watch-later-options", "start,aid,sid,sub-delay,audio-delay"),
            ("volume-max", "100"),
            ("volume", String(volume)),
        ]
    }

    init(mpv: Mpv) {
        self.mpv = mpv
        mpv.onEvent = { [weak self] event in self?.handle(event) }
        for name in ["time-pos", "duration", "volume", "speed"] {
            mpv.observe(name, format: MPV_FORMAT_DOUBLE)
        }
        for name in ["pause", "eof-reached", "mute"] {
            mpv.observe(name, format: MPV_FORMAT_FLAG)
        }
        for name in ["dwidth", "dheight"] {
            mpv.observe(name, format: MPV_FORMAT_INT64)
        }
    }

    func open(_ url: URL) {
        saveResumePoint()
        state = PlaybackState(url: url, volume: state.volume, isMuted: state.isMuted)
        onStateChange?(state)
        mpv.command("loadfile", url.path)
        mpv.set("pause", false)
    }

    func saveResumePoint() {
        guard let url = state.url else { return }
        if state.isWorthResuming {
            mpv.command("write-watch-later-config")
        } else {
            mpv.command("delete-watch-later-config", url.path)
        }
    }

    func togglePause() {
        guard !state.isAtEnd else {
            seek(to: 0, precise: true)
            mpv.set("pause", false)
            return
        }
        mpv.set("pause", !state.isPaused)
    }

    func seek(by seconds: Double) {
        mpv.command("seek", String(seconds), "relative+exact")
    }

    func seek(to seconds: Double, precise: Bool) {
        mpv.command("seek", String(seconds), precise ? "absolute+exact" : "absolute+keyframes")
    }

    func stepFrame(forward: Bool) {
        mpv.command(forward ? "frame-step" : "frame-back-step")
    }

    func changeSpeed(by delta: Double) {
        let speed = (state.speed + delta).clamped(to: Self.speedRange)
        mpv.set("speed", speed)
    }

    func resetSpeed() {
        mpv.set("speed", 1.0)
    }

    func changeVolume(by delta: Double) {
        mpv.set("volume", (state.volume + delta).clamped(to: 0...100))
        if delta > 0, state.isMuted { mpv.set("mute", false) }
    }

    func toggleMute() {
        mpv.set("mute", !state.isMuted)
    }

    private func handle(_ event: MpvEvent) {
        switch event {
        case .loadFailed:
            if let url = state.url { onLoadFailure?(url) }
        case let .propertyChanged(name, value):
            apply(value, to: name)
            onStateChange?(state)
        }
    }

    private func apply(_ value: MpvPropertyValue, to name: String) {
        switch (name, value) {
        case let ("time-pos", .double(seconds)): state.position = seconds
        case let ("duration", .double(seconds)): state.duration = seconds
        case let ("volume", .double(volume)): state.volume = volume
        case let ("speed", .double(speed)): state.speed = speed
        case let ("pause", .flag(isPaused)): state.isPaused = isPaused
        case let ("eof-reached", .flag(isAtEnd)): state.isAtEnd = isAtEnd
        case let ("mute", .flag(isMuted)): state.isMuted = isMuted
        case let ("dwidth", .integer(width)): state.videoWidth = width
        case let ("dheight", .integer(height)): state.videoHeight = height
        case ("eof-reached", .unavailable): state.isAtEnd = false
        default: break
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
