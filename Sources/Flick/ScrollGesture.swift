import Foundation

struct ScrollInput {
    enum Phase {
        case began
        case changed
        case ended
        case momentum
        case wheel
    }

    var deltaX: Double
    var deltaY: Double
    var isPrecise: Bool
    var isNaturalScrolling: Bool
    var phase: Phase

    var fingersRight: Double { isNaturalScrolling ? deltaX : -deltaX }
    var fingersUp: Double { isNaturalScrolling ? -deltaY : deltaY }
}

enum ScrollAction: Equatable {
    case none
    case seek(seconds: Double)
    case changeVolume(by: Double)
}

struct ScrollGesture {
    static let secondsPerPoint = 0.2
    static let volumePerPoint = 0.5
    static let secondsPerWheelNotch = 5.0
    static let volumePerWheelNotch = 5.0

    private enum Axis {
        case horizontal
        case vertical
    }

    private var lockedAxis: Axis?

    mutating func action(for input: ScrollInput) -> ScrollAction {
        switch input.phase {
        case .momentum:
            return .none
        case .ended:
            lockedAxis = nil
            return .none
        case .began:
            lockedAxis = nil
        case .changed, .wheel:
            break
        }
        guard let axis = axis(for: input) else { return .none }
        return input.isPrecise ? preciseAction(input, axis: axis) : wheelAction(input, axis: axis)
    }

    private mutating func axis(for input: ScrollInput) -> Axis? {
        if let lockedAxis { return lockedAxis }
        guard input.deltaX != 0 || input.deltaY != 0 else { return nil }
        let axis: Axis = abs(input.deltaX) > abs(input.deltaY) ? .horizontal : .vertical
        if input.phase != .wheel { lockedAxis = axis }
        return axis
    }

    private func preciseAction(_ input: ScrollInput, axis: Axis) -> ScrollAction {
        switch axis {
        case .horizontal: .seek(seconds: input.fingersRight * Self.secondsPerPoint)
        case .vertical: .changeVolume(by: input.fingersUp * Self.volumePerPoint)
        }
    }

    private func wheelAction(_ input: ScrollInput, axis: Axis) -> ScrollAction {
        switch axis {
        case .horizontal: .seek(seconds: input.fingersRight < 0 ? -Self.secondsPerWheelNotch : Self.secondsPerWheelNotch)
        case .vertical: .changeVolume(by: input.fingersUp < 0 ? -Self.volumePerWheelNotch : Self.volumePerWheelNotch)
        }
    }
}
