import Foundation
import XCTest
@testable import OpenAI

/// Exercises metadata and unknown event compatibility through the real Responses SSE parser.
/// The interpreter invokes these callbacks synchronously on the calling test thread.
final class ResponseMetadataStreamTests: XCTestCase, @unchecked Sendable {
    /// Events delivered by the interpreter in stream order.
    private var events: [ResponseStreamEvent] = []
    /// Parsing failures delivered by the interpreter.
    private var errors: [Error] = []
    /// Full diagnostic payloads observed before unsupported events are skipped.
    private var unknownEvents: [(type: String, data: Data)] = []
    /// Sanitized provider moderation metadata with the same nesting as the observed stream event.
    private let moderationJSON = #"{"type":"response.metadata","response_id":"resp_metadata_test","sequence_number":62,"metadata":{"openai_chatgpt_moderation_metadata":{"prompt":{"omnimod":{"protection_type":"omnimod","outputs":[{"results":[{"category_flags":{"A1":false,"REFUSED":false}}],"is_blocked":false}]}},"generation":{},"tool_call":{},"tool_response":{}}}}"#
    /// A terminal response fixture with the fields required by the SDK schema.
    private let completedJSON = #"{"type":"response.completed","response":{"id":"resp_1","object":"response","created_at":1780207976,"status":"completed","background":false,"completed_at":1780207988,"error":null,"frequency_penalty":0.0,"incomplete_details":null,"instructions":"Test","max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5.5","moderation":null,"parallel_tool_calls":false,"presence_penalty":0.0,"previous_response_id":null,"prompt_cache_key":"cache","prompt_cache_retention":"24h","reasoning":{"context":"current_turn","effort":"medium","summary":null},"safety_identifier":"user-1","service_tier":"default","store":false,"temperature":1.0,"text":{"format":{"type":"json_schema","description":"Payload","name":"payload","schema":{"additionalProperties":false,"type":"object","required":["title"],"properties":{"title":{"type":"string"}}},"strict":true},"verbosity":"medium"},"tool_choice":"auto","tool_usage":{"image_gen":{"input_tokens":0,"input_tokens_details":{"image_tokens":0,"text_tokens":0},"output_tokens":0,"output_tokens_details":{"image_tokens":0,"text_tokens":0},"total_tokens":0},"web_search":{"num_requests":0}},"tools":[],"top_logprobs":0,"top_p":0.98,"truncation":"disabled","usage":{"input_tokens":1,"input_tokens_details":{"cached_tokens":0},"output_tokens":1,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":2},"user":null,"metadata":{}},"sequence_number":7}"#

