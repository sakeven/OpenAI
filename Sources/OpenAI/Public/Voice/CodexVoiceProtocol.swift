#if canImport(WebKit) && (os(iOS) || os(macOS))
import Foundation

/// Codex's desktop voice wire format, shared by chat and the Translation extension.
@available(iOS 17.0, macOS 14.0, *)
enum CodexVoiceProtocol {
    /// Voice model verified against the installed desktop client and the live call endpoint.
    static let model = "gpt-live-1.1-codex"
    /// Client version used by the verified desktop voice handshake.
    static let version = "0.164.0-alpha.11.1"

    /// Builds the native OAuth handshake; credentials never enter the WebKit document.
    static func request(sdp: String, accessToken: String, accountID: String,
                        instructions: String, history: [[String: Any]], threadID: String, voice: String = "cove") throws -> URLRequest {
        let url = URL(string: "https://chatgpt.com/backend-api/codex/realtime/calls?intent=quicksilver&architecture=avas")!
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        for (key, value) in [
            "Authorization": "Bearer \(accessToken)", "ChatGPT-Account-Id": accountID,
            "Content-Type": "application/json", "OpenAI-Alpha": "quicksilver=v2",
            "originator": "codex_cli_rs", "version": version,
            "User-Agent": "codex_cli_rs/\(version)", "Thread-Id": threadID,
            "Session-Id": UUID().uuidString
        ] { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "sdp": sdp,
            "session": [
                "model": model, "instructions": instructions,
                "audio": ["output": ["voice": voice]],
                "delegation": ["type": "client"], "initial_items": history
            ]
        ])
        return request
    }

    /// Appends the complete text in one command, preserving Unicode and paragraph boundaries.
    static func context(_ text: String, delegationID: String? = nil) -> [String: Any] {
        var event: [String: Any] = [
            "type": delegationID == nil ? "session.context.append" : "delegation.context.append",
            "channel": "speakable", "content": [["type": "input_text", "text": text]]
        ]
        if let delegationID { event["delegation_item_id"] = delegationID }
        return event
    }

    /// Extracts a client delegation without accepting requests for other targets.
    static func delegation(from event: [String: Any]) -> (id: String, text: String)? {
        guard event["type"] as? String == "delegation.created",
              let item = event["item"] as? [String: Any],
              item["type"] as? String == "delegation", item["target"] as? String == "client",
              let id = item["id"] as? String, let content = item["content"] as? [[String: Any]] else { return nil }
        let text = content.filter { $0["type"] as? String == "input_text" }
            .compactMap { $0["text"] as? String }.joined()
        return text.isEmpty ? nil : (id, text)
    }

    /// Converts rejected handshakes into actionable errors while retaining server error messages.
    static func answer(data: Data, response: URLResponse) throws -> String {
        guard let response = response as? HTTPURLResponse else { throw VoiceSessionError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            if [401, 403].contains(response.statusCode) { throw VoiceSessionError.unavailable }
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let error = object?["error"] as? [String: Any]
            throw VoiceSessionError.server(error?["message"] as? String
                ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode))
        }
        let answer = String(decoding: data, as: UTF8.self)
        guard answer.hasPrefix("v=0"), answer.contains("m=audio") else { throw VoiceSessionError.invalidResponse }
        return answer
    }
}

#endif
