import AppKit
import Sparkle
import UniformTypeIdentifiers

@main
enum FlickApp {
    static func main() {
        let delegate = AppDelegate()
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let volumeKey = "volume"
    static let subtitlesKey = "showsSubtitles"
    static let firstFrameProbeVariable = "FLICK_FIRST_FRAME_FILE"
    static let playableContentTypes: [UTType] = [.movie, .video, .audiovisualContent, .audio]

    private let launch = LaunchEnvironment(environment: ProcessInfo.processInfo.environment)
    private var controller: PlayerWindowController?
    private var player: Player?
    private var firstFrameProbe: FirstFrameProbe?
    private var uploadStreams: PhoneUploadStreams?
    private var phoneWindow: PhoneWindowController?
    private let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = MainMenu.make()
        try? FileManager.default.removeItem(at: launch.phoneVideosDirectory)
        HomebrewTools.exposeToChildProcesses()
        UserDefaults.standard.register(defaults: [Self.volumeKey: 100.0, Self.subtitlesKey: true])
        do {
            try startPlayer()
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        controller?.open(url)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let controller, !controller.hasFile else { return }
        controller.showLibrary()
        guard !launch.isDriven else { return }
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.discardPhoneUpload()
        try? FileManager.default.removeItem(at: launch.phoneVideosDirectory)
        guard let player else { return }
        controller?.recordProgress()
        player.saveResumePoint()
        UserDefaults.standard.set(player.state.volume, forKey: Self.volumeKey)
        UserDefaults.standard.set(player.state.subtitles.isVisible, forKey: Self.subtitlesKey)
    }

    @objc func checkForUpdates(_ sender: Any?) {
        updater.checkForUpdates(sender)
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.playableContentTypes
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        controller?.open(url)
    }

    @objc func openLocation(_ sender: Any?) {
        guard let url = LinkPrompt.ask(title: "Open a video link", button: "Play") else { return }
        controller?.open(url)
    }

    @objc func playFromPhone(_ sender: Any?) {
        let phoneWindow = phoneWindow ?? makePhoneWindow()
        self.phoneWindow = phoneWindow
        phoneWindow.present()
    }

    private func makePhoneWindow() -> PhoneWindowController {
        let phoneWindow = PhoneWindowController(destination: launch.phoneVideosDirectory)
        phoneWindow.onLink = { [weak self] url in self?.controller?.open(url) }
        phoneWindow.onUploadStarted = { [weak self] upload in
            self?.uploadStreams?.add(upload)
            self?.controller?.play(upload)
        }
        return phoneWindow
    }

    private func startPlayer() throws {
        let defaults = UserDefaults.standard
        let options = Player.options(
            watchLaterDirectory: launch.watchLaterDirectory,
            volume: defaults.double(forKey: Self.volumeKey),
            showsSubtitles: defaults.bool(forKey: Self.subtitlesKey),
            isMuted: launch.isDriven
        )
        let mpv = try Mpv(options: options)
        uploadStreams = PhoneUploadStreams(mpv: mpv)
        let player = Player(mpv: mpv)
        let videoLayer = try VideoLayer(mpv: mpv)
        self.player = player
        let library = Library(file: launch.libraryFile)
        let controller = PlayerWindowController(player: player, library: library, videoLayer: videoLayer)
        self.controller = controller
        firstFrameProbe = FirstFrameProbe(environment: ProcessInfo.processInfo.environment)
        firstFrameProbe?.attach(to: videoLayer, controller: controller)
    }
}

struct LaunchEnvironment {
    static let driveDirectoryVariable = "FLICK_DRIVE_DIR"

    let dataDirectory: URL
    let isDriven: Bool

    init(environment: [String: String]) {
        guard let path = environment[Self.driveDirectoryVariable] else {
            dataDirectory = URL.applicationSupportDirectory.appending(component: "Flick")
            isDriven = false
            return
        }
        dataDirectory = URL(fileURLWithPath: path, isDirectory: true)
        isDriven = true
    }

    var watchLaterDirectory: URL { dataDirectory.appending(component: "watch_later") }
    var libraryFile: URL { dataDirectory.appending(component: "library.json") }
    var phoneVideosDirectory: URL { (isDriven ? dataDirectory : .temporaryDirectory).appending(component: "From Phone") }
}

enum LinkPrompt {
    static func ask(title: String, button: String) -> URL? {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.placeholderString = "https://www.youtube.com/watch?v=…"
        field.stringValue = NSPasteboard.general.string(forType: .string).flatMap(URL.init(webVideoString:))?.absoluteString ?? ""
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "YouTube, Loom, Vimeo, public Drive or Dropbox links, or a direct video URL."
        alert.accessoryView = field
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        guard let url = URL(webVideoString: field.stringValue) else {
            NSSound.beep()
            return nil
        }
        return url
    }
}

final class FirstFrameProbe {
    private let path: String
    private var frameDrawnAt: Date?
    private var windowShownAt: Date?

