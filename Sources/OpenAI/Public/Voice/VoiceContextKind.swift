/// Distinguishes reference information from a result intended for speech in either Live protocol.
public enum VoiceContextKind: Sendable {
    /// Adds facts for relevant future replies without requesting an immediate announcement.
    case background
    /// Supplies a result the model should explain aloud, potentially paraphrasing it.
    case spoken
}
