import CMpv
import Foundation

final class PhoneUpload: @unchecked Sendable {
    enum Progress: Equatable {
        case receiving
        case finished
        case failed
    }

    let file: URL
    let size: Int64
    let streamTarget: String
    private let condition = NSCondition()
    private let writer: FileHandle
    private var received: Int64 = 0
    private var currentProgress = Progress.receiving

    init(file: URL, size: Int64) throws {
        guard FileManager.default.createFile(atPath: file.path, contents: nil) else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: file.path])
        }
        self.file = file
        self.size = size
        streamTarget = "\(PhoneUploadStreams.scheme)://\(UUID().uuidString)"
        writer = try FileHandle(forWritingTo: file)
    }

    var progress: Progress {
        condition.withLock { currentProgress }
    }

    var receivedBytes: Int64 {
        condition.withLock { received }
    }

    var fractionReceived: Double {
        size > 0 ? Double(receivedBytes) / Double(size) : 1
    }

    func append(_ data: Data) throws {
        try writer.write(contentsOf: data)
        condition.withLock {
            received += Int64(data.count)
            condition.broadcast()
        }
    }

    func finish() {
        let isComplete = condition.withLock { received >= size }
        guard isComplete else { return fail() }
        try? writer.close()
        settle(.finished)
    }

    func fail() {
        guard progress == .receiving else { return }
        try? writer.close()
        try? FileManager.default.removeItem(at: file)
        settle(.failed)
    }

    func discard() {
        fail()
        try? FileManager.default.removeItem(at: file)
    }

    func bytesAvailable(from offset: Int64, unless isCancelled: () -> Bool) -> Int64? {
        condition.lock()
        defer { condition.unlock() }
        while received <= offset, currentProgress == .receiving, !isCancelled() {
            condition.wait()
        }
        guard currentProgress != .failed, !isCancelled() else { return nil }
        return max(received - offset, 0)
    }

    func interruptWaits(_ mark: () -> Void) {
        condition.withLock {
            mark()
            condition.broadcast()
        }
    }

    private func settle(_ progress: Progress) {
        condition.withLock {
            currentProgress = progress
            condition.broadcast()
        }
    }
}

final class PhoneUploadStreams: @unchecked Sendable {
    static let scheme = "flick-upload"

    private let lock = NSLock()
    private var uploads: [String: PhoneUpload] = [:]

    init(mpv: Mpv) {
        let registry = Unmanaged.passRetained(self).toOpaque()
        mpv_stream_cb_add_ro(mpv.handle, Self.scheme, registry) { registry, uri, info in
            guard let registry, let uri, let info else { return MPV_ERROR_LOADING_FAILED.rawValue }
            let streams = Unmanaged<PhoneUploadStreams>.fromOpaque(registry).takeUnretainedValue()
            return streams.open(String(cString: uri), into: info)
        }
    }

    func add(_ upload: PhoneUpload) {
        lock.withLock { uploads[upload.streamTarget] = upload }
    }

    private func open(_ target: String, into info: UnsafeMutablePointer<mpv_stream_cb_info>) -> Int32 {
        guard let upload = lock.withLock({ uploads[target] }),
              let reader = try? PhoneUploadReader(upload: upload) else { return MPV_ERROR_LOADING_FAILED.rawValue }
        info.pointee.cookie = Unmanaged.passRetained(reader).toOpaque()
        info.pointee.read_fn = { cookie, buffer, count in
            PhoneUploadReader.from(cookie).read(into: buffer, upTo: count)
        }
        info.pointee.seek_fn = { cookie, offset in
            PhoneUploadReader.from(cookie).seek(to: offset)
        }
        info.pointee.size_fn = { cookie in
            PhoneUploadReader.from(cookie).upload.size
        }
        info.pointee.cancel_fn = { cookie in
            PhoneUploadReader.from(cookie).cancel()
        }
        info.pointee.close_fn = { cookie in
            guard let cookie else { return }
            Unmanaged<PhoneUploadReader>.fromOpaque(cookie).release()
        }
        return 0
    }
}

final class PhoneUploadReader {
    let upload: PhoneUpload
    private let handle: FileHandle
    private var position: Int64 = 0
    private var isCancelled = false

    init(upload: PhoneUpload) throws {
        self.upload = upload
        handle = try FileHandle(forReadingFrom: upload.file)
    }

    deinit {
        try? handle.close()
    }

    static func from(_ cookie: UnsafeMutableRawPointer?) -> PhoneUploadReader {
        Unmanaged<PhoneUploadReader>.fromOpaque(cookie!).takeUnretainedValue()
    }

    func read(into buffer: UnsafeMutablePointer<CChar>?, upTo count: UInt64) -> Int64 {
        guard let buffer, let available = upload.bytesAvailable(from: position, unless: { isCancelled }) else { return -1 }
        let wanted = Int(min(Int64(count), available))
        guard wanted > 0 else { return 0 }
        guard (try? handle.seek(toOffset: UInt64(position))) != nil,
              let data = try? handle.read(upToCount: wanted), !data.isEmpty else { return -1 }
        data.copyBytes(to: UnsafeMutableRawBufferPointer(start: buffer, count: data.count))
        position += Int64(data.count)
        return Int64(data.count)
    }

    func seek(to offset: Int64) -> Int64 {
        guard offset >= 0, offset <= upload.size else { return Int64(MPV_ERROR_GENERIC.rawValue) }
        position = offset
        return offset
    }

    func cancel() {
        upload.interruptWaits { isCancelled = true }
    }
}
