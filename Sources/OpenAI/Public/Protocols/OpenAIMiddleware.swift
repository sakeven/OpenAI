import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol OpenAIMiddleware: Sendable {
    func intercept(request: URLRequest) -> URLRequest
    func interceptStreamingData(request: URLRequest?, _ data: Data) -> Data
    /// Observes a complete unsupported Responses SSE event before it is skipped.
    func didSkipResponseEvent(eventType: String, data: Data)
    func intercept(response: URLResponse?, request: URLRequest, data: Data?) -> (response: URLResponse?, data: Data?)
}

public extension OpenAIMiddleware {
    func intercept(request: URLRequest) -> URLRequest { request }
    func interceptStreamingData(request: URLRequest?, _ data: Data) -> Data { data }
    /// Leaves skipped-event diagnostics optional for middleware that only transforms requests or responses.
    func didSkipResponseEvent(eventType: String, data: Data) {}
    func intercept(response: URLResponse?, request: URLRequest, data: Data?) -> (response: URLResponse?, data: Data?) { (response, data) }
}
