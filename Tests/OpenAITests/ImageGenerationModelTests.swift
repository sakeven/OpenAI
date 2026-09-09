import Foundation
import XCTest
@testable import OpenAI

/// Verifies image tool schemas can encode requests and decode echoed Responses tool definitions.
final class ImageGenerationModelTests: XCTestCase {
    /// Sunburst, Flare, and Codex retain their exact wire identifiers through both codec directions.
    func testImageModelRoundTrips() throws {
        for name in ["gpt-image-2.5-sunburst", "gpt-image-2.5-flare", "gpt-image-2", "gpt-image-2-codex"] {
            let data = Data("""
            {"type":"image_generation","model":"\(name)","quality":"high","output_format":"png","partial_images":3}
            """.utf8)
            let tool = try JSONDecoder().decode(Tool.self, from: data)
            guard case .imageGenerationTool(let imageTool) = tool else {
                return XCTFail("Expected an image generation tool")
            }
            XCTAssertEqual(imageTool.model?.rawValue, name)
            XCTAssertEqual(imageTool.partialImages, 3)
            let encoded = try JSONEncoder().encode(tool)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            XCTAssertEqual(object["model"] as? String, name)
            XCTAssertEqual(object["quality"] as? String, "high")
            XCTAssertEqual(object["output_format"] as? String, "png")
        }
    }
}
