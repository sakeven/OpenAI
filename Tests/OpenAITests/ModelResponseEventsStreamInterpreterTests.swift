//
//  ModelResponseEventsStreamInterpreterTests.swift
//  OpenAI
//
//  Created by Oleksii Nezhyborets on 10.04.2025.
//

import XCTest
@testable import OpenAI

@MainActor
final class ModelResponseEventsStreamInterpreterTests: XCTestCase {
    private let interpreter = ModelResponseEventsStreamInterpreter()

    func testParseApiError() async throws {
        let expectation = XCTestExpectation(description: "API Error callback received")
        var receivedError: Error?

        interpreter.setCallbackClosures { result in
            // This closure is for successful results, which we don't expect here
            XCTFail("Unexpected successful result received")
        } onError: { apiError in
            Task {
                await MainActor.run {
                    receivedError = apiError
                    expectation.fulfill() // Fulfill the expectation when the error is received
                }
            }
        }

        interpreter.processData(
            MockServerSentEvent.chatCompletionError()
        )

        // Wait for the expectation to be fulfilled, with a timeout
        await fulfillment(of: [expectation], timeout: 1.0)

        // Assert that an error was received and that it is of the expected type
        XCTAssertNotNil(receivedError, "Expected an error to be received, but got nil.")
        XCTAssertTrue(receivedError is APIErrorResponse, "Expected received error to be of type APIErrorResponse.")
    }

    func testParsesOutputTextDeltaUsingPayloadType() async throws {
        let expectation = XCTestExpectation(description: "OutputText delta event received")
        var receivedEvent: ResponseStreamEvent?

        interpreter.setCallbackClosures { event in
            Task {
                await MainActor.run {
                    receivedEvent = event
                    expectation.fulfill()
                }
            }
        } onError: { error in
            XCTFail("Unexpected error received: \(error)")
        }

        interpreter.processData(
            MockServerSentEvent.responseStreamEvent(
                itemId: "msg_1",
                payloadType: "response.output_text.delta",
                outputIndex: 0,
                contentIndex: 0,
                delta: "Hi",
                sequenceNumber: 1
            )
        )

        await fulfillment(of: [expectation], timeout: 1.0)

        guard let receivedEvent else {
            XCTFail("No event received")
            return
        }

        switch receivedEvent {
        case .outputText(.delta(let deltaEvent)):
            XCTAssertEqual(deltaEvent.itemId, "msg_1")
            XCTAssertEqual(deltaEvent.outputIndex, 0)
            XCTAssertEqual(deltaEvent.contentIndex, 0)
            XCTAssertEqual(deltaEvent.delta, "Hi")
            XCTAssertEqual(deltaEvent.sequenceNumber, 1)
        default:
            XCTFail("Expected .outputText(.delta), got \(receivedEvent)")
        }
    }

    func testParsesWebSearchOutputItemDoneWithApiSource() async throws {
        let expectation = XCTestExpectation(description: "Web search output item received")
        var receivedEvent: ResponseStreamEvent?
        var receivedError: Error?

        interpreter.setCallbackClosures { event in
            Task {
                await MainActor.run {
                    receivedEvent = event
                    expectation.fulfill()
                }
            }
        } onError: { error in
            Task {
                await MainActor.run {
                    receivedError = error
                    expectation.fulfill()
                }
            }
        }

        let json = """
        {"type":"response.output_item.done","item":{"id":"ws_1","type":"web_search_call","status":"completed","action":{"type":"search","queries":["finance: SMH"],"query":"finance: SMH","sources":[{"type":"api","name":"oai-finance"}]}},"output_index":1,"sequence_number":105}
        """
        interpreter.processData("data: \(json)\n\n".data(using: .utf8)!)

        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertNil(receivedError)
        guard case .outputItem(.done(let doneEvent)) = receivedEvent else {
            XCTFail("Expected .outputItem(.done), got \(String(describing: receivedEvent))")
            return
        }

        guard case .WebSearchToolCall(let webSearchToolCall) = doneEvent.item else {
            XCTFail("Expected WebSearchToolCall, got \(doneEvent.item)")
            return
        }

        guard case .WebSearchActionSearch(let action) = webSearchToolCall.action else {
            XCTFail("Expected WebSearchActionSearch, got \(String(describing: webSearchToolCall.action))")
            return
        }

        XCTAssertEqual(action.query, "finance: SMH")
        guard case .WebSearchActionSearchAPISource(let source) = action.sources?.first else {
            XCTFail("Expected WebSearchActionSearchAPISource, got \(String(describing: action.sources?.first))")
            return
        }
        XCTAssertEqual(source.name, "oai-finance")
    }

    func testParsesCompactionOutputItemDone() async throws {
        let expectation = XCTestExpectation(description: "Compaction output item received")
        var receivedEvent: ResponseStreamEvent?
        var receivedError: Error?

        interpreter.setCallbackClosures { event in
            Task {
                await MainActor.run {
                    receivedEvent = event
                    expectation.fulfill()
                }
            }
        } onError: { error in
            Task {
                await MainActor.run {
                    receivedError = error
                    expectation.fulfill()
                }
            }
        }

        let json = """
        {"type":"response.output_item.done","item":{"id":"cmp_1","type":"compaction","encrypted_content":"encrypted"},"output_index":1,"sequence_number":106}
        """
        interpreter.processData("data: \(json)\n\n".data(using: .utf8)!)

        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertNil(receivedError)
        guard case .outputItem(.done(let doneEvent)) = receivedEvent else {
            XCTFail("Expected .outputItem(.done), got \(String(describing: receivedEvent))")
            return
        }

        guard case .CompactionBody(let compaction) = doneEvent.item else {
            XCTFail("Expected CompactionBody, got \(doneEvent.item)")
            return
        }

        XCTAssertEqual(compaction.id, "cmp_1")
        XCTAssertEqual(compaction.encryptedContent, "encrypted")
    }
}
