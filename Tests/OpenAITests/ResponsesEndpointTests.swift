//
//  ResponsesEndpointTests.swift
//  OpenAI
//
//  Tests for ResponsesEndpoint.createResponse (async)
//

import XCTest
@testable import OpenAI

class ResponsesEndpointTests: XCTestCase {
    private var openAI: OpenAIProtocol!
    private let urlSession = URLSessionMock()

    override func setUp() async throws {
        let configuration = OpenAI.Configuration(token: "test-token", organizationIdentifier: nil, timeoutInterval: 10)
        openAI = OpenAI(
            configuration: configuration,
            session: urlSession,
            streamingSessionFactory: MockStreamingSessionFactory()
        )
    }

    /// Replace the next dataTask on urlSession with a successful stub containing the encoded `result`.
    private func stub<ResultType: Codable & Equatable>(_ result: ResultType) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(result)
        let task = DataTaskMock.successful(with: data)
        urlSession.dataTask = task
    }
    
    func testCreateResponse() async throws {
        // Build the query
        let query = CreateModelResponseQuery(
            input: .textInput("Hello"),
            model: "test-model"
        )

        // Dummy response object
        let dummy = ResponseObject(
            createdAt: 123,
            error: nil,
            id: "resp-1",
            incompleteDetails: nil,
            instructions: nil,
            maxOutputTokens: nil,
            metadata: [:],
            model: "test-model",
            object: "response",
            output: [],
            parallelToolCalls: false,
            previousResponseId: nil,
            reasoning: nil,
            status: "completed",
            temperature: nil,
            text: .init(format: nil),
            toolChoice: .ToolChoiceOptions(.auto),
            tools: [],
            topP: nil,
            truncation: nil,
            usage: nil,
            user: nil
        )
        try stub(dummy)

        let result = try await openAI.responses.createResponse(query: query)
        XCTAssertEqual(dummy, result)
    }

    func testCreateResponseQueryEncodesContextManagement() throws {
        let query = CreateModelResponseQuery(
            input: .textInput("Hello"),
            model: "test-model",
            contextManagement: [
                .init(compactThreshold: 200_000)
            ]
        )

        let data = try JSONEncoder().encode(query)
        let dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let contextManagement = try XCTUnwrap(dictionary["context_management"] as? [[String: Any]])
        XCTAssertEqual(contextManagement.count, 1)
        XCTAssertEqual(contextManagement[0]["type"] as? String, "compaction")
        XCTAssertEqual(contextManagement[0]["compact_threshold"] as? Int, 200_000)
    }

    func testCompactResponse() async throws {
        let json = """
        {"id":"resp_001","object":"response.compaction","created_at":1764967971,"output":[{"id":"msg_000","type":"message","status":"completed","content":[{"type":"input_text","text":"Hello"}],"role":"user"},{"id":"cmp_001","type":"compaction","encrypted_content":"encrypted"}],"usage":{"input_tokens":139,"input_tokens_details":{"cached_tokens":0},"output_tokens":438,"output_tokens_details":{"reasoning_tokens":64},"total_tokens":577}}
        """
        urlSession.dataTask = DataTaskMock.successful(with: json.data(using: .utf8)!)

        let result = try await openAI.responses.compactResponse(
            query: .init(
                model: "gpt-5.5",
                input: .inputItemList([
                    .inputMessage(.init(role: .user, content: .textInput("Hello")))
                ])
            )
        )

        XCTAssertEqual(urlSession.dataAsyncCalls[0].request.url?.path, "/v1/responses/compact")
        XCTAssertEqual(result.object, "response.compaction")
        XCTAssertEqual(result.usage?.totalTokens, 577)
        guard case .inputMessage(let message) = result.output[0] else {
            XCTFail("Expected compact output to preserve the user message")
            return
        }
        XCTAssertEqual(message.role, .user)
        guard case .item(.CompactionSummaryItemParam(let compaction)) = result.output[1] else {
            XCTFail("Expected compact output to include a compaction item")
            return
        }
        XCTAssertEqual(compaction.encryptedContent, "encrypted")
    }

    func testCreateResponseWithFunctionTool() async throws {
        // Build a simple JSON schema: { "type":"object", "properties":{ "foo":{ "type":"string" } }, "required":["foo"] }
        let propSchema = JSONSchema(fields: [
            JSONSchemaField.type(.string)
        ])
        let schema = JSONSchema(fields: [
            JSONSchemaField.type(.object),
            JSONSchemaField.properties(["foo": propSchema]),
            JSONSchemaField.required(["foo"])
        ])
        // Create the function tool wrapper
        let functionTool = FunctionTool(
            type: "function",
            name: "my_function",
            description: "A test function",
            parameters: schema,
            strict: true
        )
        let tool = Tool.functionTool(functionTool)

        // Build the query
        let query = CreateModelResponseQuery(
            input: .textInput("Hello"),
            model: "test-model",
            tools: [tool]
        )

        // Dummy response object
        let dummy = makeResponse(tools: [tool])
        try stub(dummy)

        let result = try await openAI.responses.createResponse(query: query)
        switch result.tools[0] {
        case .functionTool(let responseTool):
            guard case let JSONSchema.object(jsonSchemaObject) = responseTool.parameters else {
                XCTFail("Expected function.parameters to be object")
                return
            }
            
            let type = (jsonSchemaObject["type"]?.value as? String)
            XCTAssertEqual(type, "object")
            
            let properties = try XCTUnwrap(jsonSchemaObject["properties"]?.value as? JSONObject)
            let fooProperty = try XCTUnwrap(properties["foo"]?.value as? JSONObject)
            XCTAssertEqual(fooProperty["type"]?.value as? String, "string")
            
            let required = try XCTUnwrap(jsonSchemaObject["required"]?.value as? [AnyJSONDocument])
            XCTAssertEqual(required.compactMap({ $0.value as? String }), ["foo"])
        default:
            XCTFail("Expected tool in response to be a function")
        }
    }
    private func makeResponse(output: [OutputItem] = [], tools: [Tool] = []) -> ResponseObject {
        .init(
            createdAt: 123,
            error: nil,
            id: "resp-1",
            incompleteDetails: nil,
            instructions: nil,
            maxOutputTokens: nil,
            metadata: [:],
            model: "test-model",
            object: "response",
            output: output,
            parallelToolCalls: false,
            previousResponseId: nil,
            reasoning: nil,
            status: "completed",
            temperature: nil,
            text: .init(format: nil),
            toolChoice: .ToolChoiceOptions(.auto),
            tools: tools,
            topP: nil,
            truncation: nil,
            usage: nil,
            user: nil
        )
    }
}
