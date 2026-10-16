import Foundation
import XCTest
@testable import OpenAI

/// Covers the production factory wiring between complete unknown events and middleware diagnostics.
final class ResponseStreamDiagnosticsMiddlewareTests: XCTestCase {
    /// Metadata bypasses diagnostics while unknown payloads and later business events keep their order.
    func testFactorySkipsMetadataAndForwardsOnlyUnknownPayload() async {
        let diagnostic = expectation(description: "Unknown event delivered to middleware")
        let keepalive = expectation(description: "Later event delivered to stream")
        let payload = #"{"type":"provider.new_event","metadata":{"detail":"完整内容"}}"#
        let middleware = DiagnosticsMiddleware { type, data in
            XCTAssertEqual(type, "provider.new_event")
            XCTAssertEqual(data, Data(payload.utf8))
            diagnostic.fulfill()
        }
        let factory = ImplicitURLSessionStreamingSessionFactory(
            middlewares: [middleware], parsingOptions: [], sslDelegate: nil
        )
        let session = factory.makeModelResponseStreamingSession(
            urlRequest: URLRequest(url: URL(string: "https://example.com/responses")!),
            onReceiveContent: { _, event in
                guard case .keepalive = event else {
                    XCTFail("Unexpected business event: \(event)")
                    return
                }
                keepalive.fulfill()
            },
            onProcessingError: { _, error in XCTFail("Unexpected failure: \(error)") },
            onComplete: { _, _ in }
        )
        let metadata = #"{"type":"response.metadata","metadata":{"openai_chatgpt_moderation_metadata":{"prompt":{},"generation":{}}}}"#
        let wire = "event: response.metadata\ndata: \(metadata)\n\ndata: \(payload)\n\ndata: \(metadata)\n\nevent: keepalive\ndata: {}\n\n"
        session.urlSession(URLSessionMock(), dataTask: DataTaskMock(), didReceive: Data(wire.utf8))
        await fulfillment(of: [diagnostic, keepalive], timeout: 2, enforceOrder: true)
    }
}

/// Immutable test observer, invoked on the streaming session's serialized callback queue.
private struct DiagnosticsMiddleware: OpenAIMiddleware {
    /// Assertions performed for the complete skipped event.
    let onSkipped: @Sendable (String, Data) -> Void

    /// Forwards the diagnostic without modifying request bytes or stream events.
    func didSkipResponseEvent(eventType: String, data: Data) {
        onSkipped(eventType, data)
    }
}
