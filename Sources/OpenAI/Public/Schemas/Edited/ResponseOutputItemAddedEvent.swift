//
//  ResponseOutputItemAddedEvent.swift
//  OpenAI
//
//  Created by Oleksii Nezhyborets on 16.04.2025.
//

import Foundation

/// Emitted when a new output item is added.
public struct ResponseOutputItemAddedEvent: Codable, Hashable, Sendable {
    /// The type of the event. Always `response.output_item.added`.
    public let type: String
    /// The index of the output item that was added.
    public let outputIndex: Int
    /// The output item that was added.
    public let item: OutputItem
    /// Creates a new `ResponseOutputItemAddedEvent`.
    ///
    /// - Parameters:
    ///   - type: The type of the event. Always `response.output_item.added`.
    ///   - outputIndex: The index of the output item that was added.
    ///   - item:The output item that was added.
    public init(
        type: String = "response.output_item.added",
        outputIndex: Int,
        item: OutputItem
    ) {
        self.type = type
        self.outputIndex = outputIndex
        self.item = item
    }
    
    public enum CodingKeys: String, CodingKey {
        case type
        case outputIndex = "output_index"
        case item
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(String.self, forKey: .type)
        self.outputIndex = try container.decode(Int.self, forKey: .outputIndex)

        do {
            self.item = try container.decode(OutputItem.self, forKey: .item)
        } catch {
            let fallbackItem = try Self.decodeStreamingImageGenerationPlaceholder(
                from: container.superDecoder(forKey: .item)
            )
            guard let fallbackItem else {
                throw error
            }
            self.item = fallbackItem
        }
    }

    /// Accepts Codex image-generation progress items that omit `result` until the final streamed event.
    private static func decodeStreamingImageGenerationPlaceholder(
        from decoder: any Decoder
    ) throws -> OutputItem? {
        let placeholder = try StreamingImageGenerationPlaceholder(from: decoder)
        guard placeholder.type == .imageGenerationCall else {
            return nil
        }
        return .ImageGenToolCall(
            .init(
                _type: placeholder.type,
                id: placeholder.id,
                status: placeholder.status,
                result: placeholder.result ?? ""
            )
        )
    }
}

/// Minimal shape used when streamed image-generation progress items arrive before the final base64 payload exists.
private struct StreamingImageGenerationPlaceholder: Decodable {
    /// The streamed item type, expected to be `image_generation_call`.
    let type: Components.Schemas.ImageGenToolCall._TypePayload
    /// Stable tool-call identifier reused across image-generation progress events.
    let id: String
    /// Current image-generation status reported by the Responses stream.
    let status: Components.Schemas.ImageGenToolCall.StatusPayload
    /// Final base64 image payload when already available.
    let result: String?
}
