import Foundation
import XCTest
@testable import OpenAI

/// Verifies the new model's arrays survive both Codable and multipart upload encoding.
final class AudioTranscriptionQueryTests: XCTestCase {
    /// Literal multiword, Unicode and punctuation-bearing keywords use individual multipart fields.
    func testStructuredHintsUseRepeatedMultipartFields() throws {
        let query = AudioTranscriptionQuery(file: Data("audio".utf8), fileType: .m4a, model: "gpt-transcribe",
            prompt: "Meeting notes.", stream: true, languages: ["zh", "en"],
            keywords: ["AnyNotes", "New York", "张三", "AC-42", "O’Connor"])
        let body = String(decoding: query.encode(boundary: "boundary"), as: UTF8.self)
        XCTAssertEqual(body.components(separatedBy: "name=\"keywords[]\"").count - 1, 5)
        XCTAssertEqual(body.components(separatedBy: "name=\"languages[]\"").count - 1, 2)
        for word in query.keywords! { XCTAssertTrue(body.contains("name=\"keywords[]\"\r\n\r\n\(word)\r\n")) }
        XCTAssertFalse(body.contains("name=\"language\""))
        XCTAssertTrue(body.contains("name=\"stream\"\r\n\r\ntrue\r\n"))
        let decoded = try JSONDecoder().decode(AudioTranscriptionQuery.self, from: JSONEncoder().encode(query))
        XCTAssertEqual(decoded.keywords, query.keywords)
        XCTAssertEqual(decoded.languages, query.languages)
        XCTAssertEqual(decoded.file, query.file)
    }

    /// Requests for existing models keep their singular language field and omit unused arrays.
    func testLegacyRequestOmitsNewHints() {
        let query = AudioTranscriptionQuery(file: Data(), fileType: .wav, model: .whisper_1, language: "en")
        let body = String(decoding: query.encode(boundary: "boundary"), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"language\"\r\n\r\nen\r\n"))
        XCTAssertFalse(body.contains("keywords"))
        XCTAssertFalse(body.contains("languages"))
    }

    /// Empty optional arrays must not become empty keyword fields that the service could interpret as terms.
    func testEmptyArraysAreOmitted() {
        let query = AudioTranscriptionQuery(file: Data(), fileType: .wav, model: "gpt-transcribe",
                                          languages: [], keywords: [])
        let body = String(decoding: query.encode(boundary: "boundary"), as: UTF8.self)
        XCTAssertFalse(body.contains("keywords"))
        XCTAssertFalse(body.contains("languages"))
    }
}
