import AppKit
import CoreImage.CIFilterBuiltins

final class PhoneWindowController: NSWindowController, NSWindowDelegate {
    static let codeSize: CGFloat = 220

    var onLink: ((URL) -> Void)?
    var onUploadStarted: ((PhoneUpload) -> Void)?
    private let destination: URL
    private var server: PhoneServer?
    private var receiving: [PhoneUpload] = []
    private var progressTimer: Timer?
    private let codeView = NSImageView()
    private let addressLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")

    init(destination: URL) {
        self.destination = destination
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 470),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = "Play from Phone"
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.delegate = self
        window.contentView = makeContent()
    }

    required init?(coder: NSCoder) {
        fatalError("PhoneWindowController is created in code only")
    }

    func present() {
        if server == nil { startServer() }
        window?.center()
        showWindow(nil)
    }

    func windowWillClose(_ notification: Notification) {
        server?.stopListening()
        server = nil
    }

    private func makeContent() -> NSView {
        let title = NSTextField(labelWithString: "Scan with your phone’s camera")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let hint = NSTextField(wrappingLabelWithString: "Your phone must be on the same Wi-Fi as this Mac. Pick a video on the page that opens and it plays here. Nothing is kept on this Mac.")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center
        codeView.imageScaling = .scaleNone
        codeView.wantsLayer = true
        codeView.layer?.backgroundColor = NSColor.white.cgColor
        codeView.layer?.cornerRadius = 10
        codeView.setAccessibilityLabel("QR code for the Play from Phone page")
        addressLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        addressLabel.textColor = .secondaryLabelColor
        addressLabel.isSelectable = true
        addressLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.alignment = .center
        statusLabel.stringValue = "Starting…"
        let stack = NSStackView(views: [title, hint, codeView, addressLabel, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 24, right: 24)
        stack.setCustomSpacing(18, after: hint)
        NSLayoutConstraint.activate([
            codeView.widthAnchor.constraint(equalToConstant: Self.codeSize + 24),
            codeView.heightAnchor.constraint(equalToConstant: Self.codeSize + 24),
            hint.widthAnchor.constraint(equalToConstant: 292),
            statusLabel.widthAnchor.constraint(equalToConstant: 292),
            addressLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 292),
        ])
        return stack
    }

    private func startServer() {
        guard let server = try? PhoneServer(destination: destination) else { return show(status: "Flick couldn’t start sharing on this network.") }
        self.server = server
        server.onLink = { [weak self] url in self?.onLink?(url) }
        server.onUploadStarted = { [weak self] upload in self?.started(upload) }
        server.onUploadEnded = { [weak self] upload in self?.ended(upload) }
        server.start { [weak self, weak server] port in
            guard let self, let server, server === self.server else { return }
            self.serverReady(server, port: port)
        }
    }

    private func serverReady(_ server: PhoneServer, port: UInt16?) {
        guard let port else { return show(status: "Flick couldn’t start sharing on this network.") }
        guard let host = LocalAddress.wifi(), let page = server.pageURL(host: host, port: port) else {
            codeView.image = nil
            return show(status: "Connect this Mac to Wi-Fi, then open Play from Phone again.")
        }
        codeView.image = Self.code(for: page)
        addressLabel.stringValue = page.absoluteString
        if receiving.isEmpty { show(status: "Waiting for your phone…") }
    }

    private func started(_ upload: PhoneUpload) {
        receiving.append(upload)
        onUploadStarted?(upload)
        showProgress()
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in self?.showProgress() }
    }

    private func ended(_ upload: PhoneUpload) {
        receiving.removeAll { $0 === upload }
        if receiving.isEmpty {
            progressTimer?.invalidate()
            progressTimer = nil
        }
        let name = upload.file.lastPathComponent
        guard upload.progress == .finished else { return show(status: "“\(name)” stopped before it finished sending.") }
        show(status: "“\(name)” is here. Flick forgets it when you play something else.")
    }

    private func showProgress() {
        guard let upload = receiving.last else { return }
        let percent = Int((upload.fractionReceived * 100).rounded(.down))
        show(status: "Receiving “\(upload.file.lastPathComponent)”… \(percent)%")
    }

    private func show(status: String) {
        statusLabel.stringValue = status
    }

    private static func code(for url: URL) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = (codeSize / output.extent.width).rounded(.down)
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let image = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}

enum LocalAddress {
    static func wifi() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }
        let candidates = sequence(first: first) { $0.pointee.ifa_next }.compactMap { candidate(from: $0.pointee) }
        return candidates.first { $0.interface.hasPrefix("en") }?.address ?? candidates.first?.address
    }

    private static func candidate(from interface: ifaddrs) -> (interface: String, address: String)? {
        let flags = Int32(interface.ifa_flags)
        guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0,
              let socketAddress = interface.ifa_addr, socketAddress.pointee.sa_family == UInt8(AF_INET) else { return nil }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(socketAddress, socklen_t(socketAddress.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
        let address = String(cString: host)
        guard isPrivate(address) else { return nil }
        return (String(cString: interface.ifa_name), address)
    }

    static func isPrivate(_ address: String) -> Bool {
        let octets = address.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return false }
        return octets[0] == 10 || (octets[0] == 172 && (16...31).contains(octets[1])) || (octets[0] == 192 && octets[1] == 168)
    }
}
