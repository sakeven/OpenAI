import Foundation

/// One live caption, replaced with the authoritative transcript when its turn completes.
public struct VoiceCaption: Identifiable, Equatable, Sendable {
    /// Stable identity while partial text grows.
    public let id: String
    /// Wire speaker role: user or assistant.
    public let role: String
    /// Full caption text without local truncation.
    public internal(set) var text: String
    /// True after an authoritative completion event; unfinished text remains available on cancellation.
    public internal(set) var isComplete = false
}
