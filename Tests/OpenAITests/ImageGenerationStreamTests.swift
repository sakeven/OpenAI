import Foundation
import XCTest
@testable import OpenAI

/// Covers image outputs that have not produced a result across the entire Responses stream.
final class ImageGenerationStreamTests: XCTestCase {
    /// Added and done events both allow missing or null results, including failed calls.
    func testImageEventsWithoutResult() throws {
        for eventType in ["added", "done"] {
            for status in ["in_progress", "generating", "completed", "failed"] {
                for resultField in ["", ",\"result\":null"] {
                    let json = """
                    {"type":"response.output_item.\(eventType)","output_index":0,"item":{
                        "type":"image_generation_call","id":"ig_missing","status":"\(status)"\(resultField)
                    }}
                    """
                    let event = try JSONDecoder().decode(ResponseStreamEvent.self, from: Data(json.utf8))
                    let output: OutputItem
                    switch event {
                    case .outputItem(.added(let added)):
                        XCTAssertEqual(eventType, "added")
                        output = added.item
                    case .outputItem(.done(let done)):
                        XCTAssertEqual(eventType, "done")
                        output = done.item
                    default: return XCTFail("Expected an output item event")
                    }
                    guard case .ImageGenToolCall(let image) = output else {
                        return XCTFail("Expected an image output")
                    }
                    XCTAssertNil(image.result)
                    XCTAssertEqual(image.status.rawValue, status)
                }
            }
        }
    }

    /// Terminal response outputs use the same optional schema as individual streamed items.
    func testTerminalResponseWithoutImageResult() throws {
        for status in ["generating", "completed", "failed"] {
            for resultField in ["", ",\"result\":null"] {
                let data = terminalResponse(status: status, resultField: resultField)
                let event = try JSONDecoder().decode(ResponseStreamEvent.self, from: data)
                guard case .completed(let completed) = event,
                      case .ImageGenToolCall(let image) = completed.response.output.first else {
                    return XCTFail("Expected a terminal image output")
                }
                XCTAssertNil(image.result)
                XCTAssertEqual(image.status.rawValue, status)
                let encoded = try JSONEncoder().encode(completed.response)
                let restored = try JSONDecoder().decode(ResponseObject.self, from: encoded)
                XCTAssertEqual(restored, completed.response)
            }
        }
    }

    /// A resultless done item must not prevent decoding a final image from response.completed.
    func testFinalImageAfterResultlessDoneEvent() throws {
        let done = Data(#"{"type":"response.output_item.done","output_index":0,"item":{"type":"image_generation_call","id":"ig_missing","status":"generating"}}"#.utf8)
        _ = try JSONDecoder().decode(ResponseStreamEvent.self, from: done)
        let data = terminalResponse(status: "completed", resultField: #", "result":"Zm9v","revised_prompt":"A blue square""#)
        let event = try JSONDecoder().decode(ResponseStreamEvent.self, from: data)
        guard case .completed(let completed) = event,
              case .ImageGenToolCall(let image) = completed.response.output.first else {
            return XCTFail("Expected the final image output")
        }
        XCTAssertEqual(image.result, "Zm9v")
        XCTAssertEqual(image.revisedPrompt, "A blue square")
    }

    /// Making result optional must still reject malformed fields and missing required identifiers.
    func testMalformedImageEventsStillThrow() {
        for eventType in ["added", "done"] {
            for fields in [#""id":"ig_bad","result":123"#, #""result":null"#] {
                let json = """
                {"type":"response.output_item.\(eventType)","output_index":0,"item":{
                    "type":"image_generation_call","status":"generating",\(fields)
                }}
                """
                XCTAssertThrowsError(try JSONDecoder().decode(ResponseStreamEvent.self, from: Data(json.utf8)))
            }
        }
    }

    /// Builds the minimal terminal envelope around a service-provided image output.
    private func terminalResponse(status: String, resultField: String) -> Data {
        Data("""
        {"type":"response.completed","sequence_number":10,"response":{
            "id":"resp_image","created_at":1,"metadata":{},"model":"gpt-6-astra",
            "object":"response","status":"completed","parallel_tool_calls":false,"tools":[],
            "output":[{"type":"image_generation_call","id":"ig_missing","status":"\(status)"\(resultField)}]
        }}
        """.utf8)
    }

    /// Progress events carry no final image until the service produces one.
    func testResponseStreamEventWithInProgressImageGenerationCall() throws {
        let data = """
        {
          "type": "response.output_item.added",
          "item": {
            "id": "ig_04e7922f0fe120280169e4deb2fae8819198eba5d3a0aedeeb",
            "type": "image_generation_call",
            "status": "in_progress"
          },
          "output_index": 0,
          "sequence_number": 2
        }
        """

        let event = try JSONDecoder().decode(ResponseStreamEvent.self, from: Data(data.utf8))

        switch event {
        case .outputItem(.added(let addedEvent)):
            XCTAssertEqual(addedEvent.type, "response.output_item.added")
            XCTAssertEqual(addedEvent.outputIndex, 0)

            switch addedEvent.item {
            case .ImageGenToolCall(let imageOutput):
                XCTAssertEqual(imageOutput.id, "ig_04e7922f0fe120280169e4deb2fae8819198eba5d3a0aedeeb")
                XCTAssertEqual(imageOutput.status, .inProgress)
                XCTAssertNil(imageOutput.result)
            default:
                XCTFail("Expected an ImageGenToolCall output item")
            }
        default:
            XCTFail("Expected a response.output_item.added event")
        }
    }

    /// Verifies Responses image generation calls retain the revised prompt returned by the API.
    func testImageGenerationCallDecodesRevisedPrompt() throws {
        let data = """
        {
          "id": "ig_123",
          "type": "image_generation_call",
          "status": "completed",
          "revised_prompt": "A small blue square",
          "result": "Zm9v"
        }
        """

        let item = try JSONDecoder().decode(
            Components.Schemas.ImageGenToolCall.self,
            from: Data(data.utf8)
        )

        XCTAssertEqual(item.id, "ig_123")
        XCTAssertEqual(item.status, .completed)
        XCTAssertEqual(item.revisedPrompt, "A small blue square")
        XCTAssertEqual(item.result, "Zm9v")
    }

}
