#if canImport(AVFoundation) && (os(iOS) || os(macOS))
import Foundation

/// Loads a short voice sample without starting a microphone or a chat session.
@available(iOS 17.0, macOS 14.0, *)
enum VoicePreviewAudio {
    /// Public voices read the localized sample; Codex voices use their official catalog previews.
    static func load(voice: String, language: String, text: String,
                     authentication: VoiceSessionAuthentication, urlSession: URLSession) async throws -> Data {
        switch authentication {
        case .apiKey(let token, let host):
            return try await RealtimeSpeech.synthesize(text, host: host, apiKey: token, voice: voice)
        case .codexOAuth(let token, let accountID):
            let request = catalogRequest(language: language, token: token, accountID: accountID)
            let catalog = try await data(for: request, urlSession: urlSession)
            let url = try previewURL(voice: voice, catalog: catalog)
            try Task.checkCancellation()
            // Download the public sample separately so OAuth headers never reach its CDN.
            return try await data(for: URLRequest(url: url, timeoutInterval: 30), urlSession: urlSession)
        }
    }

    /// Matches the desktop voice picker while keeping credentials confined to ChatGPT.
    static func catalogRequest(language: String, token: String, accountID: String) -> URLRequest {
        var components = URLComponents(string: "https://chatgpt.com/backend-api/settings/voices")!
        components.queryItems = [URLQueryItem(name: "voice_mode", value: "wingman"),
                                 URLQueryItem(name: "spoken_language", value: language)]
        var request = URLRequest(url: components.url!, timeoutInterval: 30)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        return request
    }

    /// Uses backend identifiers, including voices whose displayed names differ from their IDs.
    static func previewURL(voice: String, catalog: Data) throws -> URL {
        let catalog = try JSONDecoder().decode(Catalog.self, from: catalog)
        guard let url = catalog.voices.first(where: { $0.voice == voice })?.preview_url,
              url.scheme == "https", url.host != nil else { throw URLError(.badServerResponse) }
        return url
    }

    /// Rejects service failures before JSON decoding or audio playback.
    private static func data(for request: URLRequest, urlSession: URLSession) async throws -> Data {
        let (data, response) = try await urlSession.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
        return data
    }

    /// Only the preview fields from the desktop catalog are needed here.
    private struct Catalog: Decodable {
        /// Available voices for this account and language.
        let voices: [Entry]
    }

    /// Associates an official preview with the exact service voice identifier.
    private struct Entry: Decodable {
        /// Backend ID rather than the translated display name.
        let voice: String
        /// Some account-specific voices may not provide a sample.
        let preview_url: URL?
    }
}
#endif
