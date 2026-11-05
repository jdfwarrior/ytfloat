import Foundation

public struct Command: Codable, Sendable {
    public enum Action: String, Codable, Sendable { case video, show, hide, quit, status }
    public let action: Action
    public let video: VideoRequest?
    public init(_ action: Action, video: VideoRequest? = nil) { self.action = action; self.video = video }
    public func validate() throws {
        guard (action == .video) == (video != nil) else { throw InputError.invalidVideo }
    }
}

public struct CommandReply: Codable, Sendable {
    public let ok: Bool
    public let message: String
    public init(ok: Bool = true, message: String = "OK") { self.ok = ok; self.message = message }
}
