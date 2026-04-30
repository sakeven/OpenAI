//
//  CompactModelResponseQuery.swift
//  OpenAI
//
//  Created by OpenAI on 30.04.2026.
//

import Foundation

/// Request body for compacting a Responses conversation window.
public struct CompactModelResponseQuery: Codable, Equatable, Sendable {
    /// Model ID used to run the compaction pass.
    public let model: String

    /// The conversation window to compact.
    public let input: CreateModelResponseQuery.Input?

    /// System-style instructions that apply only to the compaction pass.
    public let instructions: String?

    /// Creates a request for the `/responses/compact` endpoint.
    public init(
        model: String,
        input: CreateModelResponseQuery.Input? = nil,
        instructions: String? = nil
    ) {
        self.model = model
        self.input = input
        self.instructions = instructions
    }
}
