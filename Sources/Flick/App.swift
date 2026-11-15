import AppKit
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
    static let firstFrameProbeVariable = "FLICK_FIRST_FRAME_FILE"

    private var controller: PlayerWindowController?
    private var player: Player?
    private var firstFrameProbe: FirstFrameProbe?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = MainMenu.make()
        UserDefaults.standard.register(defaults: [Self.volumeKey: 100.0])
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
        controller.showEmptyState()
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard let player else { return }
        player.saveResumePoint()
        UserDefaults.standard.set(player.state.volume, forKey: Self.volumeKey)
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video, .audiovisualContent, .audio]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        controller?.open(url)
    }

    private func startPlayer() throws {
        let volume = UserDefaults.standard.double(forKey: Self.volumeKey)
        let mpv = try Mpv(options: Player.options(watchLaterDirectory: Self.watchLaterDirectory, volume: volume))
        let player = Player(mpv: mpv)
        let videoLayer = try VideoLayer(mpv: mpv)
        self.player = player
        let controller = PlayerWindowController(player: player, videoLayer: videoLayer)
        self.controller = controller
        firstFrameProbe = FirstFrameProbe(environment: ProcessInfo.processInfo.environment)
        firstFrameProbe?.attach(to: videoLayer, controller: controller)
    }

    private static var watchLaterDirectory: URL {
        URL.applicationSupportDirectory.appending(components: "Flick", "watch_later")
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
        for submenu in [appMenu(), fileMenu(), playbackMenu(), audioMenu(), viewMenu(), windowMenu()] {
            let holder = NSMenuItem()
            holder.submenu = submenu
            menu.addItem(holder)
        }
        return menu
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Flick")
        menu.addItem(item("About Flick", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
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
        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w", [.command]))
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
