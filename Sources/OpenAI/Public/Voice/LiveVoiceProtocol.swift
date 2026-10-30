#if canImport(WebKit) && (os(iOS) || os(macOS))
import Foundation

/// Shared Live call configuration and context delivery, with the public and Codex wire differences isolated here.
@available(iOS 17.0, macOS 14.0, *)
enum LiveVoiceProtocol {
    /// Client version required by the established Codex OAuth endpoint.
    static let version = "0.164.0-alpha.11.1"

    /// Builds either authenticated handshake without exposing credentials to the media document.
    static func request(sdp: String, authentication: VoiceSessionAuthentication,
                        instructions: String, history: [[String: Any]], threadID: String, voice: String?) throws -> URLRequest {
        let codex = authentication.isCodex
        var session: [String: Any] = [
            "model": codex ? "gpt-live-1.1-codex" : "gpt-live-1",
            "instructions": instructions + """

            Application context updates may arrive with a first line beginning "Text part N/M".
            This line is transport metadata, not text to speak. Collect all parts in order and wait
            for the part marked "(final)" before using their combined bodies as one complete update.
            Apply the original instructions to that combined text. Never read part headings aloud.
            """,
            "audio": ["output": ["voice": voice ?? (codex ? "cove" : "marin")]],
            "delegation": ["type": "client"],
            codex ? "initial_items" : "input": history
        ]
        let url: URL
        let token: String
        var headers = ["Content-Type": "application/json"]
        switch authentication {
        case .codexOAuth(let accessToken, let accountID):
            token = accessToken
            url = URL(string: "https://chatgpt.com/backend-api/codex/realtime/calls?intent=quicksilver&architecture=avas")!
            headers.merge([
                "ChatGPT-Account-Id": accountID, "OpenAI-Alpha": "quicksilver=v2",
                "originator": "codex_cli_rs", "version": version,
                "User-Agent": "codex_cli_rs/\(version)", "Thread-Id": threadID,
                "Session-Id": UUID().uuidString
            ]) { _, new in new }
        case .apiKey(let apiKey, let host):
            token = apiKey
            var components = URLComponents()
            components.scheme = "https"
            components.host = host.isEmpty ? "api.openai.com" : host
            components.path = "/v1/live/sessions"
            guard let endpoint = components.url else { throw URLError(.badURL) }
            url = endpoint
            session["store"] = false
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        headers["Authorization"] = "Bearer \(token)"
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let body: [String: Any] = codex ? ["sdp": sdp, "session": session]
            : ["session": session, "transport": ["type": "webrtc", "sdp": sdp]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Splits oversized updates without losing text; UTF-8 bytes conservatively bound the byte-token budget.
    static func contextEvents(_ text: String, delegationID: String? = nil, kind: VoiceContextKind = .spoken, usesCodex: Bool) -> [[String: Any]] {
        // The server limits each appended text to 500 tokens. Leave room for part instructions,
        // and split at scalar boundaries so Chinese, emoji and combining marks round-trip intact.
        guard text.utf8.count > 500 else { return [context(text, delegationID: delegationID, kind: kind, usesCodex: usesCodex)] }
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
            return context("Text part \(index + 1)/\(parts.count) \(direction)\n\(part)", delegationID: delegationID,
                           kind: index == parts.count - 1 ? kind : .background, usesCodex: usesCodex)
        }
    }

    /// Maps background facts and spoken results to the verified event shape of each service.
    private static func context(_ text: String, delegationID: String?, kind: VoiceContextKind, usesCodex: Bool) -> [String: Any] {
        if !usesCodex {
            return ["type": kind == .spoken ? "session.commentary.append" : "session.thinking.append", "event_id": UUID().uuidString,
                    "delegation_id": delegationID as Any? ?? NSNull(), "content": text]
        }
        var event: [String: Any] = [
            "type": delegationID == nil ? "session.context.append" : "delegation.context.append",
            "content": [["type": "input_text", "text": text]]
        ]
        if kind == .spoken { event["channel"] = "speakable" }
        if let delegationID { event["delegation_item_id"] = delegationID }
        return event
    }

    /// Extracts only client-owned work; public Live supplies metadata while Codex supplies task text.
    static func delegation(from event: [String: Any]) -> (id: String, text: String?, offset: Int?)? {
        switch event["type"] as? String {
        case "session.delegation.created":
            guard let item = event["delegation"] as? [String: Any],
                  item["type"] as? String == "delegation", item["target"] as? String == "client",
                  let id = item["id"] as? String, let offset = event["offset_ms"] as? Int else { return nil }
            return (id, nil, offset)
        case "delegation.created":
            guard let item = event["item"] as? [String: Any],
                  item["type"] as? String == "delegation", item["target"] as? String == "client",
                  let id = item["id"] as? String, let content = item["content"] as? [[String: Any]] else { return nil }
            let text = content.filter { $0["type"] as? String == "input_text" }
                .compactMap { $0["text"] as? String }.joined()
            return text.isEmpty ? nil : (id, text, nil)
        default: return nil
        }
    }

    /// Converts rejected handshakes into actionable errors while retaining server error messages.
    static func answer(data: Data, response: URLResponse, usesCodex: Bool) throws -> String {
        guard let response = response as? HTTPURLResponse else { throw VoiceSessionError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            if [401, 403].contains(response.statusCode) { throw VoiceSessionError.unavailable }
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let error = object?["error"] as? [String: Any]
            throw VoiceSessionError.server(error?["message"] as? String
                ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode))
        }
        let answer: String
        if usesCodex {
            answer = String(decoding: data, as: UTF8.self)
        } else {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let transport = object["transport"] as? [String: Any],
                  transport["type"] as? String == "webrtc", let sdp = transport["sdp"] as? String else {
                throw VoiceSessionError.invalidResponse
            }
            answer = sdp
        }
        guard answer.hasPrefix("v=0"), answer.contains("m=audio") else { throw VoiceSessionError.invalidResponse }
        return answer
    }
}

#endif
