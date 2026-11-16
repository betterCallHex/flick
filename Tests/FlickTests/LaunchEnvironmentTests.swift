import Foundation
import Testing
@testable import Flick

struct LaunchEnvironmentTests {
    @Test func keepsDataInApplicationSupportByDefault() {
        let launch = LaunchEnvironment(environment: [:])
        #expect(launch.libraryFile == URL.applicationSupportDirectory.appending(components: "Flick", "library.json"))
        #expect(launch.phoneVideosDirectory == URL.temporaryDirectory.appending(component: "From Phone"))
        #expect(!launch.isDriven)
    }

    @Test func keepsADrivenRunsDataInItsOwnFolder() {
        let launch = LaunchEnvironment(environment: ["FLICK_DRIVE_DIR": "/tmp/flick-drive/data"])
        #expect(launch.libraryFile.path == "/tmp/flick-drive/data/library.json")
        #expect(launch.watchLaterDirectory.path == "/tmp/flick-drive/data/watch_later")
        #expect(launch.phoneVideosDirectory.path == "/tmp/flick-drive/data/From Phone")
        #expect(launch.isDriven)
    }
}

@Suite(.serialized)
struct MutedLaunchTests {
    @Test func aMutedPlayerStartsSilent() async throws {
        let video = try VideoFixture.shared()
        let options = Player.options(watchLaterDirectory: try temporaryDirectory(), volume: 100, isMuted: true)
        let session = try HeadlessSession(options: options)
        let opened = try await session.open(video)
        #expect(opened.isMuted)
    }
}
