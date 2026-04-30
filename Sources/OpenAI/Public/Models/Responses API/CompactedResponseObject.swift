//
//  CompactedResponseObject.swift
//  OpenAI
//
//  Created by OpenAI on 30.04.2026.
//

import Foundation

/// Response returned by the `/responses/compact` endpoint.
public struct CompactedResponseObject: Codable, Equatable, Sendable {
    public typealias Schemas = Components.Schemas

    /// Unix timestamp in seconds when the compacted conversation was created.
    public let createdAt: Int

    /// Unique identifier for the compacted response.
    public let id: String

    /// The object type, normally `response.compaction`.
    public let object: String

    /// Canonical compacted context window to pass into the next Responses request.
    public let output: [InputItem]

    /// Token usage for the compaction pass.
    public let usage: Schemas.ResponseUsage?

    /// Creates one compacted response object.
    public init(
        createdAt: Int,
        id: String,
        object: String,
        output: [InputItem],
        usage: Schemas.ResponseUsage?
    ) {
        self.createdAt = createdAt
        self.id = id
        self.object = object
        self.output = output
        self.usage = usage
    }

    private enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case id
        case object
        case output
        case usage
    }
}