    /// Metadata is recognized without diagnostics before or after completion, including fragmented streams.
    func testMetadataPreservesTextAndCompletion() {
        for explicitEvent in [false, true] {
            for fragmented in [false, true] {
                let interpreter = makeInterpreter()
                let metadata = frame(moderationJSON,
                                     event: explicitEvent ? "response.metadata" : nil)
                let delta = frame(#"{"type":"response.output_text.delta","item_id":"msg_1","output_index":0,"content_index":0,"delta":"你好","logprobs":[],"sequence_number":1}"#)
                let stream = Data((metadata + delta + metadata + frame(completedJSON) + metadata).utf8)
                if fragmented {
                    for byte in stream {
                        interpreter.processData(Data([byte]))
                    }
                } else {
                    interpreter.processData(stream)
                }
                XCTAssertTrue(errors.isEmpty, "Unexpected errors: \(errors)")
                XCTAssertTrue(unknownEvents.isEmpty, "Known metadata must not produce diagnostic records")
                XCTAssertEqual(events.count, 2)
                guard events.count == 2,
                      case .outputText(.delta(let text)) = events[0],
                      case .completed(let completed) = events[1] else {
                    XCTFail("Expected text followed by completion")
                    continue
                }
                XCTAssertEqual(text.delta, "你好")
                XCTAssertEqual(completed.response.id, "resp_1")
            }
        }
    }

    /// Explicit server errors and failed responses still reach the application's failure handling.
    func testMetadataPreservesServerFailures() throws {
        let interpreter = makeInterpreter()
        var failed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(completedJSON.utf8)) as? [String: Any])
        failed["type"] = "response.failed"
        var response = try XCTUnwrap(failed["response"] as? [String: Any])
        response["status"] = "failed"
        response["error"] = ["code": "server_error", "message": "Test failure"]
        failed["response"] = response
        let failedJSON = String(decoding: try JSONSerialization.data(withJSONObject: failed), as: UTF8.self)
        let metadata = frame(#"{"type":"response.metadata"}"#) + frame(#"{"type":"provider.new_event"}"#)
        let error = frame(#"{"type":"error","code":"server_error","message":"Test failure","param":"model","sequence_number":2}"#)
        interpreter.processData(Data((metadata + error + metadata + frame(failedJSON)).utf8))
        XCTAssertTrue(errors.isEmpty, "Unexpected parsing errors: \(errors)")
        XCTAssertEqual(events.count, 2)
        guard events.count == 2,
              case .error(let serverError) = events[0],
              case .failed(let failure) = events[1] else {
            XCTFail("Expected server error and failed response")
            return
        }
        XCTAssertEqual(serverError.message, "Test failure")
        XCTAssertNotNil(failure.response.error)
    }

    /// Internal moderation flags do not replace the server's actual refusal event or create diagnostics.
    func testMetadataPreservesRefusalWithoutDiagnostics() {
        let interpreter = makeInterpreter()
        let metadata = moderationJSON.replacingOccurrences(of: "false", with: "true")
        let refusal = frame(#"{"type":"response.refusal.delta","item_id":"msg_1","output_index":0,"content_index":0,"delta":"Refusal text","sequence_number":63}"#)
        interpreter.processData(Data((frame(metadata) + refusal).utf8))
        XCTAssertTrue(errors.isEmpty)
        XCTAssertTrue(unknownEvents.isEmpty)
        XCTAssertEqual(events.count, 1)
        guard case .refusal(.delta(let event)) = events.first else {
            XCTFail("Expected the explicit refusal after metadata")
            return
        }
        XCTAssertEqual(event.delta, "Refusal text")
    }

    /// Unknown types from either SSE headers or JSON payloads must preserve later completion.
    func testUnknownEventTypesDoNotEndStream() {
        for eventType in ["response.unrecognized", "provider.new_event"] {
            for explicitEvent in [false, true] {
                let interpreter = makeInterpreter()
                let unknown = frame("{\"type\":\"\(eventType)\",\"new_field\":true}",
                                    event: explicitEvent ? eventType : nil)
                for byte in unknown.utf8 {
                    interpreter.processData(Data([byte]))
                }
                XCTAssertTrue(events.isEmpty)
                XCTAssertTrue(errors.isEmpty)
                interpreter.processData(Data(frame(completedJSON).utf8))
                XCTAssertTrue(errors.isEmpty)
                XCTAssertEqual(events.count, 1)
                guard case .completed(let completion) = events.first else {
                    XCTFail("Expected completion after the unknown event")
                    continue
                }
                XCTAssertEqual(completion.response.id, "resp_1")
            }
        }
    }

    /// Invalid JSON and missing discriminators cannot be classified as valid unknown event types.
    func testMalformedEnvelopeStillFails() {
        for payload in ["not-json", "{}", #"{"type":42}"#] {
            let interpreter = makeInterpreter()
            interpreter.processData(Data(frame(payload).utf8))
            XCTAssertTrue(events.isEmpty)
            XCTAssertEqual(errors.count, 1)
            XCTAssertTrue(errors.first is DecodingError)
        }
    }

    /// Malformed supported events must still fail after metadata has been skipped.
    func testMalformedKnownEventStillFails() {
        let interpreter = makeInterpreter()
        let stream = frame(#"{"type":"response.metadata"}"#)
            + frame(#"{"type":"response.output_text.delta"}"#)
        interpreter.processData(Data(stream.utf8))
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors.first is DecodingError)
    }

    /// The observer receives one exact payload after multiline SSE data and UTF-8 fragments are assembled.
    func testUnknownDiagnosticsPreserveCompletePayload() {
        for explicitEvent in [false, true] {
            let interpreter = makeInterpreter()
            let payload = "{\n  \"type\": \"provider.new_event\",\n  \"metadata\": {\"detail\":\"完整内容\",\"value\":42}\n}"
            let dataLines = payload.components(separatedBy: "\n").map { "data: \($0)\n" }.joined()
            let stream = (explicitEvent ? "event: provider.new_event\n" : "") + dataLines + "\n"
            for byte in stream.utf8 {
                interpreter.processData(Data([byte]))
            }
            XCTAssertEqual(unknownEvents.count, 1)
            XCTAssertEqual(unknownEvents.first?.type, "provider.new_event")
            XCTAssertEqual(unknownEvents.first?.data, Data(payload.utf8))
            XCTAssertTrue(events.isEmpty)
            XCTAssertTrue(errors.isEmpty)
            interpreter.processData(Data(frame(completedJSON).utf8))
            XCTAssertEqual(unknownEvents.count, 1)
            XCTAssertEqual(events.count, 1)
        }
    }

    /// Installs synchronous callbacks and resets results for each independent stream.
    private func makeInterpreter() -> ModelResponseEventsStreamInterpreter {
        events = []
        errors = []
        unknownEvents = []
        let interpreter = ModelResponseEventsStreamInterpreter(onUnknownEvent: { type, data in
            self.unknownEvents.append((type, data))
        })
        interpreter.setCallbackClosures { self.events.append($0) } onError: { self.errors.append($0) }
        return interpreter
    }

    /// Wraps a payload in an SSE frame, optionally including the provider's event field.
    private func frame(_ json: String, event: String? = nil) -> String {
        (event.map { "event: \($0)\n" } ?? "") + "data: \(json)\n\n"
    }
}
