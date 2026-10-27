#if canImport(WebKit) && (os(iOS) || os(macOS))
import Foundation
import XCTest
@testable import OpenAI

/// Exercises real wire payloads and complete text preservation without using credentials or a microphone.
@available(iOS 17.0, macOS 14.0, *)
final class VoiceProtocolTests: XCTestCase {
    /// Codex requests use the verified endpoint and retain complete message history.
    func testCodexHandshakeKeepsFullHistoryAndNativeCredentials() throws {
        let text = String(repeating: "完整正文🙂\n", count: 4000)
        let history = [VoiceMessage(role: .user, text: text).wireValue]
        let request = try CodexVoiceProtocol.request(sdp: "v=0\r\nm=audio", accessToken: "test-token", accountID: "test-account",
            instructions: "Test", history: history, threadID: "test-thread", voice: "juniper")
        XCTAssertEqual(request.url?.host, "chatgpt.com")
        XCTAssertEqual(request.url?.path, "/backend-api/codex/realtime/calls")
        XCTAssertEqual(request.value(forHTTPHeaderField: "OpenAI-Alpha"), "quicksilver=v2")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("test-token"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let session = try XCTUnwrap(object["session"] as? [String: Any])
        let items = try XCTUnwrap(session["initial_items"] as? [[String: Any]])
        let contents = try XCTUnwrap(items.first?["content"] as? [[String: Any]])
        XCTAssertEqual(contents.first?["text"] as? String, text)
        XCTAssertEqual(session["model"] as? String, "gpt-live-1.1-codex")
        let instructions = try XCTUnwrap(session["instructions"] as? String)
        XCTAssertTrue(instructions.hasPrefix("Test\n"))
        XCTAssertTrue(instructions.contains("wait\nfor the part marked \"(final)\""))
        XCTAssertTrue(instructions.contains("Never read part headings aloud."))
        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        XCTAssertEqual((audio["output"] as? [String: Any])?["voice"] as? String, "juniper")
    }

    /// API-key calls preserve custom routing, multipart framing, and the separate public API contract.
    func testAPIKeyHandshakeUsesConfiguredHostAndMultipart() throws {
        let sdp = "v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n"
        let request = try RealtimeVoiceProtocol.request(sdp: sdp, token: "key", host: "gateway.example", instructions: "Read completely", voice: "cedar")
        XCTAssertEqual(request.url?.absoluteString, "https://gateway.example/v1/realtime/calls")
        XCTAssertNil(request.value(forHTTPHeaderField: "OpenAI-Alpha"))
        XCTAssertNil(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"))
        let type = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        let boundary = try XCTUnwrap(type.components(separatedBy: "boundary=").last)
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.hasSuffix("--\(boundary)--\r\n"))
        XCTAssertTrue(body.contains("name=\"sdp\"\r\n\r\n\(sdp)"))
        let json = try XCTUnwrap(body.components(separatedBy: "name=\"session\"\r\n\r\n").last?.components(separatedBy: "\r\n--").first)
        let session = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(session["model"] as? String, "gpt-realtime-2.1")
        XCTAssertEqual(session["type"] as? String, "realtime")
        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        XCTAssertEqual((audio["output"] as? [String: Any])?["voice"] as? String, "cedar")
        let tools = try XCTUnwrap(session["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.first?["name"] as? String, RealtimeVoiceProtocol.toolName)
    }

    /// Both result paths preserve all text, including quotes, newlines and non-BMP characters.
    func testResultsAreNotSilentlyTruncated() throws {
        let text = String(repeating: "结果 \"quoted\" 🙂\n", count: 4000)
        let events = CodexVoiceProtocol.contextEvents(text, delegationID: "task")
        let parts = try events.map { event -> String in
            XCTAssertEqual(event["type"] as? String, "delegation.context.append")
            XCTAssertEqual(event["delegation_item_id"] as? String, "task")
            let content = try XCTUnwrap(event["content"] as? [[String: Any]])
            let payload = try XCTUnwrap(content.first?["text"] as? String)
            XCTAssertLessThanOrEqual(payload.utf8.count, 500)
            return String(payload.drop(while: { $0 != "\n" }).dropFirst())
        }
        XCTAssertGreaterThan(events.count, 1)
        XCTAssertEqual(Array(parts.joined().utf8), Array(text.utf8))
        let item = try XCTUnwrap(RealtimeVoiceProtocol.result(text, id: "call")["item"] as? [String: Any])
        XCTAssertEqual(item["output"] as? String, text)
        XCTAssertEqual(item["call_id"] as? String, "call")
    }

    /// Short updates keep the original payload, including exact-limit and empty updates.
    func testShortContextUpdatesKeepOriginalText() throws {
        for text in ["", "今天可以办理。", String(repeating: "a", count: 500)] {
            let events = CodexVoiceProtocol.contextEvents(text)
            XCTAssertEqual(events.count, 1)
            let event = try XCTUnwrap(events.first)
            XCTAssertEqual(event["type"] as? String, "session.context.append")
            XCTAssertNil(event["delegation_item_id"])
            let content = try XCTUnwrap(event["content"] as? [[String: Any]])
            XCTAssertEqual(content.first?["text"] as? String, text)
        }
    }

    /// Resumed updates and reading use the same bound, including a single oversized grapheme cluster.
    func testSessionContextPartsPreserveUnicodeAndMarkCompletion() throws {
        let samples = [String(repeating: "a", count: 501),
                       String(repeating: "杭州, 绿牌🙂 e\u{301} 👩🏽‍💻\n", count: 100),
                       "a" + String(repeating: "\u{301}", count: 1000)]
        for text in samples {
            let events = CodexVoiceProtocol.contextEvents(text)
            var restored = ""
            for (index, event) in events.enumerated() {
                XCTAssertEqual(event["type"] as? String, "session.context.append")
                XCTAssertNil(event["delegation_item_id"])
                XCTAssertEqual(event["channel"] as? String, "speakable")
                let content = try XCTUnwrap(event["content"] as? [[String: Any]])
                let payload = try XCTUnwrap(content.first?["text"] as? String)
                XCTAssertLessThanOrEqual(payload.utf8.count, 500)
                let newline = try XCTUnwrap(payload.firstIndex(of: "\n"))
                let heading = payload[..<newline]
                XCTAssertTrue(heading.hasPrefix("Text part \(index + 1)/\(events.count)"))
                XCTAssertEqual(heading.contains("(final)"), index == events.count - 1)
                XCTAssertEqual(heading.contains("wait for the final part"), index != events.count - 1)
                restored += payload[payload.index(after: newline)...]
                // Check the actual JSON round-trip, not just the intermediate Swift string.
                let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: event)) as? [String: Any])
                let decodedContent = try XCTUnwrap(decoded["content"] as? [[String: Any]])
                XCTAssertEqual(decodedContent.first?["text"] as? String, payload)
            }
            XCTAssertEqual(Array(restored.utf8), Array(text.utf8))
        }
    }

