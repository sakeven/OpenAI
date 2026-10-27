import Foundation

/// Authentication and routing for the two supported voice backends.
public enum VoiceSessionAuthentication: Sendable {
    /// Public Realtime API using the caller's own key and configured host.
    case apiKey(token: String, host: String = "api.openai.com")
    /// Codex desktop voice using an already refreshed ChatGPT OAuth session.
    case codexOAuth(accessToken: String, accountID: String)

    /// Chooses the event dialect without exposing credentials to the media document.
    var isCodex: Bool {
        if case .codexOAuth = self { return true }
        return false
    }
}
