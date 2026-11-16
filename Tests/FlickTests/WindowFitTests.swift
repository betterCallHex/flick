import AppKit
import Testing
@testable import Flick

struct WindowFitTests {
    private let screen = NSRect(x: 0, y: 0, width: 1512, height: 944)

    @Test func keepsASmallVideoAtItsOwnSize() {
        let frame = NSRect(fittingVideo: CGSize(width: 640, height: 360), centeredAt: CGPoint(x: 756, y: 472), within: screen)
        #expect(frame.size == CGSize(width: 640, height: 360))
    }

    @Test func shrinksALargeVideoToFitTheScreenKeepingItsShape() {
        let frame = NSRect(fittingVideo: CGSize(width: 3840, height: 2160), centeredAt: CGPoint(x: 756, y: 472), within: screen)
        #expect(frame.width <= screen.width * 0.85)
        #expect(frame.height <= screen.height * 0.85)
        #expect(abs(frame.width / frame.height - 16.0 / 9.0) < 0.01)
    }

    @Test func growsATinyVideoToAUsableSize() {
        let frame = NSRect(fittingVideo: CGSize(width: 320, height: 240), centeredAt: CGPoint(x: 756, y: 472), within: screen)
        #expect(frame.size == CGSize(width: 480, height: 360))
    }

    @Test func staysOnScreenWhenCenteredNearAnEdge() {
        let frame = NSRect(fittingVideo: CGSize(width: 1280, height: 720), centeredAt: CGPoint(x: 1500, y: 20), within: screen)
        #expect(screen.contains(frame))
    }

    @Test func keepsTheWindowWhenTheSameVideoComesInAnotherResolution() {
        #expect(CGSize(width: 854, height: 480).hasSameShape(as: CGSize(width: 1920, height: 1080)))
        #expect(!CGSize(width: 1080, height: 1920).hasSameShape(as: CGSize(width: 1920, height: 1080)))
        #expect(!CGSize(width: 1920, height: 1080).hasSameShape(as: nil))
    }
}

struct VideoSizeTests {
    @Test func usesTheStoredSizeForAnUnrotatedVideo() {
        #expect(VideoShape(width: 1280, height: 720).size == CGSize(width: 1280, height: 720))
    }

    @Test func turnsAPhoneVideoRecordedSidewaysUpright() {
        #expect(VideoShape(width: 1280, height: 720, rotation: 90).size == CGSize(width: 720, height: 1280))
        #expect(VideoShape(width: 1280, height: 720, rotation: 270).size == CGSize(width: 720, height: 1280))
    }

    @Test func keepsTheShapeOfAnUpsideDownVideo() {
        #expect(VideoShape(width: 1280, height: 720, rotation: 180).size == CGSize(width: 1280, height: 720))
    }
}
