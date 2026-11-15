import CMpv
import Foundation

struct MpvError: Error, CustomStringConvertible {
    let code: Int32

    var description: String { String(cString: mpv_error_string(code)) }
}

enum MpvPropertyValue: Equatable {
    case double(Double)
    case flag(Bool)
    case integer(Int64)
    case string(String)
    case unavailable

    init(_ property: mpv_event_property) {
        guard let data = property.data else {
            self = .unavailable
            return
        }
        switch property.format {
        case MPV_FORMAT_DOUBLE: self = .double(data.load(as: Double.self))
        case MPV_FORMAT_FLAG: self = .flag(data.load(as: Int32.self) != 0)
        case MPV_FORMAT_INT64: self = .integer(data.load(as: Int64.self))
        case MPV_FORMAT_STRING: self = data.load(as: UnsafePointer<CChar>?.self).map { .string(String(cString: $0)) } ?? .unavailable
        default: self = .unavailable
        }
    }
}

enum MpvEvent: Equatable {
    case fileLoaded
    case loadFailed
    case hook(name: String, id: UInt64)
    case propertyChanged(name: String, value: MpvPropertyValue)
}

final class Mpv {
    let handle: OpaquePointer
    let eventQueue: DispatchQueue
    var onEvent: ((MpvEvent) -> Void)?
    private let wakeupRelay: Unmanaged<WakeupRelay>

    init(options: [(name: String, value: String)], eventQueue: DispatchQueue = .main) throws {
        guard let handle = mpv_create() else { throw MpvError(code: MPV_ERROR_NOMEM.rawValue) }
        self.handle = handle
        self.eventQueue = eventQueue
        wakeupRelay = Unmanaged.passRetained(WakeupRelay(queue: eventQueue))
        for option in options {
            try Self.check(mpv_set_option_string(handle, option.name, option.value))
        }
        try Self.check(mpv_initialize(handle))
        wakeupRelay.takeUnretainedValue().mpv = self
        mpv_set_wakeup_callback(handle, { context in
            Unmanaged<WakeupRelay>.fromOpaque(context!).takeUnretainedValue().wake()
        }, wakeupRelay.toOpaque())
    }

    deinit {
        mpv_set_wakeup_callback(handle, nil, nil)
        mpv_terminate_destroy(handle)
        wakeupRelay.release()
    }

    @discardableResult
    func command(_ arguments: String...) -> Int32 {
        let owned = arguments.map { strdup($0) }
        defer { owned.forEach { free($0) } }
        var pointers = owned.map { UnsafePointer($0) } + [nil]
        return mpv_command(handle, &pointers)
    }

    func set(_ name: String, _ value: Double) {
        var value = value
        mpv_set_property(handle, name, MPV_FORMAT_DOUBLE, &value)
    }

    func set(_ name: String, _ value: Bool) {
        var flag: Int32 = value ? 1 : 0
        mpv_set_property(handle, name, MPV_FORMAT_FLAG, &flag)
    }

    func double(_ name: String) -> Double? {
        var value = 0.0
        return mpv_get_property(handle, name, MPV_FORMAT_DOUBLE, &value) >= 0 ? value : nil
    }

    func string(_ name: String) -> String? {
        guard let value = mpv_get_property_string(handle, name) else { return nil }
        defer { mpv_free(value) }
        return String(cString: value)
    }

    func addHook(_ name: String, priority: Int32) {
        mpv_hook_add(handle, 0, name, priority)
    }

    func continueHook(_ id: UInt64) {
        mpv_hook_continue(handle, id)
    }

    func observe(_ name: String, format: mpv_format) {
        mpv_observe_property(handle, 0, name, format)
    }

    fileprivate func drainEvents() {
        while let event = mpv_wait_event(handle, 0)?.pointee, event.event_id != MPV_EVENT_NONE {
            guard let translated = Self.translate(event) else { continue }
            onEvent?(translated)
        }
    }

    private static func translate(_ event: mpv_event) -> MpvEvent? {
        switch event.event_id {
        case MPV_EVENT_FILE_LOADED:
            return .fileLoaded
        case MPV_EVENT_END_FILE:
            let endFile = event.data.load(as: mpv_event_end_file.self)
            return endFile.reason == MPV_END_FILE_REASON_ERROR ? .loadFailed : nil
        case MPV_EVENT_HOOK:
            let hook = event.data.load(as: mpv_event_hook.self)
            return .hook(name: String(cString: hook.name), id: hook.id)
        case MPV_EVENT_PROPERTY_CHANGE:
            let property = event.data.load(as: mpv_event_property.self)
            return .propertyChanged(name: String(cString: property.name), value: MpvPropertyValue(property))
        default:
            return nil
        }
    }

    private static func check(_ code: Int32) throws {
        guard code >= 0 else { throw MpvError(code: code) }
    }
}

private final class WakeupRelay {
    weak var mpv: Mpv?
    private let queue: DispatchQueue

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func wake() {
        queue.async { [weak self] in self?.mpv?.drainEvents() }
    }
}
