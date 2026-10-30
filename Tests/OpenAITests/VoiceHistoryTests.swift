#if canImport(WebKit) && (os(iOS) || os(macOS))
import Foundation
import XCTest
@testable import OpenAI

/// Ensures long-chat reconnects stay within startup limits while retaining a route to every omitted message.
@available(iOS 17.0, macOS 14.0, *)
final class VoiceHistoryTests: XCTestCase {
    /// A short conversation reaches either backend unchanged and needs no archive notice.
    func testShortHistoryIsUnchanged() throws {
        let history = [VoiceMessage(role: .user, text: "你好🙂"), VoiceMessage(role: .assistant, text: "你好！")]
        let prepared = try LiveVoiceHistory.prepare(history, archivePath: nil)
        XCTAssertEqual(prepared.messages, history)
        XCTAssertTrue(prepared.notice.isEmpty)
    }

    /// The 128-message ceiling retains a chronological suffix and explicitly identifies omitted history.
    func testMessageLimitKeepsLatestWholeMessages() throws {
        let history = (0..<200).map { VoiceMessage(id: "\($0)", role: .user, text: "Message \($0)") }
        let prepared = try LiveVoiceHistory.prepare(history, archivePath: "/workspace/inputs/voice-history.json")
        XCTAssertEqual(prepared.messages, Array(history.suffix(128)))
        XCTAssertTrue(prepared.notice.contains("truncated"))
        XCTAssertTrue(prepared.notice.contains("72 earlier messages"))
        XCTAssertTrue(prepared.notice.contains("/workspace/inputs/voice-history.json"))
    }

    /// Byte budgeting preserves Chinese and combining characters without slicing even one message.
    func testMultilingualByteBoundary() throws {
        let newest = VoiceMessage(role: .assistant, text: String(repeating: "中", count: 2_048))
        let history = [VoiceMessage(role: .user, text: "Old 👩🏽‍💻 e\u{301}"), newest]
        let prepared = try LiveVoiceHistory.prepare(history, archivePath: "/workspace/history.json")
        XCTAssertEqual(prepared.messages, [newest])
        XCTAssertEqual(prepared.messages.reduce(0) { $0 + $1.text.utf8.count }, 6_144)
        XCTAssertEqual(history[0].text, "Old 👩🏽‍💻 e\u{301}")
    }

    /// An oversized latest message remains available in the archive, never as an incomplete body preview.
    func testOversizedNewestMessageUsesOnlyArchiveReference() throws {
        let history = [VoiceMessage(role: .user, text: "Old"),
                       VoiceMessage(role: .assistant, text: String(repeating: "完整正文🙂", count: 3_000))]
        let prepared = try LiveVoiceHistory.prepare(history, archivePath: "/workspace/history.json")
        XCTAssertTrue(prepared.messages.isEmpty)
        XCTAssertTrue(prepared.notice.contains("2 earlier messages"))
        XCTAssertTrue(prepared.notice.contains("delegate to the client"))
        XCTAssertTrue(prepared.notice.contains("/workspace/history.json"))
    }

    /// SDK consumers cannot silently omit oversized history without supplying a recoverable full-file location.
    func testMissingArchiveRejectsOmission() {
        let history = [VoiceMessage(role: .user, text: String(repeating: "x", count: 6_145))]
        for path: String? in [nil, ""] {
            XCTAssertThrowsError(try LiveVoiceHistory.prepare(history, archivePath: path)) { error in
                guard case VoiceSessionError.textTooLong = error else { return XCTFail("Unexpected error: \(error)") }
            }
        }
    }

    /// The selected messages and explicit archive instructions feed both existing handshake shapes.
    func testBothHandshakesUseSameHistoryPolicy() throws {
        let history = (0..<150).map { VoiceMessage(role: $0.isMultiple(of: 2) ? .user : .assistant, text: "History \($0)") }
        let prepared = try LiveVoiceHistory.prepare(history, archivePath: "/workspace/history.json")
        for codex in [false, true] {
            let auth: VoiceSessionAuthentication = codex ? .codexOAuth(accessToken: "token", accountID: "account")
                : .apiKey(token: "token", host: "api.openai.com")
            let request = try LiveVoiceProtocol.request(sdp: "v=0\r\nm=audio", authentication: auth,
                instructions: "Rules" + prepared.notice, history: prepared.messages.map(\.wireValue), threadID: "thread", voice: nil)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            let session = try XCTUnwrap(object["session"] as? [String: Any])
            let input = try XCTUnwrap(session[codex ? "initial_items" : "input"] as? [[String: Any]])
            XCTAssertEqual(input.count, 128)
            XCTAssertTrue((session["instructions"] as? String)?.contains("/workspace/history.json") == true)
            let texts = input.compactMap { ($0["content"] as? [[String: Any]])?.first?["text"] as? String }
            XCTAssertEqual(texts, history.suffix(128).map(\.text))
        }
    }
}
#endif
