import CMpv
import Foundation

struct PlaybackState: Equatable {
    var url: URL?
    var title: String?
    var isLoading = false
    var isBuffering = false
    var position = 0.0
    var duration = 0.0
    var isPaused = false
    var isAtEnd = false
    var volume = 100.0
    var isMuted = false
    var speed = 1.0
    var videoWidth: Int64 = 0
    var videoHeight: Int64 = 0
    var videoRotation: Int64 = 0
    var resolutions: [Int] = []
    var maxResolution: Int?

    var videoSize: CGSize? {
        guard videoWidth > 0, videoHeight > 0 else { return nil }
        let isSideways = videoRotation % 180 != 0
        let width = Double(isSideways ? videoHeight : videoWidth)
        let height = Double(isSideways ? videoWidth : videoHeight)
        return CGSize(width: width, height: height)
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
    static let afterYtdlHookPriority: Int32 = 20

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
            ("ytdl", "yes"),
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
        for name in ["pause", "eof-reached", "mute", "paused-for-cache"] {
            mpv.observe(name, format: MPV_FORMAT_FLAG)
        }
        for name in ["video-out-params/rotate", "video-out-params/dw", "video-out-params/dh"] {
            mpv.observe(name, format: MPV_FORMAT_INT64)
        }
        mpv.observe("media-title", format: MPV_FORMAT_STRING)
        mpv.addHook("on_load", priority: Self.afterYtdlHookPriority)
    }

    func open(_ url: URL) {
        saveResumePoint()
        state = PlaybackState(
            url: url,
            isLoading: true,
            volume: state.volume,
            isMuted: state.isMuted,
            videoWidth: state.videoWidth,
            videoHeight: state.videoHeight,
            videoRotation: state.videoRotation,
            maxResolution: state.maxResolution
        )
        onStateChange?(state)
        mpv.command("loadfile", url.mpvTarget)
        mpv.set("pause", false)
    }

    func limitResolution(to maxResolution: Int?) {
        mpv.set("ytdl-raw-options", VideoQuality.ytdlRawOptions(maxResolution: maxResolution))
        state.maxResolution = maxResolution
        guard let url = state.url, url.resolvesThroughYtdl else {
            onStateChange?(state)
            return
        }
        state.isLoading = true
        onStateChange?(state)
        mpv.command("loadfile", url.mpvTarget, "replace", "-1", "start=\(state.position)")
    }

    func saveResumePoint() {
        guard let url = state.url else { return }
        if state.isWorthResuming {
            mpv.command("write-watch-later-config")
        } else {
            mpv.command("delete-watch-later-config", url.mpvTarget)
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
        case .fileLoaded:
            state.isLoading = false
            onStateChange?(state)
        case let .hook(name, id):
            if name == "on_load" { applyYtdlInfo() }
            mpv.continueHook(id)
        case .loadFailed:
            state.isLoading = false
            onStateChange?(state)
            if let url = state.url { onLoadFailure?(url) }
        case let .propertyChanged(name, value):
            apply(value, to: name)
            onStateChange?(state)
        }
    }

    private func applyYtdlInfo() {
        guard let url = state.url, url.resolvesThroughYtdl,
              let result = mpv.string("user-data/mpv/ytdl/json-subprocess-result"),
              let info = YtdlInfo(subprocessResult: result) else { return }
        state.resolutions = info.resolutions
        onStateChange?(state)
        guard let cookie = info.signedSegmentCookie else { return }
        mpv.command("change-list", "file-local-options/http-header-fields", "append", "Cookie: \(cookie)")
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
        case let ("paused-for-cache", .flag(isBuffering)): state.isBuffering = isBuffering
        case let ("media-title", .string(title)): state.title = title
        case ("video-out-params/dw", .integer), ("video-out-params/dh", .integer), ("video-out-params/rotate", .integer):
            readDisplaySize()
        case ("eof-reached", .unavailable): state.isAtEnd = false
        default: break
        }
    }

    private func readDisplaySize() {
        guard
            let width = mpv.integer("video-out-params/dw"),
            let height = mpv.integer("video-out-params/dh"),
            let rotation = mpv.integer("video-out-params/rotate")
        else { return }
        state.videoWidth = width
        state.videoHeight = height
        state.videoRotation = rotation
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
