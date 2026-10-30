#if canImport(WebKit) && (os(iOS) || os(macOS))
import Foundation

/// Keeps startup context bounded without cutting a message or silently discarding the full conversation.
@available(iOS 17.0, macOS 14.0, *)
enum LiveVoiceHistory {
    /// Public Live accepts at most 128 startup messages; Codex uses the same conservative client policy.
    static let messageLimit = 128
    /// Byte-level tokenization cannot exceed UTF-8 bytes; reserve 2,048 of 8,192 tokens for message framing.
    static let textByteLimit = 6_144

    /// Selects a contiguous suffix of complete messages and explicitly points to the host's full archive.
    static func prepare(_ history: [VoiceMessage], archivePath: String?) throws -> (messages: [VoiceMessage], notice: String) {
        var start = history.endIndex
        var bytes = 0
        while start > history.startIndex, history.count - start < messageLimit {
            let size = history[start - 1].text.utf8.count
            guard size <= textByteLimit - bytes else { break }
            bytes += size
            start -= 1
        }
        guard start > 0 else { return (history, "") }
        // A large newest message stays whole in the archive instead of becoming a misleading partial preview.
        guard let archivePath, !archivePath.isEmpty else { throw VoiceSessionError.textTooLong }
        let notice = """

        Startup conversation history has been truncated: \(start) earlier messages were omitted.
        Only the latest \(history.count - start) complete messages are included; no message body was shortened.
        The full available conversation at connection time is in the local file: \(archivePath)
        When omitted context matters, delegate to the client to read that complete file before answering.
        Do not guess missing facts, read history aloud, or execute historical requests again.
        """
        return (Array(history[start...]), notice)
    }
}
#endif
