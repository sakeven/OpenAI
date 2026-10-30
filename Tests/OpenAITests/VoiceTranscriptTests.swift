#if canImport(WebKit) && (os(iOS) || os(macOS))
import XCTest
@testable import OpenAI

/// Checks actual wire transcripts independently of network and microphone access.
@available(iOS 17.0, macOS 14.0, *)
final class VoiceTranscriptTests: XCTestCase {
    /// Exact fragments retain spaces and repeated words, and duplicate events do not duplicate content.
    func testLiveDeltasRemainSnapshots() {
        var state = LiveVoiceTranscript()
        let first = delta("u1", "user", "Hi", 100, 200)
        state.apply(first); state.apply(first)
        state.apply(delta("u2", "user", " hi 🙂", 200, 500))
        XCTAssertEqual(state.captions.map(\.text), ["Hi hi 🙂"])
        XCTAssertEqual(state.messages.map(\.text), ["Hi hi 🙂"])
        XCTAssertFalse(state.captions[0].isComplete)
    }

    /// Late user captions are ordered by audio time while fragment text remains in delivery order.
    func testLateInputAndOverlappingSpeech() {
        var state = LiveVoiceTranscript()
        state.apply(delta("a1", "assistant", "Tomorrow.", 1000, 2000))
        state.apply(delta("u1", "user", "When", 100, 500))
        state.apply(delta("u2", "user", " is it?", 500, 1100))
        state.apply(delta("u3", "user", " Another question", 2500, 2700))
        XCTAssertEqual(state.messages.map(\.text), ["When is it?", "Tomorrow.", " Another question"])
        XCTAssertEqual(state.messages.map(\.id), ["u1", "a1", "u3"])
    }

    /// A gap on the media timeline may split display rows but never creates an authoritative final turn.
    func testGapsPreserveFullTextWithoutFinalizing() {
        var state = LiveVoiceTranscript()
        state.apply(delta("u1", "user", "First", 0, 500))
        state.apply(delta("u2", "user", " continuation", 4000, 5000))
        XCTAssertEqual(state.messages.map(\.text).joined(), "First continuation")
        XCTAssertTrue(state.captions.allSatisfy { !$0.isComplete })
    }

    /// Metadata-only work waits for speech and retains the earlier user identity when newer speech arrives.
    func testPublicDelegationIncludesContextAndOrigin() throws {
        var state = LiveVoiceTranscript()
        XCTAssertNil(state.delegation(id: "task", offset: 1000))
        state.apply(delta("u1", "user", "Find Thursday's note", 100, 800))
        state.apply(delta("a1", "assistant", "Checking.", 1200, 1800))
        state.apply(delta("u2", "user", " Friday, actually.", 2500, 2800))
        let request = try XCTUnwrap(state.delegation(id: "task", offset: 1000))
        XCTAssertEqual(request.userMessageID, "u1")
        XCTAssertTrue(request.text.contains("Friday, actually."))
        XCTAssertTrue(request.text.contains("not guaranteed complete turns"))
        XCTAssertEqual(request.id, "task")
    }

    /// Codex completion still replaces partial text once without changing its stable row identity.
    func testCodexFinalization() {
        var state = LiveVoiceTranscript()
        state.apply(["type": "input_transcript.added", "item": ["text": "Hello"]])
        let id = state.captions.first?.id
        XCTAssertTrue(state.messages.isEmpty)
        let done: [String: Any] = ["type": "turn.done", "turn": ["id": "server-user", "role": "user", "transcript": "Hello there."]]
        state.apply(done); state.apply(done)
        state.apply(["type": "input_transcript.added", "item": ["text": "Next question"]])
        XCTAssertEqual(state.captions.count, 2)
        XCTAssertEqual(state.captions.first?.id, id)
        XCTAssertEqual(state.captions.first?.isComplete, true)
        XCTAssertEqual(state.messages.map(\.text), ["Hello there."])
    }

    /// Constructs representative public events with independent audio timestamps and service IDs.
    private func delta(_ id: String, _ role: String, _ text: String, _ start: Int, _ end: Int) -> [String: Any] {
        ["type": role == "user" ? "session.input_transcript.delta" : "session.output_transcript.delta",
         "event_id": id, "delta": text, "start_ms": start, "end_ms": end]
    }
}
#endif
