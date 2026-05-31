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

    func testParsesResponseCompletedWithoutOutputField() async throws {
        let expectation = XCTestExpectation(description: "Responses stream completed event received")
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
        {"type":"response.completed","response":{"id":"resp_1","object":"response","created_at":1780207976,"status":"completed","background":false,"completed_at":1780207988,"error":null,"frequency_penalty":0.0,"incomplete_details":null,"instructions":"Test","max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5.5","moderation":null,"parallel_tool_calls":false,"presence_penalty":0.0,"previous_response_id":null,"prompt_cache_key":"cache","prompt_cache_retention":"24h","reasoning":{"context":"current_turn","effort":"medium","summary":null},"safety_identifier":"user-1","service_tier":"default","store":false,"temperature":1.0,"text":{"format":{"type":"json_schema","description":"Payload","name":"payload","schema":{"additionalProperties":false,"type":"object","required":["title"],"properties":{"title":{"type":"string"}}},"strict":true},"verbosity":"medium"},"tool_choice":"auto","tool_usage":{"image_gen":{"input_tokens":0,"input_tokens_details":{"image_tokens":0,"text_tokens":0},"output_tokens":0,"output_tokens_details":{"image_tokens":0,"text_tokens":0},"total_tokens":0},"web_search":{"num_requests":0}},"tools":[],"top_logprobs":0,"top_p":0.98,"truncation":"disabled","usage":{"input_tokens":1,"input_tokens_details":{"cached_tokens":0},"output_tokens":1,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":2},"user":null,"metadata":{}},"sequence_number":7}
        """
        interpreter.processData("data: \(json)\n\n".data(using: .utf8)!)

        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertNil(receivedError)
        guard case .completed(let event) = receivedEvent else {
            XCTFail("Expected .completed, got \(String(describing: receivedEvent))")
            return
        }
        XCTAssertEqual(event.response.output, [])
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
