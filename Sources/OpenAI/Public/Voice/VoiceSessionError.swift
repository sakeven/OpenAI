#if canImport(WebKit) && (os(iOS) || os(macOS))
import Foundation

/// User-facing failures at the microphone, transport, and service boundaries.
@available(iOS 17.0, macOS 14.0, *)
public enum VoiceSessionError: LocalizedError {
    /// The account or workspace rejected voice access.
    case unavailable
    /// Capture was denied by the operating system.
    case microphoneDenied
    /// A call could not establish a media connection in time.
    case connectionFailed
    /// The reading session never completed.
    case readingTimedOut
    /// The server returned something other than a valid audio SDP answer.
    case invalidResponse
    /// A full text payload exceeds the negotiated data-channel limit.
    case textTooLong
    /// A service or media error with a meaningful description.
    case server(String)

    /// Localized messages shared by the native voice panel and Translation alerts.
    public var errorDescription: String? {
        switch self {
        case .unavailable:
            String(localized: "Voice is unavailable for this account. Check your credentials and voice access.")
        case .microphoneDenied:
            String(localized: "Allow microphone access in System Settings to start a voice conversation.")
        case .connectionFailed:
            String(localized: "Voice connection lost. Check your network and try again.")
        case .readingTimedOut:
            String(localized: "Reading did not finish in time. Please try a shorter passage.")
        case .invalidResponse:
            String(localized: "The voice service returned an invalid response.")
        case .textTooLong:
            String(localized: "This text is too long for one voice request. Please select a shorter passage.")
        case .server(let message): message
        }
    }
}

#endif
