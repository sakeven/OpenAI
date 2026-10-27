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
                "model": model, "instructions": instructions + """

                Application context updates may arrive with a first line beginning "Text part N/M".
                This line is transport metadata, not text to speak. Collect all parts in order and wait
                for the part marked "(final)" before using their combined bodies as one complete update.
                Apply the original instructions to that combined text. Never read part headings aloud.
                """,
                "audio": ["output": ["voice": voice]],
                "delegation": ["type": "client"], "initial_items": history
            ]
        ])
        return request
    }

    /// Splits oversized updates without losing text; UTF-8 bytes conservatively bound the byte-token budget.
    static func contextEvents(_ text: String, delegationID: String? = nil) -> [[String: Any]] {
        // The server limits each appended text to 500 tokens. Leave room for part instructions,
        // and split at scalar boundaries so Chinese, emoji and combining marks round-trip intact.
        guard text.utf8.count > 500 else { return [context(text, delegationID: delegationID)] }
        var parts: [String] = []
        var part = ""
        var byteCount = 0
        for scalar in text.unicodeScalars {
            let size = scalar.utf8.count
            if byteCount + size > 400 {
                parts.append(part)
                part = ""
                byteCount = 0
            }
            part.unicodeScalars.append(scalar)
            byteCount += size
        }
        if !part.isEmpty { parts.append(part) }
        return parts.enumerated().map { index, part in
            let direction = index == parts.count - 1
                ? "(final); now use the complete text."
                : "; wait for the final part."
            return context("Text part \(index + 1)/\(parts.count) \(direction)\n\(part)", delegationID: delegationID)
        }
    }

    /// Builds one bounded append, retaining the existing Codex event dialect and task identity.
    private static func context(_ text: String, delegationID: String?) -> [String: Any] {
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
