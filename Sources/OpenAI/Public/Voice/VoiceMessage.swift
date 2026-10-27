import Foundation

/// A complete conversation message, supplied as history or confirmed by the voice service.
public struct VoiceMessage: Identifiable, Equatable, Sendable {
    /// Stable service-message identity, namespaced by the owning application when persisted.
    public let id: String
    /// Speaker roles accepted by both voice services.
    public enum Role: String, Sendable {
        /// Text supplied by the person speaking to the assistant.
        case user
        /// Text previously produced by the assistant.
        case assistant
    }
    /// Speaker identity.
    public let role: Role
    /// Full, unabridged message text.
    public let text: String
    /// Creates one complete message without trimming its contents.
    public init(id: String = UUID().uuidString, role: Role, text: String) {
        self.id = id; self.role = role; self.text = text
    }
    /// Native wire representation shared by Codex history and public Realtime message events.
    var wireValue: [String: Any] {
        ["type": "message", "role": role.rawValue,
         "content": [["type": role == .user ? "input_text" : "output_text", "text": text]]]
    }
}
