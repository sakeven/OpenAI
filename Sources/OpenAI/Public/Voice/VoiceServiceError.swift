#if canImport(WebKit) && (os(iOS) || os(macOS))
import Foundation

/// A rejected command or service notice; receiving one does not itself end a connected call.
@available(iOS 17.0, macOS 14.0, *)
public struct VoiceServiceError: LocalizedError, Sendable, Equatable {
    /// Service-provided diagnostic code, which may be absent.
    public let code: String?
    /// Outgoing command identity when the service can identify the rejected command.
    public let clientEventID: String?
    /// Human-readable service explanation retained for the host's existing error presentation.
    public let message: String

    /// Normalizes public nested errors and Codex's nested, string or top-level messages.
    init(event: [String: Any]) {
        let error = event["error"] as? [String: Any]
        code = error?["code"] as? String ?? event["code"] as? String
        clientEventID = error?["client_event_id"] as? String ?? event["client_event_id"] as? String
        message = error?["message"] as? String ?? event["message"] as? String
            ?? event["error"] as? String ?? String(localized: "The voice service returned an invalid response.")
    }

    /// Exposes the original service message without replacing a recoverable error with a connection failure.
    public var errorDescription: String? { message }
}
#endif
