//
//  CreateModelResponseQuery+ContextManagement.swift
//  OpenAI
//
//  Created by OpenAI on 30.04.2026.
//

import Foundation

extension CreateModelResponseQuery {
    /// One server-side context management rule used by the Responses API.
    public struct ContextManagement: Codable, Equatable, Sendable {
        /// Supported context management rule types.
        @frozen public enum RuleType: String, Codable, Equatable, Sendable, CaseIterable {
            case compaction
        }

        /// The kind of context management the server should apply.
        public let type: RuleType

        /// Token threshold that triggers server-side compaction.
        public let compactThreshold: Int?

        /// Creates one context management rule for a Responses request.
        public init(
            type: RuleType = .compaction,
            compactThreshold: Int? = nil
        ) {
            self.type = type
            self.compactThreshold = compactThreshold
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case compactThreshold = "compact_threshold"
        }
    }
}
