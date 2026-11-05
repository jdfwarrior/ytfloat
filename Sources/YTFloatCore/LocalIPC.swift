import Foundation
import Darwin

public enum IPCError: LocalizedError {
    case system(String), alreadyRunning, malformed, unavailable
    public var errorDescription: String? {
        switch self {
        case .system(let text): return text
        case .alreadyRunning: return "YTFloat is already running."
        case .malformed: return "Invalid command or response."
        case .unavailable: return "YTFloat is not running or did not respond."
        }
    }
}

/// The directory belongs to this user, and must never be a symlink or writable by others.
public struct IPCPaths: Sendable {
    public let directory: String
    public var socket: String { directory + "/player.sock" }
    public init(directory: String = "/tmp/ytfloat-\(getuid())") throws {
        self.directory = directory
        if mkdir(directory, 0o700) != 0, errno != EEXIST { throw IPCError.system("Cannot create private command directory.") }
        var info = stat()
        guard lstat(directory, &info) == 0, info.st_uid == getuid(),
              info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o077 == 0 else {
            throw IPCError.system("The command directory is not private or has an unexpected owner.")
        }
    }
}

public final class FileLock {
    private let descriptor: Int32
    public init(path: String, wait: Bool = false) throws {
        descriptor = Darwin.open(path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw IPCError.system("Cannot open launch lock.") }
        if flock(descriptor, LOCK_EX | (wait ? 0 : LOCK_NB)) != 0 {
            Darwin.close(descriptor)
            throw IPCError.alreadyRunning
        }
    }
    deinit { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
}

private func address(_ path: String) throws -> sockaddr_un {
    var value = sockaddr_un()
    value.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8CString)
    guard bytes.count <= MemoryLayout.size(ofValue: value.sun_path) else { throw IPCError.system("Command socket path is too long.") }
    withUnsafeMutableBytes(of: &value.sun_path) { target in target.copyBytes(from: bytes.map { UInt8(bitPattern: $0) }) }
    value.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    return value
}

private func configure(_ descriptor: Int32) {
    var yes: Int32 = 1
    setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
    var timeout = timeval(tv_sec: 2, tv_usec: 0)
    setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
    setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
    _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
    // Darwin may inherit O_NONBLOCK from the listening socket. Each accepted client
    // runs on a worker queue and must wait (with a timeout) for its first bytes.
    let flags = fcntl(descriptor, F_GETFL)
    if flags >= 0 { _ = fcntl(descriptor, F_SETFL, flags & ~O_NONBLOCK) }
}

private func sendLine<T: Encodable>(_ value: T, to descriptor: Int32) throws {
    var data = try JSONEncoder().encode(value)
    data.append(10)
    try data.withUnsafeBytes { bytes in
        var count = 0
        while count < bytes.count {
            let sent = Darwin.send(descriptor, bytes.baseAddress!.advanced(by: count), bytes.count - count, 0)
            if sent < 0, errno == EINTR { continue }
            guard sent > 0 else { throw IPCError.unavailable }
            count += sent
        }
    }
}

private func receiveLine<T: Decodable>(_ type: T.Type, from descriptor: Int32) throws -> T {
    var data = Data()
    var bytes = [UInt8](repeating: 0, count: 1024)
    let deadline = Date().addingTimeInterval(3)
    while data.count < 8192, Date() < deadline {
        let count = recv(descriptor, &bytes, min(bytes.count, 8192 - data.count), 0)
        if count < 0, errno == EINTR { continue }
        guard count > 0 else { throw IPCError.system("Cannot read command response (\(count)): \(String(cString: strerror(errno)))") }
        data.append(contentsOf: bytes.prefix(count))
        if let newline = data.firstIndex(of: 10) {
            return try JSONDecoder().decode(type, from: data.prefix(upTo: newline))
        }
    }
    throw IPCError.malformed
}

public enum IPCClient {
    public static func send(_ command: Command, paths: IPCPaths) throws -> CommandReply {
        try command.validate()
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw IPCError.unavailable }
        defer { Darwin.close(descriptor) }
        configure(descriptor)
        var addr = try address(paths.socket)
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { throw IPCError.system("Cannot connect to YTFloat at \(paths.socket): \(String(cString: strerror(errno)))") }
        try sendLine(command, to: descriptor)
        return try receiveLine(CommandReply.self, from: descriptor)
    }
}

public final class IPCServer {
    private let paths: IPCPaths
    private let lock: FileLock
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "co.ytfloat.ipc")
    private var activeClients = 0
    private var stopped = false
    public init(paths: IPCPaths, handler: @escaping (Command, @escaping (CommandReply) -> Void) -> Void) throws {
        self.paths = paths
        lock = try FileLock(path: paths.directory + "/instance.lock")
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw IPCError.system("Cannot create command socket.") }
        configure(descriptor)
        _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
        unlink(paths.socket) // Only the holder of the instance lock may remove a stale socket.
        var addr = try address(paths.socket)
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0, chmod(paths.socket, 0o600) == 0, listen(descriptor, 32) == 0 else {
            Darwin.close(descriptor); unlink(paths.socket)
            throw IPCError.system("Cannot listen for commands.")
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            while true {
                let client = accept(descriptor, nil, nil)
                guard client >= 0 else { break }
                guard self.activeClients < 16 else { Darwin.close(client); continue }
                self.activeClients += 1
                configure(client)
                DispatchQueue.global(qos: .userInitiated).async {
                    defer {
                        Darwin.close(client)
                        self.queue.async { self.activeClients -= 1 }
                    }
                    do {
                        let command = try receiveLine(Command.self, from: client)
                        try command.validate()
                        let ready = DispatchSemaphore(value: 0)
                        // Store the reply under a lock; the handler may execute asynchronously.
                        let box = ReplyBox()
                        handler(command) { reply in box.set(reply); ready.signal() }
                        guard ready.wait(timeout: .now() + 2) == .success else { return }
                        try sendLine(box.get(), to: client)
                    } catch { try? sendLine(CommandReply(ok: false, message: error.localizedDescription), to: client) }
                }
            }
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        self.source = source
        source.resume()
    }
    public func stop() {
        guard !stopped else { return }
        stopped = true
        source?.cancel(); source = nil
        unlink(paths.socket)
    }
    deinit { stop() }
}

private final class ReplyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var reply = CommandReply(ok: false, message: "No response")
    func set(_ value: CommandReply) { lock.lock(); defer { lock.unlock() }; reply = value }
    func get() -> CommandReply { lock.lock(); defer { lock.unlock() }; return reply }
}
