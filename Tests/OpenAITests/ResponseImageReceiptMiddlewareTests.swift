import Foundation
import XCTest
@testable import OpenAI

/// Verifies raw image errors reach middleware before typed decoding or unknown-event skipping.
final class ResponseImageReceiptMiddlewareTests: XCTestCase {
    /// Fragmented known and unknown events preserve provider-specific error fields in the production factory.
    func testImageReceiptsAreObservedBeforeTypedDelivery() async {
        let knownReceipt = expectation(description: "Known image receipt")
        let knownDelivery = expectation(description: "Typed image delivery")
        let unknownReceipt = expectation(description: "Unknown image failure receipt")
        let keepalive = expectation(description: "Stream continues")
        let known = #"{"type":"response.output_item.done","output_index":0,"item":{"type":"image_generation_call","id":"ig_1","status":"failed","error":{"message":"完整错误","code":"unsupported_format"}}}"#
        let unknown = #"{"type":"response.image_generation_call.failed","item_id":"ig_2","error":{"message":"UserError","detail":"完整原因"}}"#
        let middleware = ImageReceiptMiddleware { type, data in
            if type == "response.output_item.done" {
                XCTAssertEqual(data, Data(known.utf8))
                knownReceipt.fulfill()
            } else if type == "response.image_generation_call.failed" {
                XCTAssertEqual(data, Data(unknown.utf8))
                unknownReceipt.fulfill()
            }
        }
        let factory = ImplicitURLSessionStreamingSessionFactory(middlewares: [middleware], parsingOptions: [], sslDelegate: nil)
        let session = factory.makeModelResponseStreamingSession(
            urlRequest: URLRequest(url: URL(string: "https://example.com/responses")!),
            onReceiveContent: { _, event in
                switch event {
                case .outputItem: knownDelivery.fulfill()
                case .keepalive: keepalive.fulfill()
                default: XCTFail("Unexpected event")
                }
            },
            onProcessingError: { _, error in XCTFail("Unexpected failure: \(error)") },
            onComplete: { _, _ in }
        )
        let wire = "data: \(known)\n\ndata: \(unknown)\n\nevent: keepalive\ndata: {}\n\n"
        for byte in wire.utf8 {
            session.urlSession(URLSessionMock(), dataTask: DataTaskMock(), didReceive: Data([byte]))
        }
        await fulfillment(of: [knownReceipt, knownDelivery, unknownReceipt, keepalive], timeout: 2, enforceOrder: true)
    }
}

/// Receives complete payloads without changing request or response bytes.
private struct ImageReceiptMiddleware: OpenAIMiddleware {
    /// Assertions for raw SSE frames.
    let onReceived: @Sendable (String, Data) -> Void

    /// Forwards each complete raw event to the test observer.
    func didReceiveResponseEvent(eventType: String, data: Data) {
        onReceived(eventType, data)
    }
}
