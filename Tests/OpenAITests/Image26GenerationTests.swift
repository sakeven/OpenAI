import Foundation
import XCTest
@testable import OpenAI

/// Verifies the dedicated image endpoint receives formats without incompatible Responses or streaming fields.
final class Image26GenerationTests: XCTestCase {
    /// Every supported container preserves the selected model and requests a single base64-backed result.
    func testGenerationFormatRequestBodies() throws {
        for model in ["gpt-image-2.6-sunburst", "gpt-image-2.6-flare"] {
            for format in ImagesQuery.OutputFormat.allCases {
                let query = ImagesQuery(prompt: "完整图片要求", model: model, n: 1, quality: .high, outputFormat: format)
                let client = OpenAI(configuration: .init(token: nil, host: "images.example.test"))
                let request = try client.makeImagesRequest(query: query).build(
                    token: nil, organizationIdentifier: nil, timeoutInterval: 120, customHeaders: [:]
                )
                XCTAssertEqual(request.url?.host, "images.example.test")
                XCTAssertEqual(request.url?.path, "/v1/images/generations")
                XCTAssertEqual(request.httpMethod, "POST")
                let body = try XCTUnwrap(request.httpBody)
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(json["model"] as? String, model)
                XCTAssertEqual(json["output_format"] as? String, format.rawValue)
                XCTAssertEqual(json["prompt"] as? String, "完整图片要求")
                XCTAssertEqual(json["n"] as? Int, 1)
                for key in ["response_format", "stream", "partial_images", "frame_count", "frame_duration_ms", "svg"] {
                    XCTAssertNil(json[key])
                }
            }
        }
    }

    /// An explicitly selected SVG author encodes as a nested object and remains independent of the image model.
    func testSVGAuthorSelection() throws {
        let query = ImagesQuery(prompt: "Vector logo", model: "gpt-image-2.6-sunburst", n: 1,
                                quality: .high, outputFormat: .svg, svg: .init(model: "svg-author-test"))
        let data = try JSONEncoder().encode(query)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let svg = try XCTUnwrap(json["svg"] as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "gpt-image-2.6-sunburst")
        XCTAssertEqual(svg["model"] as? String, "svg-author-test")
        XCTAssertNil(svg["reasoning"])
        XCTAssertEqual(try JSONDecoder().decode(ImagesQuery.self, from: data), query)
    }

    /// GIF timing maps to the exact API parameter names and survives request round-tripping.
    func testGIFFrameSettings() throws {
        let query = ImagesQuery(prompt: "Loop a blinking lantern", model: "gpt-image-2.6-flare", n: 1,
                                quality: .high, outputFormat: .gif, frameCount: 12, frameDurationMs: 150)
        let data = try JSONEncoder().encode(query)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["frame_count"] as? Int, 12)
        XCTAssertEqual(json["frame_duration_ms"] as? Int, 150)
        XCTAssertEqual(try JSONDecoder().decode(ImagesQuery.self, from: data), query)
    }
}
