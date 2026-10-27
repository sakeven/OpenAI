import Foundation

/// A complete request for the application's existing agent or tools.
public struct VoiceDelegation: Sendable {
    /// Service-provided identity used when returning a result.
    public let id: String
    /// Self-contained request text from the voice model.
    public let text: String
}
