import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol OpenAIMiddleware: Sendable {
    func intercept(request: URLRequest) -> URLRequest
    func interceptStreamingData(request: URLRequest?, _ data: Data) -> Data
    /// Observes each complete Responses SSE payload before typed decoding, including provider-specific fields.
    func didReceiveResponseEvent(eventType: String, data: Data)
    /// Observes a complete unsupported Responses SSE event before it is skipped.
    func didSkipResponseEvent(eventType: String, data: Data)
    func intercept(response: URLResponse?, request: URLRequest, data: Data?) -> (response: URLResponse?, data: Data?)
}

public extension OpenAIMiddleware {
    func intercept(request: URLRequest) -> URLRequest { request }
    func interceptStreamingData(request: URLRequest?, _ data: Data) -> Data { data }
    /// Raw event observation is optional and never changes stream delivery.
    func didReceiveResponseEvent(eventType: String, data: Data) {}
    /// Leaves skipped-event diagnostics optional for middleware that only transforms requests or responses.
    func didSkipResponseEvent(eventType: String, data: Data) {}
    func intercept(response: URLResponse?, request: URLRequest, data: Data?) -> (response: URLResponse?, data: Data?) { (response, data) }
}
