#if canImport(WebKit) && (os(iOS) || os(macOS))
import WebKit

/// Weak forwarding avoids retaining a session through its WebKit message handler.
@available(iOS 17.0, macOS 14.0, *)
@MainActor final class VoiceMessageHandler: NSObject, WKScriptMessageHandler {
    /// The session owns its WebView, so the reverse reference must be weak.
    weak var session: RealtimeVoiceSession?
    /// Attaches the bridge to one session.
    init(session: RealtimeVoiceSession) { self.session = session }
    /// Forwards messages to the session's origin and identity checks.
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        session?.receive(message)
    }
}
#endif
