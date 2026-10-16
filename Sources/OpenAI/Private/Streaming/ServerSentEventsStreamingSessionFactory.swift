//
//  ServerSentEventsStreamingSessionFactory.swift
//  OpenAI
//
//  Created by Oleksii Nezhyborets on 10.03.2025.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol StreamingSessionFactory: Sendable {
    func makeServerSentEventsStreamingSession<ResultType: Codable & Sendable>(
        urlRequest: URLRequest,
        onReceiveContent: @Sendable @escaping (StreamingSession<ServerSentEventsStreamInterpreter<ResultType>>, ResultType) -> Void,
        onProcessingError: @Sendable @escaping (StreamingSession<ServerSentEventsStreamInterpreter<ResultType>>, Error) -> Void,
        onComplete: @Sendable @escaping (StreamingSession<ServerSentEventsStreamInterpreter<ResultType>>, Error?) -> Void
    ) -> StreamingSession<ServerSentEventsStreamInterpreter<ResultType>>
    
    func makeAudioSpeechStreamingSession(
        urlRequest: URLRequest,
        onReceiveContent: @Sendable @escaping (StreamingSession<AudioSpeechStreamInterpreter>, AudioSpeechResult) -> Void,
        onProcessingError: @Sendable @escaping (StreamingSession<AudioSpeechStreamInterpreter>, Error) -> Void,
        onComplete: @Sendable @escaping (StreamingSession<AudioSpeechStreamInterpreter>, Error?) -> Void
    ) -> StreamingSession<AudioSpeechStreamInterpreter>
    
    func makeModelResponseStreamingSession(
        urlRequest: URLRequest,
        onReceiveContent: @Sendable @escaping (StreamingSession<ModelResponseEventsStreamInterpreter>, ResponseStreamEvent) -> Void,
        onProcessingError: @Sendable @escaping (StreamingSession<ModelResponseEventsStreamInterpreter>, Error) -> Void,
        onComplete: @Sendable @escaping (StreamingSession<ModelResponseEventsStreamInterpreter>, Error?) -> Void
    ) -> StreamingSession<ModelResponseEventsStreamInterpreter>
}

struct ImplicitURLSessionStreamingSessionFactory: StreamingSessionFactory {
    let middlewares: [OpenAIMiddleware]
    let parsingOptions: ParsingOptions
    let sslDelegate: SSLDelegateProtocol?
    
    func makeServerSentEventsStreamingSession<ResultType>(
        urlRequest: URLRequest,
        onReceiveContent: @Sendable @escaping (StreamingSession<ServerSentEventsStreamInterpreter<ResultType>>, ResultType) -> Void,
        onProcessingError: @Sendable @escaping (StreamingSession<ServerSentEventsStreamInterpreter<ResultType>>, any Error) -> Void,
        onComplete: @Sendable @escaping (StreamingSession<ServerSentEventsStreamInterpreter<ResultType>>, (any Error)?) -> Void
    ) -> StreamingSession<ServerSentEventsStreamInterpreter<ResultType>> where ResultType : Decodable, ResultType : Encodable, ResultType : Sendable {
        .init(
            urlRequest: urlRequest,
            interpreter: .init(parsingOptions: parsingOptions),
            sslDelegate: sslDelegate,
            middlewares: middlewares,
            onReceiveContent: onReceiveContent,
            onProcessingError: onProcessingError,
            onComplete: onComplete
        )
    }
    
    func makeAudioSpeechStreamingSession(
        urlRequest: URLRequest,
        onReceiveContent: @Sendable @escaping (StreamingSession<AudioSpeechStreamInterpreter>, AudioSpeechResult) -> Void,
        onProcessingError: @Sendable @escaping (StreamingSession<AudioSpeechStreamInterpreter>, any Error) -> Void,
        onComplete: @Sendable @escaping (StreamingSession<AudioSpeechStreamInterpreter>, (any Error)?) -> Void
    ) -> StreamingSession<AudioSpeechStreamInterpreter> {
        .init(
            urlRequest: urlRequest,
            interpreter: .init(),
            sslDelegate: sslDelegate,
            middlewares: middlewares,
            onReceiveContent: onReceiveContent,
            onProcessingError: onProcessingError,
            onComplete: onComplete
        )
    }
    
    /// Connects skipped-event diagnostics to the same middleware instances used by this request.
    func makeModelResponseStreamingSession(
        urlRequest: URLRequest,
        onReceiveContent: @Sendable @escaping (StreamingSession<ModelResponseEventsStreamInterpreter>, ResponseStreamEvent) -> Void,
        onProcessingError: @Sendable @escaping (StreamingSession<ModelResponseEventsStreamInterpreter>, any Error) -> Void,
        onComplete: @Sendable @escaping (StreamingSession<ModelResponseEventsStreamInterpreter>, (any Error)?) -> Void
    ) -> StreamingSession<ModelResponseEventsStreamInterpreter> {
        .init(
            urlRequest: urlRequest,
            interpreter: .init(onUnknownEvent: { [middlewares] eventType, data in
                for middleware in middlewares {
                    middleware.didSkipResponseEvent(eventType: eventType, data: data)
                }
            }),
            sslDelegate: sslDelegate,
            middlewares: middlewares,
            onReceiveContent: onReceiveContent,
            onProcessingError: onProcessingError,
            onComplete: onComplete
        )
    }
}
