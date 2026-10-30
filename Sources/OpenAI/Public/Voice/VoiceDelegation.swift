import Foundation

/// A client-owned request for the application’s existing agent and tools.
public struct VoiceDelegation: Sendable {
    /// Service-provided identity used when returning a result.
    public let id: String
    /// Codex task text or public Live transcript context for the delegated request.
    public let text: String
    /// Spoken user row associated with this task, when it is already known.
    public let userMessageID: String?

    /// Retains the service identity while carrying transcript association into the host’s existing queue.
    public init(id: String, text: String, userMessageID: String? = nil) {
        self.id = id; self.text = text; self.userMessageID = userMessageID
    }
}
