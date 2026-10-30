#if canImport(WebKit) && (os(iOS) || os(macOS))
import Foundation

/// Reconciles both Live transcript dialects without inventing a final-turn signal for the public API.
@available(iOS 17.0, macOS 14.0, *)
struct LiveVoiceTranscript {
    /// Display rows retain stable IDs as their received text grows.
    private(set) var captions: [VoiceCaption] = []
    /// Codex final turns or public Live snapshots, in approximate speech order.
    private(set) var messages: [VoiceMessage] = []
    /// Codex maintains independent unfinished user and assistant turns.
    private var partialIDs: [String: String] = [:]
    /// Service event and final-turn IDs prevent duplicate text on repeated delivery.
    private var receivedIDs: Set<String> = []
    /// Public Live timing is retained for display grouping and delegation association.
    private var intervals: [String: (start: Int, end: Int)] = [:]

    /// Applies full Codex turns and exact public transcript deltas through the same caption/message state.
    mutating func apply(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "session.input_transcript.delta", "session.output_transcript.delta":
            guard let id = event["event_id"] as? String, let text = event["delta"] as? String,
                  let start = event["start_ms"] as? Int, let end = event["end_ms"] as? Int,
                  receivedIDs.insert(id).inserted else { return }
            let role = event["type"] as? String == "session.input_transcript.delta" ? "user" : "assistant"
            // Timeline gaps only group display rows. They never confirm that an utterance has ended.
            let previous = captions.last { caption in
                guard caption.role == role, let range = intervals[caption.id] else { return false }
                return start >= range.start && start <= range.end + 1500
                    && !captions.contains { other in
                        guard other.role != role, let otherRange = intervals[other.id] else { return false }
                        return otherRange.end >= range.end && otherRange.start < start
                    }
            }
            let captionID = previous?.id ?? id
            let old = intervals[captionID]
            intervals[captionID] = (min(old?.start ?? start, start), max(old?.end ?? end, end))
            update(id: captionID, role: role, text: text, complete: false)
            captions.sort { (intervals[$0.id]?.start ?? 0) < (intervals[$1.id]?.start ?? 0) }
            if let caption = captions.first(where: { $0.id == captionID }) {
                save(id: captionID, role: role, text: caption.text)
            }
        case "input_transcript.added", "output_transcript.added":
            guard let item = event["item"] as? [String: Any], let text = item["text"] as? String else { return }
            let role = event["type"] as? String == "input_transcript.added" ? "user" : "assistant"
            let id = partialIDs[role] ?? UUID().uuidString
            partialIDs[role] = id
            update(id: id, role: role, text: text, complete: false)
        case "turn.done":
            guard let turn = event["turn"] as? [String: Any], let serviceID = turn["id"] as? String,
                  let role = turn["role"] as? String, ["user", "assistant"].contains(role),
                  let text = turn["transcript"] as? String,
                  receivedIDs.insert(serviceID).inserted else { return }
            let id = partialIDs.removeValue(forKey: role) ?? serviceID
            update(id: id, role: role, text: text, complete: true)
            save(id: id, role: role, text: text)
        default: break
        }
    }

    /// Resolves metadata-only delegations against received speech while retaining the originating user row.
    func delegation(id: String, offset: Int) -> VoiceDelegation? {
        let users = captions.filter { $0.role == "user" && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let user = users.last(where: { (intervals[$0.id]?.start ?? 0) <= offset }) ?? users.first else { return nil }
        let transcript = captions.map { caption in
            let range = intervals[caption.id]
            return "[\(caption.role), \(range?.start ?? 0)–\(range?.end ?? 0) ms] \(caption.text)"
        }.joined(separator: "\n")
        return VoiceDelegation(id: id, text: """
        The voice model delegated the user's request at \(offset) ms in this call. Resolve that request
        using the current AI Chat context and the received transcript below. These are streaming
        snapshots, not guaranteed complete turns. Later speech may clarify or correct earlier speech.
        If the request is incomplete or ambiguous, ask for clarification instead of guessing missing
        action details. Apply the chat's existing permission and confirmation rules.

        \(transcript)
        """, userMessageID: user.id)
    }

    /// Updates one shared display row, preserving whitespace and repetitions from the service.
    private mutating func update(id: String, role: String, text: String, complete: Bool) {
        if let index = captions.firstIndex(where: { $0.id == id }) {
            guard !captions[index].isComplete else { return }
            captions[index].text = complete ? text : captions[index].text + text
            captions[index].isComplete = complete
        } else {
            captions.append(.init(id: id, role: role, text: text, isComplete: complete))
        }
    }

    /// Upserts service text in caption order without replacing a delegated text agent's separate answer.
    private mutating func save(id: String, role: String, text: String) {
        guard !text.isEmpty else { return }
        let message = VoiceMessage(id: id, role: role == "user" ? .user : .assistant, text: text)
        if let index = messages.firstIndex(where: { $0.id == id }) { messages[index] = message }
        else { messages.append(message) }
        let positions = Dictionary(uniqueKeysWithValues: captions.enumerated().map { ($1.id, $0) })
        messages.sort { positions[$0.id, default: 0] < positions[$1.id, default: 0] }
    }
}
#endif
