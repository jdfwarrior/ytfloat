import Foundation
import Testing
import Darwin
@testable import YTFloatCore

struct VideoRequestTests {
    private let id = "dQw4w9WgXcQ"
    @Test func supportedFormsAndStartTimes() throws {
        let inputs: [(String, Int)] = [
            ("https://www.youtube.com/watch?v=\(id)", 0),
            ("https://youtu.be/\(id)?t=1h2m3s", 3723),
            ("youtube.com/shorts/\(id)?start=90", 90),
            ("https://m.youtube.com/live/\(id)?t=12s", 12),
            ("https://youtube.com/embed/\(id)#t=2m", 120),
            ("https://music.youtube.com/watch?v=\(id)&t=45", 45)
        ]
        for (input, start) in inputs {
            let request = try VideoRequest(url: input)
            #expect(request.id == id)
            #expect(request.start == start)
            #expect(try VideoRequest(url: request.url.absoluteString) == request)
        }
    }
    @Test func rejectsUnsafeOrAmbiguousInputs() {
        for input in ["https://youtube.com.evil.test/watch?v=\(id)",
            "https://evil.test/youtu.be/\(id)", "file:///\(id)",
            "https://user@youtube.com/watch?v=\(id)", "https://youtube.com:8080/watch?v=\(id)",
            "https://youtu.be/tooShort", "https://youtu.be/\(id)/extra",
            "https://youtube.com/watch?v=\(id)&v=aaaaaaaaaaa",
            "https://youtu.be/\(id)?t=-1", "https://youtu.be/\(id)?t=NaN",
            "https://youtu.be/\(id)?t=999999999999999999999999h",
            "https://youtu.be/\(id)?t=99hBAD", "https://youtu.be/\(id)?t=1&start=2",
            "https://youtu.be/\(id)?t=9999999", "javascript:alert(1)"] {
            #expect(throws: (any Error).self) { try VideoRequest(url: input) }
        }
    }
    @Test func ipcDecoderRevalidatesPayloads() throws {
        let malformed = Data(#"{"action":"video","video":{"id":"';alert(1)","start":0}}"#.utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Command.self, from: malformed) }
        #expect(throws: (any Error).self) { try Command(.video).validate() }
        #expect(throws: (any Error).self) { try Command(.quit, video: VideoRequest(id: id)).validate() }
    }
}

struct PreferencesTests {
    @Test func defaultsPersistenceAndClamping() {
        let suite = "YTFloatTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: defaults)
        #expect(prefs.alwaysOnTop && prefs.autoplay && prefs.lockAspect && prefs.showControls)
        #expect(prefs.opacity == 1)
        #expect(prefs.overlayTimeout == 3)
        prefs.opacity = 0.1
        #expect(prefs.opacity == 0.35)
        prefs.opacity = 10
        #expect(prefs.opacity == 1)
        prefs.opacity = .nan
        #expect(prefs.opacity == 1)
        prefs.opacity = 0.7
        prefs.autoplay = false; prefs.alwaysOnTop = false
        prefs.lockAspect = false; prefs.showControls = false; prefs.allSpaces = false
        prefs.overlayTimeout = 5
        let restored = Preferences(defaults: UserDefaults(suiteName: suite)!)
        #expect(restored.opacity == 0.7)
        #expect(!restored.autoplay && !restored.alwaysOnTop && !restored.lockAspect && !restored.showControls && !restored.allSpaces)
        #expect(restored.overlayTimeout == 5)
    }
}

struct IPCTests {
    private func privateDirectory() throws -> String {
        let path = "/tmp/ytf-test-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return path
    }
    @Test func roundTripAndSingleInstanceLock() throws {
        let directory = try privateDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let paths = try IPCPaths(directory: directory)
        let server = try IPCServer(paths: paths) { command, reply in reply(CommandReply(message: command.action.rawValue)) }
        defer { server.stop() }
        #expect(try IPCClient.send(Command(.show), paths: paths).message == "show")
        #expect(throws: (any Error).self) { try IPCServer(paths: paths) { _, reply in reply(CommandReply()) } }
        #expect(try IPCClient.send(Command(.hide), paths: paths).message == "hide")
        server.stop()
        #expect(!FileManager.default.fileExists(atPath: paths.socket))
    }
    @Test func concurrentCommandsReuseOneServer() async throws {
        let directory = try privateDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let paths = try IPCPaths(directory: directory)
        let server = try IPCServer(paths: paths) { _, reply in reply(CommandReply()) }
        defer { server.stop() }
        try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<8 { group.addTask { try IPCClient.send(Command(.show), paths: paths).ok } }
            for try await result in group { #expect(result) }
        }
    }
    @Test func staleSocketRecovery() throws {
        let directory = try privateDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let paths = try IPCPaths(directory: directory)
        try Data("stale".utf8).write(to: URL(fileURLWithPath: paths.socket))
        let server = try IPCServer(paths: paths) { _, reply in reply(CommandReply()) }
        defer { server.stop() }
        #expect(try IPCClient.send(Command(.show), paths: paths).ok)
    }
    @Test func waitsForDelayedClientBytes() throws {
        let directory = try privateDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let paths = try IPCPaths(directory: directory)
        let server = try IPCServer(paths: paths) { _, reply in reply(CommandReply()) }
        defer { server.stop() }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: paths.socket.utf8CString.map { UInt8(bitPattern: $0) }) }
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        #expect(result == 0)
        Thread.sleep(forTimeInterval: 0.1)
        let request = Data("{\"action\":\"show\"}\n".utf8)
        _ = request.withUnsafeBytes { send(fd, $0.baseAddress!, $0.count, 0) }
        var bytes = [UInt8](repeating: 0, count: 1024)
        let count = recv(fd, &bytes, bytes.count, 0)
        #expect(count > 0)
        if count > 0 { #expect(try JSONDecoder().decode(CommandReply.self, from: Data(bytes.prefix(count))).ok) }
    }
    @Test func rejectsPublicDirectoryAndSymlink() throws {
        let directory = try privateDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let link = directory + "-link"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: directory)
        defer { try? FileManager.default.removeItem(atPath: link) }
        #expect(throws: (any Error).self) { try IPCPaths(directory: link) }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory)
        #expect(throws: (any Error).self) { try IPCPaths(directory: directory) }
    }
}

struct HTTPServerTests {
    @Test func realHTTPServingAndFixedRoutes() async throws {
        let server = try HTTPServer(assets: ["index.html": .init(data: Data("test player".utf8), contentType: "text/html")])
        defer { server.stop() }
        let url: URL = try await withCheckedThrowingContinuation { continuation in
            server.start { continuation.resume(with: $0) }
        }
        #expect(url.host == "127.0.0.1")
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
        #expect(http.value(forHTTPHeaderField: "Referrer-Policy") == "strict-origin-when-cross-origin")
        #expect(data == Data("test player".utf8))
        let (_, missing) = try await URLSession.shared.data(from: url.deletingLastPathComponent().appendingPathComponent("Info.plist"))
        #expect((missing as? HTTPURLResponse)?.statusCode == 404)
        var request = URLRequest(url: url); request.httpMethod = "POST"
        let (_, mutation) = try await URLSession.shared.data(for: request)
        #expect((mutation as? HTTPURLResponse)?.statusCode == 405)
    }
}
