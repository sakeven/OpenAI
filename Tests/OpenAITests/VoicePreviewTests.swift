#if canImport(AVFoundation) && (os(iOS) || os(macOS))
import Foundation
import XCTest
@testable import OpenAI

/// Covers catalog identity, credential isolation and cancellation before audio can start.
@available(iOS 17.0, macOS 14.0, *)
final class VoicePreviewTests: XCTestCase {
    /// Display names such as Arbor must resolve through the backend ID, not by list order.
    func testCatalogUsesVoiceIDAndRejectsMissingOrNonHTTPSPreview() throws {
        let data = Data(#"{"voices":[{"voice":"cove","preview_url":null},{"voice":"fathom","name":"Arbor","preview_url":"https://samples.example/arbor.mp3"},{"voice":"unsafe","preview_url":"file:///tmp/sample.wav"}]}"#.utf8)
        XCTAssertEqual(try VoicePreviewAudio.previewURL(voice: "fathom", catalog: data).absoluteString,
                       "https://samples.example/arbor.mp3")
        for voice in ["Arbor", "cove", "missing", "unsafe"] {
            XCTAssertThrowsError(try VoicePreviewAudio.previewURL(voice: voice, catalog: data))
        }
    }

    /// Only the catalog receives credentials; the separate CDN request must have none.
    func testCodexSampleKeepsCredentialsOffCDN() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PreviewURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); PreviewURLProtocol.handler = nil }
        var paths: [String] = []
        PreviewURLProtocol.handler = { request in
            paths.append(request.url!.path)
            if request.url?.host == "chatgpt.com" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
                XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "test-account")
                let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                XCTAssertTrue(items.contains(URLQueryItem(name: "voice_mode", value: "wingman")))
                XCTAssertTrue(items.contains(URLQueryItem(name: "spoken_language", value: "zh")))
                return (200, Data(#"{"voices":[{"voice":"cove","preview_url":"https://samples.example/cove.mp3"}]}"#.utf8))
            }
            XCTAssertEqual(request.url?.host, "samples.example")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"))
            return (200, Data([1, 2, 3]))
        }
        let data = try await VoicePreviewAudio.load(voice: "cove", language: "zh", text: "Unused for Codex",
            authentication: .codexOAuth(accessToken: "test-token", accountID: "test-account"), urlSession: session)
        XCTAssertEqual(data, Data([1, 2, 3]))
        XCTAssertEqual(paths, ["/backend-api/settings/voices", "/cove.mp3"])
    }

    /// A rejected catalog must not be treated as playable audio or trigger a second request.
    func testCatalogFailureStopsBeforeAudioDownload() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PreviewURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); PreviewURLProtocol.handler = nil }
        var requests = 0
        PreviewURLProtocol.handler = { _ in requests += 1; return (401, Data()) }
        do {
            _ = try await VoicePreviewAudio.load(voice: "cove", language: "en", text: "Sample",
                authentication: .codexOAuth(accessToken: "expired", accountID: "account"), urlSession: session)
            XCTFail("A rejected catalog must throw")
        } catch { XCTAssertEqual((error as? URLError)?.code, .badServerResponse) }
        XCTAssertEqual(requests, 1)
    }

    /// Stopping pending authentication immediately clears loading and prevents later errors from resurfacing.
    @MainActor func testStopCancelsPendingAuthentication() async {
        let player = VoicePreviewPlayer()
        let started = expectation(description: "Authentication started")
        let cancelled = expectation(description: "Authentication cancelled")
        player.play(voice: "cove", language: "zh", text: "Sample", authentication: {
            started.fulfill()
            do { try await Task.sleep(for: .seconds(60)) }
            catch { cancelled.fulfill(); throw error }
            return .codexOAuth(accessToken: "unused", accountID: "unused")
        })
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(player.isLoading)
        player.stop()
        await fulfillment(of: [cancelled], timeout: 2)
        XCTAssertFalse(player.isLoading)
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(player.error)
    }
}

/// Synchronous in-memory responses isolate HTTP behavior from credentials and real services.
private final class PreviewURLProtocol: URLProtocol {
    /// Per-test response closure, cleared after each session is invalidated.
    static var handler: ((URLRequest) throws -> (Int, Data))?
    /// Intercepts only the session explicitly configured by these tests.
    override class func canInit(with request: URLRequest) -> Bool { true }
    /// Leaves headers intact so credential isolation assertions inspect the actual request.
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    /// Returns one complete response synchronously without using a network connection.
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
                httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    /// Responses are synchronous and have no in-flight resource to release.
    override func stopLoading() {}
}
#endif
