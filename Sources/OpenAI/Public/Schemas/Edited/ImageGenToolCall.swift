import Foundation

extension Components.Schemas {
    /// An image generation request made by the model.
    ///
    ///
    /// - Remark: Generated from `#/components/schemas/ImageGenToolCall`.
    public struct ImageGenToolCall: Codable, Hashable, Sendable {
        /// The type of the image generation call. Always `image_generation_call`.
        ///
        ///
        /// - Remark: Generated from `#/components/schemas/ImageGenToolCall/type`.
        @frozen public enum _TypePayload: String, Codable, Hashable, Sendable, CaseIterable {
            case imageGenerationCall = "image_generation_call"
        }
        /// The type of the image generation call. Always `image_generation_call`.
        ///
        ///
        /// - Remark: Generated from `#/components/schemas/ImageGenToolCall/type`.
        public var _type: Components.Schemas.ImageGenToolCall._TypePayload
        /// The unique ID of the image generation call.
        ///
        ///
        /// - Remark: Generated from `#/components/schemas/ImageGenToolCall/id`.
        public var id: Swift.String
        /// The status of the image generation call.
        ///
        ///
        /// - Remark: Generated from `#/components/schemas/ImageGenToolCall/status`.
        @frozen public enum StatusPayload: String, Codable, Hashable, Sendable, CaseIterable {
            case inProgress = "in_progress"
            case completed = "completed"
            case generating = "generating"
            case failed = "failed"
        }
        /// The status of the image generation call.
        ///
        ///
        /// - Remark: Generated from `#/components/schemas/ImageGenToolCall/status`.
        public var status: Components.Schemas.ImageGenToolCall.StatusPayload
        /// The prompt the model used after applying safety and quality revisions.
        ///
        ///
        /// - Remark: Generated from `#/components/schemas/ImageGenToolCall/revised_prompt`.
        public var revisedPrompt: Swift.String?
        /// The generated image encoded in base64, absent until available or when generation fails.
        ///
        ///
        /// - Remark: Generated from `#/components/schemas/ImageGenToolCall/result`.
        public var result: Swift.String?
        /// Creates a new `ImageGenToolCall`.
        ///
        /// - Parameters:
        ///   - _type: The type of the image generation call. Always `image_generation_call`.
        ///   - id: The unique ID of the image generation call.
        ///   - status: The status of the image generation call.
        ///   - revisedPrompt: The prompt the model used after applying safety and quality revisions.
        ///   - result: The generated image encoded in base64, absent until available or when generation fails.
        public init(
            _type: Components.Schemas.ImageGenToolCall._TypePayload,
            id: Swift.String,
            status: Components.Schemas.ImageGenToolCall.StatusPayload,
            revisedPrompt: Swift.String? = nil,
            result: Swift.String? = nil
        ) {
            self._type = _type
            self.id = id
            self.status = status
            self.revisedPrompt = revisedPrompt
            self.result = result
        }
        /// Maps the image output fields to their Responses wire names.
        public enum CodingKeys: String, CodingKey {
            case _type = "type"
            case id
            case status
            case revisedPrompt = "revised_prompt"
            case result
        }
    }
}
