import CMpv
import Foundation

struct VideoShape: Equatable {
    static let observedProperties = ["video-out-params/dw", "video-out-params/dh", "video-out-params/rotate"]
        .map { MpvProperty($0, MPV_FORMAT_INT64) }

    var width: Int64 = 0
    var height: Int64 = 0
    var rotation: Int64 = 0

    static func isObserved(_ name: String) -> Bool {
        observedProperties.contains { $0.name == name }
    }

    init(width: Int64 = 0, height: Int64 = 0, rotation: Int64 = 0) {
        self.width = width
        self.height = height
        self.rotation = rotation
    }

    init?(reading mpv: Mpv) {
        guard
            let width = mpv.integer("video-out-params/dw"),
            let height = mpv.integer("video-out-params/dh"),
            let rotation = mpv.integer("video-out-params/rotate")
        else { return nil }
        self.init(width: width, height: height, rotation: rotation)
    }

    var size: CGSize? {
        guard width > 0, height > 0 else { return nil }
        let isSideways = rotation % 180 != 0
        return CGSize(width: Double(isSideways ? height : width), height: Double(isSideways ? width : height))
    }

    var shortSide: Int64 { min(width, height) }
}

extension CGSize {
    func hasSameShape(as other: CGSize?) -> Bool {
        guard let other, other.height > 0, height > 0 else { return false }
        let tolerance = 0.01
        return abs(width / height - other.width / other.height) <= tolerance * (other.width / other.height)
    }
}
