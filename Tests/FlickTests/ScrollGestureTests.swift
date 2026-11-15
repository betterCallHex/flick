import Testing
@testable import Flick

struct ScrollGestureTests {
    @Test func swipingFingersRightSeeksForwardWithNaturalScrolling() {
        var gesture = ScrollGesture()
        let action = gesture.action(for: trackpad(deltaX: 10, deltaY: 0, natural: true, phase: .began))
        #expect(action == .seek(seconds: 2))
    }

    @Test func swipingFingersRightSeeksForwardWithClassicScrolling() {
        var gesture = ScrollGesture()
        let action = gesture.action(for: trackpad(deltaX: -10, deltaY: 0, natural: false, phase: .began))
        #expect(action == .seek(seconds: 2))
    }

    @Test func swipingFingersUpRaisesVolume() {
        var gesture = ScrollGesture()
        let action = gesture.action(for: trackpad(deltaX: 0, deltaY: -10, natural: true, phase: .began))
        #expect(action == .changeVolume(by: 5))
    }

    @Test func aHorizontalGestureStaysASeekWhenFingersDrift() {
        var gesture = ScrollGesture()
        _ = gesture.action(for: trackpad(deltaX: 10, deltaY: 1, natural: true, phase: .began))
        let drifted = gesture.action(for: trackpad(deltaX: 1, deltaY: -8, natural: true, phase: .changed))
        #expect(drifted == .seek(seconds: 0.2))
    }

    @Test func aNewGestureChoosesItsAxisAgain() {
        var gesture = ScrollGesture()
        _ = gesture.action(for: trackpad(deltaX: 10, deltaY: 0, natural: true, phase: .began))
        _ = gesture.action(for: trackpad(deltaX: 0, deltaY: 0, natural: true, phase: .ended))
        let next = gesture.action(for: trackpad(deltaX: 0, deltaY: -10, natural: true, phase: .began))
        #expect(next == .changeVolume(by: 5))
    }

    @Test func momentumAfterLiftingFingersIsIgnored() {
        var gesture = ScrollGesture()
        let action = gesture.action(for: trackpad(deltaX: 30, deltaY: 0, natural: true, phase: .momentum))
        #expect(action == .none)
    }

    @Test func aMouseWheelNotchChangesVolumeByAFixedStep() {
        var gesture = ScrollGesture()
        let input = ScrollInput(deltaX: 0, deltaY: 3, isPrecise: false, isNaturalScrolling: false, phase: .wheel)
        #expect(gesture.action(for: input) == .changeVolume(by: 5))
    }

    private func trackpad(deltaX: Double, deltaY: Double, natural: Bool, phase: ScrollInput.Phase) -> ScrollInput {
        ScrollInput(deltaX: deltaX, deltaY: deltaY, isPrecise: true, isNaturalScrolling: natural, phase: phase)
    }
}
