#if canImport(WebKit) && (os(iOS) || os(macOS))
import XCTest
@testable import OpenAI

/// Checks transcript identity and ordering independently of network, playback, and microphone permission.
@available(iOS 17.0, macOS 14.0, *)
final class VoiceTranscriptTests: XCTestCase {
    /// Slower input transcription fills its original position even if the assistant finishes first.
    @MainActor func testLateInputTranscriptionKeepsConversationOrder() {
        let session = RealtimeVoiceSession()
        session.handle(["type": "input_audio_buffer.speech_started", "item_id": "user"])
        session.handle(["type": "response.output_audio_transcript.done", "item_id": "assistant", "transcript": "Tomorrow."])
        session.handle(["type": "conversation.item.input_audio_transcription.completed", "item_id": "user", "transcript": "When is it?"])
        XCTAssertEqual(session.captions.map(\.id), ["user", "assistant"])
        XCTAssertEqual(session.captions.map(\.text), ["When is it?", "Tomorrow."])
        XCTAssertTrue(session.captions.allSatisfy(\.isComplete))
    }

    /// Authoritative completion replaces partial text and repeated completion cannot duplicate the row.
    @MainActor func testPublicCaptionFinalizationIsIdempotent() {
        let session = RealtimeVoiceSession()
        session.handle(["type": "response.output_audio_transcript.delta", "item_id": "a", "delta": "partial"])
        let full = String(repeating: "完整的语音内容🙂\n", count: 4000)
        let done: [String: Any] = ["type": "response.output_audio_transcript.done", "item_id": "a", "transcript": full]
        session.handle(done)
        session.handle(done)
        session.handle(["type": "response.output_audio_transcript.delta", "item_id": "a", "delta": "late"])
        XCTAssertEqual(session.captions.count, 1)
        XCTAssertEqual(session.captions.first?.text, full)
    }

    /// Codex final turn identifiers deduplicate delivery without replacing the streaming row identity.
    @MainActor func testCodexCompletionRetainsPartialIdentity() {
        let session = RealtimeVoiceSession()
        session.handle(["type": "input_transcript.added", "item": ["text": "Hello"]])
        let id = session.captions.first?.id
        let done: [String: Any] = ["type": "turn.done", "turn": ["id": "server-user", "role": "user", "transcript": "Hello there."]]
        session.handle(done)
        session.handle(done)
        session.handle(["type": "input_transcript.added", "item": ["text": "Next question"]])
        XCTAssertEqual(session.captions.count, 2)
        XCTAssertEqual(session.captions.first?.id, id)
        XCTAssertEqual(session.captions.first?.text, "Hello there.")
        XCTAssertEqual(session.captions.last?.isComplete, false)
        XCTAssertEqual(session.messages.map(\.text), ["Hello there."])
    }

    /// Caption completion is presentation-only; storage takes the complete canonical response content instead.
    @MainActor func testCanonicalResponseIsIndependentFromCaptions() {
        let session = RealtimeVoiceSession()
        session.handle(["type": "response.output_audio_transcript.done", "item_id": "a", "transcript": "Brief spoken caption"])
        XCTAssertTrue(session.messages.isEmpty)
        let output: [[String: Any]] = [["id": "a", "type": "message", "role": "assistant",
                                      "content": [["type": "output_text", "text": "Complete canonical answer"]]]]
        session.handle(["type": "response.done", "response": ["status": "cancelled", "output": output]])
        XCTAssertTrue(session.messages.isEmpty)
        session.handle(["type": "response.done", "response": ["status": "completed", "output": output]])
        session.handle(["type": "response.done", "response": ["status": "completed", "output": output]])
        XCTAssertEqual(session.messages.map(\.text), ["Complete canonical answer"])
        XCTAssertEqual(session.captions.first?.text, "Brief spoken caption")
    }

    /// Audio-mode messages use the final response's transcript while delayed user messages retain speech order.
    @MainActor func testFinalAudioMessagesAreOrderedBeforeLateUserTranscription() {
        let session = RealtimeVoiceSession()
        session.handle(["type": "input_audio_buffer.speech_started", "item_id": "user"])
        session.handle(["type": "response.output_audio_transcript.delta", "item_id": "assistant", "delta": "Partial"])
        session.handle(["type": "response.done", "response": ["status": "completed", "output": [
            ["id": "assistant", "type": "message", "role": "assistant", "content": [["type": "output_audio", "transcript": "Final answer"]]]]]])
        session.handle(["type": "conversation.item.input_audio_transcription.completed", "item_id": "user", "transcript": "Final question"])
        XCTAssertEqual(session.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(session.messages.map(\.text), ["Final question", "Final answer"])
    }

    /// Ending or losing the connection never erases text already received for an unfinished utterance.
    @MainActor func testPartialTextRemainsAvailableAfterStop() {
        let session = RealtimeVoiceSession()
        session.handle(["type": "output_transcript.added", "item": ["text": "Still speaking"]])
        session.stop()
        XCTAssertEqual(session.captions.first?.text, "Still speaking")
        XCTAssertEqual(session.captions.first?.isComplete, false)
        XCTAssertTrue(session.messages.isEmpty)
    }
}
#endif
