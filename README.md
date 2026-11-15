<img src="docs/icon.png" width="128" alt="Flick icon">

# Flick

A fast, quiet video player for macOS. Native AppKit UI on top of [libmpv](https://mpv.io), so it plays everything mpv plays (MP4, MKV, WebM, HEVC, AV1, VP9…) with hardware decoding, plus links from YouTube, Loom, Vimeo and the other sites [yt-dlp](https://github.com/yt-dlp/yt-dlp) supports.

## Speed

`make bench` launches the app on 1080p H.264, 4K HEVC (MKV) and 720p VP9 (WebM) files and measures the time from `open` to the first frame visible on screen. The check fails above 1000 ms.

Measured on an M4 MacBook Air, macOS 27:

| File | Launch → visible first frame |
|---|---|
| 1080p H.264 MP4 | 391–426 ms |
| 4K HEVC MKV | 408–450 ms |
| 720p VP9 WebM | 364–431 ms |
| First launch of a freshly built app (one-time signature check) | 655–1070 ms |

## Build

Requires the Xcode command line tools, Homebrew mpv, and yt-dlp for web links:

```sh
brew install mpv pkg-config yt-dlp
make app        # build/Flick.app
make test       # unit + headless mpv integration tests
make test-web   # also plays real YouTube and Loom links (needs network)
make bench      # launch-time budget check
make check      # test + bench
make install    # copy to ~/Applications
make icon       # regenerate Resources/AppIcon.icns from scripts/make-icon.swift
```

The app icon is 32×32 pixel art in four muted colours, drawn in code (`scripts/make-icon.swift`), clipped to Apple's icon shape so macOS shows it full size. To use other artwork, replace `Resources/AppIcon.icns`.

To make Flick the default player: Finder → select a video → Get Info → Open with: Flick → Change All.

## Web videos

Paste a link with ⌘V anywhere in the window, use File → Open URL… (⇧⌘O), or drag a link from the browser onto the window. Public YouTube, Loom, Vimeo, Google Drive and Dropbox links work, and so does any direct `.mp4`/`.m3u8` URL.

Links to pages go through yt-dlp first (`ytdl://`). Direct media links skip it. A YouTube link takes 4–6 s to start, almost all of it yt-dlp talking to YouTube. Loom signs its stream segments with a CloudFront policy that mpv's yt-dlp bridge does not forward, so Flick hooks `on_load` and passes the signature as CloudFront cookies (`SignedSegments` in `WebVideo.swift`).

Private videos (a Loom or Drive file that needs you signed in) are not supported yet.

## Controls

| | |
|---|---|
| Space, click | Play / pause |
| Double-click, F, pinch out | Full screen (Esc or pinch in to leave) |
| ← / → | Back / forward 5 s |
| ⇧← / ⇧→ | Back / forward 30 s |
| ⌥← / ⌥→ | Back / forward 1 s |
| , / . | Previous / next frame |
| ↑ / ↓ | Volume |
| M | Mute |
| [ / ] / \\ | Slower / faster / normal speed |
| Two-finger swipe left / right | Seek |
| Two-finger swipe up / down | Volume |
| Drag the window anywhere | Move it |
| Drop a file on the window or Dock icon | Open it |
| ⌘V, drop a link | Play a web video |
| ⇧⌘O | Open URL… |

Controls, title bar and cursor fade out after 2 s of playback without mouse movement. Every file resumes where you left it, unless you were in its first or last 5 seconds. Subtitles next to the video (fuzzy name match) load automatically.

## Layout

- `Sources/Flick/Mpv.swift`: thin libmpv client wrapper (options, commands, properties, events).
- `Sources/Flick/Player.swift`: playback state and commands, resume rules.
- `Sources/Flick/VideoLayer.swift`: mpv render API on a `CAOpenGLLayer`.
- `Sources/Flick/PlayerWindowController.swift`: window sizing, auto-hiding chrome, mouse and trackpad input.
- `Sources/Flick/ControlsView.swift`: control bar, scrubber, labels.
- `Sources/Flick/WebVideo.swift`: link parsing, yt-dlp routing, CloudFront cookie fix, Homebrew PATH for yt-dlp.
- `Sources/Flick/App.swift`: app delegate, menus (all keyboard shortcuts live here), first-frame probe used by `make bench`.