    init?(environment: [String: String]) {
        guard let path = environment[AppDelegate.firstFrameProbeVariable] else { return nil }
        self.path = path
    }

    func attach(to videoLayer: VideoLayer, controller: PlayerWindowController) {
        videoLayer.onFirstFrame = { [self] in
            let drawnAt = Date()
            DispatchQueue.main.async { [self] in
                frameDrawnAt = drawnAt
                reportOnceVisible()
            }
        }
        controller.onReveal = { [self] in
            windowShownAt = Date()
            reportOnceVisible()
        }
    }

    private func reportOnceVisible() {
        guard let frameDrawnAt, let windowShownAt else { return }
        let visibleAt = max(frameDrawnAt, windowShownAt)
        let milliseconds = Int((visibleAt.timeIntervalSince1970 * 1000).rounded())
        try? String(milliseconds).write(toFile: path, atomically: true, encoding: .utf8)
        _exit(0)
    }
}

enum MainMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()
        for submenu in [appMenu(), fileMenu(), editMenu(), playbackMenu(), audioMenu(), viewMenu(), windowMenu()] {
            let holder = NSMenuItem()
            holder.submenu = submenu
            menu.addItem(holder)
        }
        return menu
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Flick")
        menu.addItem(item("About Flick", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(item("Check for Updates…", #selector(AppDelegate.checkForUpdates(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Hide Flick", #selector(NSApplication.hide(_:)), "h", [.command]))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit Flick", #selector(NSApplication.terminate(_:)), "q", [.command]))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("Open…", #selector(AppDelegate.openDocument(_:)), "o", [.command]))
        menu.addItem(item("Open URL…", #selector(AppDelegate.openLocation(_:)), "o", [.command, .shift]))
        menu.addItem(item("Play from Phone…", #selector(AppDelegate.playFromPhone(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Show Library", #selector(PlayerWindowController.toggleLibrary(_:)), "l", [.command]))
        menu.addItem(item("Add Files to Library…", #selector(PlayerWindowController.addFilesToLibrary(_:))))
        menu.addItem(item("Add Link to Library…", #selector(PlayerWindowController.addLinkToLibrary(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w", [.command]))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), "x", [.command]))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), "c", [.command]))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), "v", [.command]))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a", [.command]))
        return menu
    }

    private static func playbackMenu() -> NSMenu {
        let menu = NSMenu(title: "Playback")
        menu.addItem(item("Play / Pause", #selector(PlayerWindowController.togglePlayback(_:)), " "))
        menu.addItem(.separator())
        let seek = #selector(PlayerWindowController.seekBySeconds(_:))
        menu.addItem(item("Forward 5 Seconds", seek, arrow(NSRightArrowFunctionKey), tag: 5))
        menu.addItem(item("Back 5 Seconds", seek, arrow(NSLeftArrowFunctionKey), tag: -5))
        menu.addItem(item("Forward 30 Seconds", seek, arrow(NSRightArrowFunctionKey), [.shift], tag: 30))
        menu.addItem(item("Back 30 Seconds", seek, arrow(NSLeftArrowFunctionKey), [.shift], tag: -30))
        menu.addItem(item("Forward 1 Second", seek, arrow(NSRightArrowFunctionKey), [.option], tag: 1))
        menu.addItem(item("Back 1 Second", seek, arrow(NSLeftArrowFunctionKey), [.option], tag: -1))
        menu.addItem(.separator())
        menu.addItem(item("Next Frame", #selector(PlayerWindowController.stepForward(_:)), "."))
        menu.addItem(item("Previous Frame", #selector(PlayerWindowController.stepBackward(_:)), ","))
        menu.addItem(.separator())
        menu.addItem(item("Faster", #selector(PlayerWindowController.speedUp(_:)), "]"))
        menu.addItem(item("Slower", #selector(PlayerWindowController.slowDown(_:)), "["))
        menu.addItem(item("Normal Speed", #selector(PlayerWindowController.resetSpeed(_:)), "\\"))
        return menu
    }

    private static func audioMenu() -> NSMenu {
        let menu = NSMenu(title: "Audio")
        let volume = #selector(PlayerWindowController.changeVolumeBySteps(_:))
        menu.addItem(item("Volume Up", volume, arrow(NSUpArrowFunctionKey), tag: 5))
        menu.addItem(item("Volume Down", volume, arrow(NSDownArrowFunctionKey), tag: -5))
        menu.addItem(item("Mute", #selector(PlayerWindowController.toggleMute(_:)), "m"))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(item("Toggle Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f"))
        menu.addItem(item("Subtitles", #selector(PlayerWindowController.toggleSubtitles(_:)), "c"))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m", [.command]))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        NSApp.windowsMenu = menu
        return menu
    }

    private static func item(
        _ title: String,
        _ action: Selector,
        _ key: String = "",
        _ modifiers: NSEvent.ModifierFlags = [],
        tag: Int = 0
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.tag = tag
        return item
    }

    private static func arrow(_ functionKey: Int) -> String {
        String(Character(UnicodeScalar(functionKey)!))
    }
}
