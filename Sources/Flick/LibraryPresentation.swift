import AppKit

extension PlayerWindowController {
    var isLibraryShowing: Bool { !libraryView.isHidden }

    func showLibrary() {
        libraryView.isHidden = false
        chrome.controls.isHidden = true
        chrome.setVisible(true)
        guard hasFile else {
            window?.setContentSize(libraryView.isEmpty ? NSSize(width: 640, height: 400) : NSSize(width: 960, height: 620))
            window?.center()
            window?.makeKeyAndOrderFront(nil)
            return
        }
        library.record(player.state)
        if !player.state.isPaused { player.togglePause() }
    }

    func recordProgress() {
        library.record(player.state)
    }

    @objc func toggleLibrary(_ sender: Any?) {
        guard !isLibraryShowing || !hasFile else { return resumeFromLibrary() }
        showLibrary()
    }

    @objc func addFilesToLibrary(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = AppDelegate.playableContentTypes
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(library.save)
    }

    @objc func addLinkToLibrary(_ sender: Any?) {
        guard let url = LinkPrompt.ask(title: "Add a video link to your library", button: "Add") else { return }
        library.save(url)
        guard url.resolvesThroughYtdl, let lookup else { return }
        Task { @MainActor [library] in
            guard let info = await lookup.info(for: url) else { return }
            library.describe(url, with: info)
        }
    }

    func installLibrary(in playerView: PlayerView) {
        libraryView.translatesAutoresizingMaskIntoConstraints = false
        playerView.addSubview(libraryView, positioned: .below, relativeTo: chrome.controls)
        NSLayoutConstraint.activate([
            libraryView.topAnchor.constraint(equalTo: playerView.topAnchor),
            libraryView.bottomAnchor.constraint(equalTo: playerView.bottomAnchor),
            libraryView.leadingAnchor.constraint(equalTo: playerView.leadingAnchor),
            libraryView.trailingAnchor.constraint(equalTo: playerView.trailingAnchor),
        ])
        libraryView.onPlay = { [weak self] url in self?.open(url) }
        libraryView.onAddFiles = { [weak self] in self?.addFilesToLibrary(nil) }
        libraryView.onAddLink = { [weak self] in self?.addLinkToLibrary(nil) }
    }

    func resumeFromLibrary() {
        libraryView.isHidden = true
        chrome.controls.isHidden = player.state.isLoading
        if player.state.isPaused { player.togglePause() }
        revealChrome()
    }
}

extension PlaybackState {
    func hasNewsForLibrary(since previous: PlaybackState) -> Bool {
        title != previous.title || thumbnail != previous.thumbnail || duration != previous.duration
            || isPaused != previous.isPaused || isAtEnd != previous.isAtEnd || isLoading != previous.isLoading
    }
}
