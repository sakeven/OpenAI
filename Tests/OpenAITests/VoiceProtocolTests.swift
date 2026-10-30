#if canImport(WebKit) && (os(iOS) || os(macOS))
import Foundation
import XCTest
@testable import OpenAI

/// Tests both wire dialects against the same history, context and delegation contract.
@available(iOS 17.0, macOS 14.0, *)
final class VoiceProtocolTests: XCTestCase {
    /// Public Live uses JSON, full startup history and client delegation, with credentials confined to headers.
    func testPublicHandshake() throws {
        let text = String(repeating: "完整正文🙂\n", count: 4000)
        let request = try LiveVoiceProtocol.request(sdp: "v=0\r\nm=audio", authentication: .apiKey(token: "secret", host: "gateway.example"),
            instructions: "Glossary: AnyNotes", history: [VoiceMessage(role: .user, text: text).wireValue], threadID: "thread", voice: "cedar")
        XCTAssertEqual(request.url?.absoluteString, "https://gateway.example/v1/live/sessions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertNil(request.value(forHTTPHeaderField: "OpenAI-Alpha"))
        XCTAssertNil(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"))
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("secret"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual((object["transport"] as? [String: Any])?["sdp"] as? String, "v=0\r\nm=audio")
        let session = try XCTUnwrap(object["session"] as? [String: Any])
        XCTAssertEqual(session["model"] as? String, "gpt-live-1")
        XCTAssertEqual(session["store"] as? Bool, false)
        XCTAssertEqual((session["delegation"] as? [String: Any])?["type"] as? String, "client")
        XCTAssertNil(session["tools"])
        XCTAssertNil((session["audio"] as? [String: Any])?["input"])
        let input = try XCTUnwrap(session["input"] as? [[String: Any]])
        XCTAssertEqual((input.first?["content"] as? [[String: Any]])?.first?["text"] as? String, text)
        XCTAssertTrue((session["instructions"] as? String)?.contains("Glossary: AnyNotes") == true)
    }

    /// Codex retains its established endpoint, model, headers and initial history through the shared builder.
    func testCodexHandshake() throws {
        let request = try LiveVoiceProtocol.request(sdp: "v=0\r\nm=audio", authentication: .codexOAuth(accessToken: "token", accountID: "account"),
            instructions: "Test", history: [VoiceMessage(role: .assistant, text: "History").wireValue], threadID: "thread", voice: "juniper")
        XCTAssertEqual(request.url?.path, "/backend-api/codex/realtime/calls")
        XCTAssertEqual(request.value(forHTTPHeaderField: "OpenAI-Alpha"), "quicksilver=v2")
        XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "account")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        let session = try XCTUnwrap(object["session"] as? [String: Any])
        XCTAssertEqual(session["model"] as? String, "gpt-live-1.1-codex")
        XCTAssertEqual((session["initial_items"] as? [[String: Any]])?.count, 1)
        XCTAssertNil(session["input"])
        XCTAssertEqual(((session["audio"] as? [String: Any])?["output"] as? [String: Any])?["voice"] as? String, "juniper")
        XCTAssertTrue((session["instructions"] as? String)?.contains("Never read part headings aloud.") == true)
    }

    /// Shared chunking round-trips complete results, including a single oversized grapheme cluster.
    func testContextPreservesAllTextInBothDialects() throws {
        let samples = ["", "今天可以办理。", String(repeating: "a", count: 500), String(repeating: "a", count: 501),
            String(repeating: "结果 \"quoted\" 杭州🙂 e\u{301} 👩🏽‍💻\n", count: 4000), "a" + String(repeating: "\u{301}", count: 1000)]
        for codex in [false, true] {
            for delegationID: String? in [nil, "task"] {
                for text in samples {
                    let events = LiveVoiceProtocol.contextEvents(text, delegationID: delegationID, usesCodex: codex)
                    var restored = ""
                    for (index, event) in events.enumerated() {
                        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: event)) as? [String: Any])
                        let payload: String
                        if codex {
                            XCTAssertEqual(object["type"] as? String, delegationID == nil ? "session.context.append" : "delegation.context.append")
                            XCTAssertEqual(object["delegation_item_id"] as? String, delegationID)
                            payload = try XCTUnwrap((object["content"] as? [[String: Any]])?.first?["text"] as? String)
                        } else {
                            XCTAssertEqual(object["type"] as? String, "session.commentary.append")
                            XCTAssertEqual(object["delegation_id"] as? String, delegationID)
                            if delegationID == nil { XCTAssertTrue(object["delegation_id"] is NSNull) }
                            payload = try XCTUnwrap(object["content"] as? String)
                        }
                        XCTAssertLessThanOrEqual(payload.utf8.count, 500)
                        if events.count == 1 { restored = payload }
                        else {
                            let newline = try XCTUnwrap(payload.firstIndex(of: "\n"))
                            XCTAssertEqual(payload[..<newline].contains("(final)"), index == events.count - 1)
                            restored += payload[payload.index(after: newline)...]
                        }
                    }
                    XCTAssertEqual(Array(restored.utf8), Array(text.utf8))
                }
            }
        }
    }

    /// Public metadata and Codex task text share identity handling, while other delegation targets are rejected.
    func testDelegations() throws {
        let live: [String: Any] = ["type": "session.delegation.created", "offset_ms": 1200,
            "delegation": ["type": "delegation", "target": "client", "id": "live-task"]]
        let request = try XCTUnwrap(LiveVoiceProtocol.delegation(from: live))
        XCTAssertEqual(request.id, "live-task")
        XCTAssertEqual(request.offset, 1200)
        XCTAssertNil(request.text)
        let codex: [String: Any] = ["type": "delegation.created", "item": ["type": "delegation", "target": "client", "id": "codex-task",
            "content": [["type": "input_text", "text": "Find my note"]]]]
        XCTAssertEqual(LiveVoiceProtocol.delegation(from: codex)?.text, "Find my note")
        XCTAssertNil(LiveVoiceProtocol.delegation(from: ["type": "session.delegation.created", "offset_ms": 0,
            "delegation": ["type": "delegation", "target": "responses", "id": "other"]]))
    }

    /// Only the documented answer format is accepted for each backend, with useful HTTP failures retained.
    func testHandshakeAnswers() throws {
        let url = URL(string: "https://api.openai.com/v1/live/sessions")!
        let ok = HTTPURLResponse(url: url, statusCode: 201, httpVersion: nil, headerFields: nil)!
        let sdp = "v=0\r\nm=audio"
        let json = try JSONSerialization.data(withJSONObject: ["session": ["id": "live_1"], "transport": ["type": "webrtc", "sdp": sdp]])
        XCTAssertEqual(try LiveVoiceProtocol.answer(data: json, response: ok, usesCodex: false), sdp)
        XCTAssertEqual(try LiveVoiceProtocol.answer(data: Data(sdp.utf8), response: ok, usesCodex: true), sdp)
        XCTAssertThrowsError(try LiveVoiceProtocol.answer(data: json, response: ok, usesCodex: true))
        XCTAssertThrowsError(try LiveVoiceProtocol.answer(data: Data(sdp.utf8), response: ok, usesCodex: false))
        let denied = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try LiveVoiceProtocol.answer(data: Data(), response: denied, usesCodex: false))
    }
}
#endif
