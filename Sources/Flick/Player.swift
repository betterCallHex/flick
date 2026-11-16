import CMpv
import Foundation

enum LoadFailure: Equatable {
    case unplayable
    case timedOut
}

struct PlaybackState: Equatable {
    var url: URL?
    var title: String?
    var thumbnail: URL?
    var isLoading = false
    var loadFailure: LoadFailure?
    var isBuffering = false
    var position = 0.0
    var duration = 0.0
    var isPaused = false
    var isAtEnd = false
    var volume = 100.0
    var isMuted = false
    var speed = 1.0
    var shape = VideoShape()
    var quality = VideoQuality()
    var subtitles = SubtitleState()

    static let observedProperties: [MpvProperty] = [
        MpvProperty("time-pos", MPV_FORMAT_DOUBLE),
        MpvProperty("duration", MPV_FORMAT_DOUBLE),
        MpvProperty("volume", MPV_FORMAT_DOUBLE),
        MpvProperty("speed", MPV_FORMAT_DOUBLE),
        MpvProperty("pause", MPV_FORMAT_FLAG),
        MpvProperty("eof-reached", MPV_FORMAT_FLAG),
        MpvProperty("mute", MPV_FORMAT_FLAG),
        MpvProperty("paused-for-cache", MPV_FORMAT_FLAG),
        MpvProperty("media-title", MPV_FORMAT_STRING),
    ] + VideoShape.observedProperties + SubtitleState.observedProperties

    func startingNewFile(_ url: URL) -> PlaybackState {
        var next = PlaybackState(url: url, isLoading: true, volume: volume, isMuted: isMuted)
        next.shape = shape
        next.quality = quality.forNextFile()
        next.subtitles = subtitles.forNextFile()
        return next
    }

    mutating func apply(_ value: MpvPropertyValue, to name: String) {
        switch (name, value) {
        case let ("time-pos", .double(seconds)): position = seconds
        case let ("duration", .double(seconds)): duration = seconds
        case let ("volume", .double(newVolume)): volume = newVolume
        case let ("speed", .double(newSpeed)): speed = newSpeed
        case let ("pause", .flag(newIsPaused)): isPaused = newIsPaused
        case let ("eof-reached", .flag(newIsAtEnd)): isAtEnd = newIsAtEnd
        case ("eof-reached", .unavailable): isAtEnd = false
        case let ("mute", .flag(newIsMuted)): isMuted = newIsMuted
        case let ("paused-for-cache", .flag(newIsBuffering)): isBuffering = newIsBuffering
        case let ("media-title", .string(newTitle)): title = newTitle
        default: subtitles.apply(value, to: name)
        }
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
    var webLoadTimeoutSeconds = 20.0
    let mpv: Mpv
    private var loadGeneration = 0

    static func options(
        watchLaterDirectory: URL,
        volume: Double,
        showsSubtitles: Bool = true,
        isMuted: Bool = false,
        subtitleLanguages: [String] = Locale.preferredLanguages
    ) -> [(name: String, value: String)] {
        [
            ("vo", "libmpv"),
            ("hwdec", "auto-safe"),
            ("keep-open", "yes"),
            ("idle", "yes"),
            ("osc", "no"),
            ("ytdl", "yes"),
            ("ytdl-raw-options", ytdlRawOptions(subtitleLanguages: subtitleLanguages, maxResolution: nil)),
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
            ("sub-visibility", showsSubtitles ? "yes" : "no"),
            ("resume-playback", "yes"),
            ("watch-later-dir", watchLaterDirectory.path),
            ("watch-later-options", "start,aid,sid,sub-delay,audio-delay"),
            ("volume-max", "100"),
            ("volume", String(volume)),
            ("mute", isMuted ? "yes" : "no"),
        ]
    }

    static func ytdlRawOptions(subtitleLanguages: [String], maxResolution: Int?) -> String {
        [WebSubtitles.ytdlRawOptions(languages: subtitleLanguages), VideoQuality.ytdlRawOptions(maxResolution: maxResolution)]
            .filter { !$0.isEmpty }
            .joined(separator: ",")
    }

    init(mpv: Mpv) {
        self.mpv = mpv
        mpv.onEvent = { [weak self] event in self?.handle(event) }
        PlaybackState.observedProperties.forEach(mpv.observe)
        mpv.addHook("on_load", priority: Self.afterYtdlHookPriority)
    }

    func open(_ url: URL) {
        saveResumePoint()
        state = state.startingNewFile(url)
        onStateChange?(state)
        load(url, retriesLeft: 1)
    }

    func limitResolution(to maxResolution: Int?) {
        mpv.set("ytdl-raw-options", Self.ytdlRawOptions(subtitleLanguages: Locale.preferredLanguages, maxResolution: maxResolution))
        state.quality.maxResolution = maxResolution
        guard let url = state.url, url.resolvesThroughYtdl else {
            onStateChange?(state)
            return
        }
        state.isLoading = true
        onStateChange?(state)
        load(url, retriesLeft: 1, startingAt: state.position)
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

    func toggleSubtitles(preferredLanguages: [String] = Locale.preferredLanguages) {
        guard !state.subtitles.isShowing else {
            mpv.set("sub-visibility", false)
            return
        }
        if !state.subtitles.tracks.contains(where: \.isSelected),
           let track = SubtitleTrack.preferred(among: state.subtitles.tracks, languages: preferredLanguages) {
            mpv.set("sid", String(track.id))
        }
        mpv.set("sub-visibility", true)
    }

    func keepSubtitlesAbove(bottomFraction: Double) {
        mpv.set("sub-pos", 100 * (1 - bottomFraction.clamped(to: 0...0.5)))
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
            fail(.unplayable)
        case let .propertyChanged(name, .integer) where VideoShape.isObserved(name):
            state.shape = VideoShape(reading: mpv) ?? state.shape
            onStateChange?(state)
        case let .propertyChanged(name, value):
            state.apply(value, to: name)
            onStateChange?(state)
        }
    }

    private func load(_ url: URL, retriesLeft: Int, startingAt start: Double? = nil) {
        loadGeneration += 1
        let generation = loadGeneration
        if let start {
            mpv.command("loadfile", url.mpvTarget, "replace", "-1", "start=\(start)")
        } else {
            mpv.command("loadfile", url.mpvTarget)
            mpv.set("pause", false)
        }
        guard url.resolvesThroughYtdl else { return }
        mpv.eventQueue.asyncAfter(deadline: .now() + webLoadTimeoutSeconds) { [weak self] in
            guard let self, generation == loadGeneration, state.isLoading else { return }
            guard retriesLeft > 0 else {
                mpv.command("stop")
                fail(.timedOut)
                return
            }
            load(url, retriesLeft: retriesLeft - 1, startingAt: start)
        }
    }

    private func fail(_ failure: LoadFailure) {
        state.isLoading = false
        state.loadFailure = failure
        onStateChange?(state)
    }

    private func applyYtdlInfo() {
        guard let url = state.url, url.resolvesThroughYtdl,
              let result = mpv.string("user-data/mpv/ytdl/json-subprocess-result"),
              let info = YtdlInfo(subprocessResult: result) else { return }
        state.quality.resolutions = info.resolutions
        state.thumbnail = info.thumbnail
        onStateChange?(state)
        guard let cookie = info.signedSegmentCookie else { return }
        mpv.command("change-list", "file-local-options/http-header-fields", "append", "Cookie: \(cookie)")
    }

}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