    /// Only completed, correctly addressed tool calls may enter application execution.
    func testDelegationsRejectFailedAndMalformedCalls() throws {
        let item: [String: Any] = ["type": "function_call", "name": "delegate_to_app", "call_id": "call", "arguments": "{\"request\":\"Find my note\"}"]
        let event: [String: Any] = ["type": "response.done", "response": ["status": "completed", "output": [item]]]
        let requests = try RealtimeVoiceProtocol.delegations(from: event)
        XCTAssertEqual(requests.first?.text, "Find my note")
        XCTAssertEqual(requests.first?.id, "call")
        XCTAssertTrue(try RealtimeVoiceProtocol.delegations(from: ["type": "response.done", "response": ["status": "cancelled", "output": [item]]]).isEmpty)
        XCTAssertThrowsError(try RealtimeVoiceProtocol.delegations(from: ["type": "response.done", "response": ["status": "failed"]]))
        var malformed = item; malformed["arguments"] = "not json"
        XCTAssertThrowsError(try RealtimeVoiceProtocol.delegations(from: ["type": "response.done", "response": ["status": "completed", "output": [malformed]]]))
        XCTAssertNil(CodexVoiceProtocol.delegation(from: ["type": "delegation.created", "item": ["type": "delegation", "target": "responses"]]))
    }

    /// HTTP success is not accepted as a voice connection when the answer is HTML or JSON.
    func testHandshakeRejectsInvalidSDPAndAuthErrors() throws {
        let url = URL(string: "https://api.openai.com/v1/realtime/calls")!
        let ok = HTTPURLResponse(url: url, statusCode: 201, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try CodexVoiceProtocol.answer(data: Data("<html>gateway</html>".utf8), response: ok))
        let denied = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try CodexVoiceProtocol.answer(data: Data(), response: denied))
        XCTAssertEqual(try CodexVoiceProtocol.answer(data: Data("v=0\r\nm=audio".utf8), response: ok), "v=0\r\nm=audio")
    }
}
#endif
