import Foundation
import Network
import Testing
@testable import Flick

struct PhoneFileNameTests {
    @Test func keepsThePhonesFileName() throws {
        let folder = try temporaryDirectory()
        #expect(PhoneServer.uniqueFile(named: "IMG_1234.MOV", in: folder) == folder.appending(component: "IMG_1234.MOV"))
    }

    @Test func numbersANameThatIsAlreadyTaken() throws {
        let folder = try temporaryDirectory()
        FileManager.default.createFile(atPath: folder.appending(component: "Trip.mp4").path, contents: Data())
        FileManager.default.createFile(atPath: folder.appending(component: "Trip 2.mp4").path, contents: Data())

        #expect(PhoneServer.uniqueFile(named: "Trip.mp4", in: folder) == folder.appending(component: "Trip 3.mp4"))
    }

    @Test func staysInsideTheFolder() throws {
        let folder = try temporaryDirectory()
        #expect(PhoneServer.uniqueFile(named: "../../.ssh/config", in: folder) == folder.appending(component: "config"))
        #expect(PhoneServer.uniqueFile(named: "..", in: folder) == folder.appending(component: PhoneServer.fallbackFileName))
        #expect(PhoneServer.uniqueFile(named: "", in: folder) == folder.appending(component: PhoneServer.fallbackFileName))
    }
}

struct PhoneRequestHeadTests {
    @Test func readsMethodPathQueryAndHeaders() throws {
        let head = try #require(PhoneRequestHead(Data("PUT /abc/upload?name=My%20Trip.mov HTTP/1.1\r\nContent-Length: 42\r\nExpect: 100-continue".utf8)))

        #expect(head.method == "PUT")
        #expect(head.pathComponents == ["abc", "upload"])
        #expect(head.query["name"] == "My Trip.mov")
        #expect(head.contentLength == 42)
        #expect(head.expectsContinue)
    }

    @Test func rejectsSomethingThatIsNotHTTP() {
        #expect(PhoneRequestHead(Data("hello".utf8)) == nil)
    }
}

struct LocalAddressTests {
    @Test func offersOnlyHomeNetworkAddresses() {
        #expect(LocalAddress.isPrivate("192.168.1.20"))
        #expect(LocalAddress.isPrivate("10.0.0.5"))
        #expect(LocalAddress.isPrivate("172.20.10.2"))
        #expect(!LocalAddress.isPrivate("172.32.0.1"))
        #expect(!LocalAddress.isPrivate("8.8.8.8"))
        #expect(!LocalAddress.isPrivate("169.254.3.4"))
    }
}

@MainActor
struct PhoneServerTests {
    @Test func servesThePageOnlyBehindItsToken() async throws {
        let phone = try await RunningPhoneServer()

        let (page, pageResponse) = try await URLSession.shared.data(from: phone.url("/"))
        let (_, strangerResponse) = try await URLSession.shared.data(from: phone.url("/", token: "guess"))

        #expect((pageResponse as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: page, as: UTF8.self).contains("Choose a video"))
        #expect((strangerResponse as? HTTPURLResponse)?.statusCode == 404)
    }

    @Test func savesAnUploadedVideoAndReportsItStartingAndFinishing() async throws {
        let phone = try await RunningPhoneServer()
        let video = Data((0..<3_000_000).map { UInt8(truncatingIfNeeded: $0) })
        var request = URLRequest(url: phone.url("/upload?name=Trip.mp4"))
        request.httpMethod = "PUT"

        let (_, response) = try await URLSession.shared.upload(for: request, from: video)
        let ended = try await phone.nextEnded()

        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(phone.started.map(\.file) == [phone.folder.appending(component: "Trip.mp4")])
        #expect(ended.progress == .finished)
        #expect(try Data(contentsOf: ended.file) == video)
    }

    @Test func throwsAwayAnUploadThePhoneAbandons() async throws {
        let phone = try await RunningPhoneServer()
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: phone.port)!, using: .tcp)
        connection.start(queue: .global())
        let head = "PUT /\(phone.server.token)/upload?name=Half.mov HTTP/1.1\r\nHost: x\r\nContent-Length: 1000\r\n\r\n"
        connection.send(content: Data(head.utf8) + Data(count: 10), completion: .idempotent)

        try await phone.waitUntilStarted()
        connection.cancel()
        let ended = try await phone.nextEnded()

        #expect(ended.progress == .failed)
        #expect(!FileManager.default.fileExists(atPath: ended.file.path))
    }

    @Test func playsALinkSentFromThePhone() async throws {
        let phone = try await RunningPhoneServer()
        var request = URLRequest(url: phone.url("/link"))
        request.httpMethod = "POST"
        request.httpBody = Data(" https://www.youtube.com/watch?v=aqz-KE-bpKQ\n".utf8)

        let (_, response) = try await URLSession.shared.data(for: request)
        try await phone.waitUntil { !phone.links.isEmpty }

        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(phone.links == [URL(string: "https://www.youtube.com/watch?v=aqz-KE-bpKQ")!])
    }

    @Test func turnsAwayTextThatIsNotALink() async throws {
        let phone = try await RunningPhoneServer()
        var request = URLRequest(url: phone.url("/link"))
        request.httpMethod = "POST"
        request.httpBody = Data("not a link".utf8)

        let (_, response) = try await URLSession.shared.data(for: request)

        #expect((response as? HTTPURLResponse)?.statusCode == 400)
        #expect(phone.links.isEmpty)
    }
}

