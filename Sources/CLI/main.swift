import Foundation
import Darwin
#if SWIFT_PACKAGE
import YTFloatCore
#endif

private let help = """
YTFloat — a little window for YouTube

Usage: ytfloat "https://youtu.be/VIDEO_ID?t=1m30s"
       ytfloat --show | --hide | --quit | --status | --help | --version

Supports watch, youtu.be, Shorts, live, and embed links.
An existing player is reused. Closing the player quits the app.
--show starts YTFloat if necessary; --hide and --quit never launch it.
Set YTFLOAT_APP to the app bundle path to override app discovery.
"""

private func appURL() throws -> URL {
    let fm = FileManager.default
    var candidates: [URL] = []
    if let override = ProcessInfo.processInfo.environment["YTFLOAT_APP"] { candidates.append(URL(fileURLWithPath: override)) }
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    candidates.append(executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
    candidates.append(URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("dist/YTFloat.app"))
    candidates.append(fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications/YTFloat.app"))
    candidates.append(URL(fileURLWithPath: "/Applications/YTFloat.app"))
    guard let found = candidates.first(where: {
        $0.pathExtension == "app" && fm.isExecutableFile(atPath: $0.appendingPathComponent("Contents/MacOS/YTFloat").path)
    }) else { throw IPCError.system("YTFloat.app was not found. Run script/build.sh, or set YTFLOAT_APP to its path.") }
    return found
}

private func launch(_ app: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-g", app.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw IPCError.system("macOS could not launch YTFloat.app.") }
}

private func report(_ reply: CommandReply, for command: Command) throws {
    guard reply.ok else { throw IPCError.system(reply.message) }
    if command.action == .status { print(reply.message) }
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    if args == ["--help"] || args == ["-h"] { print(help); exit(0) }
    if args == ["--version"] {
        let version = (try? appURL()).flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String } ?? "development"
        print("YTFloat \(version)")
        exit(0)
    }
    guard args.count == 1 else { throw IPCError.system(help) }
    let command: Command
    switch args[0] {
    case "--show": command = Command(.show)
    case "--hide": command = Command(.hide)
    case "--quit": command = Command(.quit)
    case "--status": command = Command(.status)
    default:
        guard !args[0].hasPrefix("-") else { throw IPCError.system("Unknown option: \(args[0]). Use --help.") }
        command = Command(.video, video: try VideoRequest(url: args[0]))
    }
    let paths = try IPCPaths()
    if let reply = try? IPCClient.send(command, paths: paths) {
        try report(reply, for: command); exit(0)
    }
    if command.action == .quit || command.action == .hide { exit(0) }
    if command.action == .status { try report(try IPCClient.send(command, paths: paths), for: command); exit(0) }
    // Serializes only startup. A separate lifetime lock inside the app protects direct launches too.
    let deadline = Date().addingTimeInterval(10)
    var lock: FileLock?
    while lock == nil, Date() < deadline {
        do { lock = try FileLock(path: paths.directory + "/launch.lock") }
        catch IPCError.alreadyRunning { Thread.sleep(forTimeInterval: 0.05) }
    }
    guard let lock else { throw IPCError.system("Timed out waiting for another YTFloat launch.") }
    try withExtendedLifetime(lock) {
        if let reply = try? IPCClient.send(command, paths: paths) { try report(reply, for: command); return }
        try launch(appURL())
        let readyDeadline = Date().addingTimeInterval(8)
        while Date() < readyDeadline {
            if let reply = try? IPCClient.send(command, paths: paths), reply.ok { try report(reply, for: command); return }
            Thread.sleep(forTimeInterval: 0.08)
        }
        throw IPCError.system("YTFloat launched but its command socket did not become ready.")
    }
} catch {
    FileHandle.standardError.write(Data("ytfloat: \(error.localizedDescription)\n".utf8))
    exit(1)
}