@Suite(.serialized)
struct PhoneStreamingTests {
    @Test func startsPlayingBeforeTheUploadFinishes() async throws {
        let video = try VideoFixture.shared()
        let bytes = try Data(contentsOf: video)
        let destination = try temporaryDirectory().appending(component: "Phone.mp4")
        let upload = try PhoneUpload(file: destination, size: Int64(bytes.count))
        try upload.append(bytes.prefix(bytes.count / 2))
        let watchLater = try temporaryDirectory()
        let session = try HeadlessSession(watchLater: watchLater)
        session.perform { player in
            PhoneUploadStreams(mpv: player.mpv).add(upload)
            player.open(destination, streamingFrom: upload.streamTarget)
        }

        let playing = try await session.waitUntil { $0.duration > 0 && !$0.isLoading }
        #expect(playing.url == destination)
        #expect(upload.progress == .receiving)

        try upload.append(bytes.suffix(from: bytes.count / 2))
        upload.finish()
        session.perform { $0.seek(to: 19.5, precise: true) }
        try await session.waitUntil(\.isAtEnd)
        #expect(try Data(contentsOf: destination) == bytes)
    }

    @Test func leavesNoResumePointBehindForAStreamedVideo() async throws {
        let video = try VideoFixture.shared()
        let bytes = try Data(contentsOf: video)
        let destination = try temporaryDirectory().appending(component: "Phone.mp4")
        let upload = try PhoneUpload(file: destination, size: Int64(bytes.count))
        try upload.append(bytes)
        upload.finish()
        let watchLater = try temporaryDirectory()
        let session = try HeadlessSession(watchLater: watchLater)
        session.perform { player in
            PhoneUploadStreams(mpv: player.mpv).add(upload)
            player.open(destination, streamingFrom: upload.streamTarget)
        }
        try await session.waitUntil { $0.duration > 0 && !$0.isLoading }
        session.perform { $0.seek(to: 12, precise: true) }
        try await session.waitUntil { abs($0.position - 12) < 0.5 }

        session.perform { $0.saveResumePoint() }

        #expect(try FileManager.default.contentsOfDirectory(atPath: watchLater.path).isEmpty)
    }

    @Test func aFailedUploadStopsReadersAndDeletesTheFile() throws {
        let destination = try temporaryDirectory().appending(component: "Phone.mp4")
        let upload = try PhoneUpload(file: destination, size: 100)
        try upload.append(Data(count: 10))

        upload.fail()

        #expect(upload.bytesAvailable(from: 10, unless: { false }) == nil)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func discardingAFinishedUploadDeletesTheFile() throws {
        let destination = try temporaryDirectory().appending(component: "Phone.mp4")
        let upload = try PhoneUpload(file: destination, size: 10)
        try upload.append(Data(count: 10))
        upload.finish()

        upload.discard()

        #expect(upload.progress == .finished)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}

@MainActor
final class RunningPhoneServer {
    let folder: URL
    let server: PhoneServer
    let port: UInt16
    private(set) var started: [PhoneUpload] = []
    private(set) var ended: [PhoneUpload] = []
    private(set) var links: [URL] = []

    init() async throws {
        folder = try temporaryDirectory()
        let server = try PhoneServer(destination: folder)
        self.server = server
        let port = await withCheckedContinuation { continuation in
            server.start { continuation.resume(returning: $0) }
        }
        self.port = try #require(port)
        server.onUploadStarted = { [unowned self] in started.append($0) }
        server.onUploadEnded = { [unowned self] in ended.append($0) }
        server.onLink = { [unowned self] in links.append($0) }
    }

    deinit {
        server.stopListening()
    }

    func url(_ path: String, token: String? = nil) -> URL {
        URL(string: "http://127.0.0.1:\(port)/\(token ?? server.token)\(path)")!
    }

    func waitUntilStarted() async throws {
        try await waitUntil { !started.isEmpty }
    }

    func nextEnded() async throws -> PhoneUpload {
        try await waitUntil { !ended.isEmpty }
        return ended.removeFirst()
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw HeadlessSessionTimeout() }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
