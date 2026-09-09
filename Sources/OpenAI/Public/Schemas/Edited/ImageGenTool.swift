import Foundation
@_spi(Generated) import OpenAPIRuntime

extension Components.Schemas {
    /// A tool that generates images using GPT Image models, including Sunburst and Flare.
    ///
    ///
    /// - Remark: Generated from `#/components/schemas/ImageGenTool`.
    public struct ImageGenTool: Codable, Hashable, Sendable {
        /// The type of the image generation tool. Always `image_generation`.
        ///
        ///
        /// - Remark: Generated from `#/components/schemas/ImageGenTool/type`.
        @frozen public enum _TypePayload: String, Codable, Hashable, Sendable, CaseIterable {
            case imageGeneration = "image_generation"
        }
        /// The type of the image generation tool. Always `image_generation`.
        ///
        ///
        /// - Remark: Generated from `#/components/schemas/ImageGenTool/type`.
        public var _type: Components.Schemas.ImageGenTool._TypePayload
        /// The image generation model to use. Default: `gpt-image-1`.
        ///
        ///
        /// - Remark: Generated from `#/components/schemas/ImageGenTool/model`.
        @frozen public enum ModelPayload: String, Codable, Hashable, Sendable, CaseIterable {
            /// GPT Image 2.5 model for precise generation and editing.
            case gptImage2_5Sunburst = "gpt-image-2.5-sunburst"
            /// GPT Image 2.5 model for fast everyday image generation.
            case gptImage2_5Flare = "gpt-image-2.5-flare"
            case gptImage2 = "gpt-image-2"
            case gptImage2Codex = "gpt-image-2-codex"
            case gptImage1_5 = "gpt-image-1.5"
            case gptImage1 = "gpt-image-1"
            case gptImage1Mini = "gpt-image-1-mini"
        }
        /// The image generation model to use. Default: `gpt-image-1`.
        ///
        ///
        /// - Remark: Generated from `#/components/schemas/ImageGenTool/model`.
        public var model: Components.Schemas.ImageGenTool.ModelPayload?
        /// The quality of the generated image. One of `low`, `medium`, `high`,
        /// or `auto`. Default: `auto`.
        ///
        ///
        /// - Remark: Generated from `#/components/schemas/ImageGenTool/quality`.
        @frozen public enum QualityPayload: String, Codable, Hashable, Sendable, CaseIterable {
            case low = "low"
            case medium = "medium"
            case high = "high"
            case auto = "auto"
        }
        /// The quality of the generated image. One of `low`, `medium`, `high`,
        /// or `auto`. Default: `auto`.
        ///
        ///
        /// - Remark: Generated from `#/components/schemas/ImageGenTool/quality`.
        public var quality: Components.Schemas.ImageGenTool.QualityPayload?
        /// The size of the generated image. One of `1024x1024`, `1024x1536`,
        /// `1536x1024`, or `auto`. Default: `auto`.
        ///
        ///
        /// - Remark: Generated from `#/components/schemas/ImageGenTool/size`.
        @frozen public enum SizePayload: String, Codable, Hashable, Sendable, CaseIterable {
            case _1024x1024 = "1024x1024"
            case _1024x1536 = "1024x1536"
            case _1536x1024 = "1536x1024"
            case auto = "auto"
        }
        /// The size of the generated image. One of `1024x1024`, `1024x1536`,
        /// `1536x1024`, or `auto`. Default: `auto`.
        ///
        ///
        /// - Remark: Generated from `#/components/schemas/ImageGenTool/size`.
        public var size: Components.Schemas.ImageGenTool.SizePayload?
        /// The output format of the generated image. One of `png`, `webp`, or
        /// `jpeg`. Default: `png`.
        ///
        ///
        /// - Remark: Generated from `#/components/schemas/ImageGenTool/output_format`.
        @frozen public enum OutputFormatPayload: String, Codable, Hashable, Sendable, CaseIterable {
            case png = "png"
            case webp = "webp"
            case jpeg = "jpeg"
        }
        /// The output format of the generated image. One of `png`, `webp`, or
        /// `jpeg`. Default: `png`.
        ///
        ///
        /// - Remark: Generated from `#/components/schemas/ImageGenTool/output_format`.
        public var outputFormat: Components.Schemas.ImageGenTool.OutputFormatPayload?
        /// Compression level for the output image. Default: 100.
        ///
        ///
        /// - Remark: Generated from `#/components/schemas/ImageGenTool/output_compression`.
        public var outputCompression: Swift.Int?
        /// Moderation level for the generated image. Default: `auto`.
        ///
        ///
        /// - Remark: Generated from `#/components/schemas/ImageGenTool/moderation`.
        @frozen public enum ModerationPayload: String, Codable, Hashable, Sendable, CaseIterable {
            case auto = "auto"
            case low = "low"
        }
        /// Moderation level for the generated image. Default: `auto`.
        ///
        ///
        /// - Remark: Generated from `#/components/schemas/ImageGenTool/moderation`.
        public var moderation: Components.Schemas.ImageGenTool.ModerationPayload?
        /// Background type for the generated image. One of `transparent`,
        /// `opaque`, or `auto`. Default: `auto`.
        ///
        ///
        /// - Remark: Generated from `#/components/schemas/ImageGenTool/background`.
        @frozen public enum BackgroundPayload: String, Codable, Hashable, Sendable, CaseIterable {
            case transparent = "transparent"
            case opaque = "opaque"
            case auto = "auto"
        }
        /// Background type for the generated image. One of `transparent`,
        /// `opaque`, or `auto`. Default: `auto`.
        ///
        ///
        /// - Remark: Generated from `#/components/schemas/ImageGenTool/background`.
        public var background: Components.Schemas.ImageGenTool.BackgroundPayload?
        /// - Remark: Generated from `#/components/schemas/ImageGenTool/input_fidelity`.
        @frozen public enum InputFidelityPayload: Codable, Hashable, Sendable {
            /// - Remark: Generated from `#/components/schemas/ImageGenTool/input_fidelity/case1`.
            case InputFidelity(Components.Schemas.InputFidelity)
            public init(from decoder: any Decoder) throws {
                var errors: [any Error] = []
                do {
                    self = .InputFidelity(try decoder.decodeFromSingleValueContainer())
                    return
                } catch {
                    errors.append(error)
                }
                throw Swift.DecodingError.failedToDecodeOneOfSchema(
                    type: Self.self,
                    codingPath: decoder.codingPath,
                    errors: errors
                )
            }
            public func encode(to encoder: any Encoder) throws {
                switch self {
                    case let .InputFidelity(value):
                        try encoder.encodeToSingleValueContainer(value)
                }
            }
        }
        /// - Remark: Generated from `#/components/schemas/ImageGenTool/input_fidelity`.
        public var inputFidelity: Components.Schemas.ImageGenTool.InputFidelityPayload?
        /// Optional mask for inpainting. Contains `image_url`
        /// (string, optional) and `file_id` (string, optional).
        ///
        ///
        /// - Remark: Generated from `#/components/schemas/ImageGenTool/input_image_mask`.
        public struct InputImageMaskPayload: Codable, Hashable, Sendable {
            /// Base64-encoded mask image.
            ///
            ///
            /// - Remark: Generated from `#/components/schemas/ImageGenTool/input_image_mask/image_url`.
            public var imageUrl: Swift.String?
            /// File ID for the mask image.
            ///
            ///
            /// - Remark: Generated from `#/components/schemas/ImageGenTool/input_image_mask/file_id`.
            public var fileId: Swift.String?
            /// Creates a new `InputImageMaskPayload`.
            ///
            /// - Parameters:
            ///   - imageUrl: Base64-encoded mask image.
            ///   - fileId: File ID for the mask image.
            public init(
                imageUrl: Swift.String? = nil,
                fileId: Swift.String? = nil
            ) {
                self.imageUrl = imageUrl
                self.fileId = fileId
            }
            public enum CodingKeys: String, CodingKey {
                case imageUrl = "image_url"
                case fileId = "file_id"
            }
            public init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.imageUrl = try container.decodeIfPresent(
                    Swift.String.self,
                    forKey: .imageUrl
                )
                self.fileId = try container.decodeIfPresent(
                    Swift.String.self,
                    forKey: .fileId
                )
                try decoder.ensureNoAdditionalProperties(knownKeys: [
                    "image_url",
                    "file_id"
                ])
            }
        }
        /// Optional mask for inpainting. Contains `image_url`
        /// (string, optional) and `file_id` (string, optional).
        ///
        ///
        /// - Remark: Generated from `#/components/schemas/ImageGenTool/input_image_mask`.
        public var inputImageMask: Components.Schemas.ImageGenTool.InputImageMaskPayload?
        /// Number of partial images to generate in streaming mode, from 0 (default value) to 3.
        ///
        ///
        /// - Remark: Generated from `#/components/schemas/ImageGenTool/partial_images`.
        public var partialImages: Swift.Int?
        /// Creates a new `ImageGenTool`.
        ///
        /// - Parameters:
        ///   - _type: The type of the image generation tool. Always `image_generation`.
        ///   - model: The image generation model to use. Default: `gpt-image-1`.
        ///   - quality: The quality of the generated image. One of `low`, `medium`, `high`,
        ///   - size: The size of the generated image. One of `1024x1024`, `1024x1536`,
        ///   - outputFormat: The output format of the generated image. One of `png`, `webp`, or
        ///   - outputCompression: Compression level for the output image. Default: 100.
        ///   - moderation: Moderation level for the generated image. Default: `auto`.
        ///   - background: Background type for the generated image. One of `transparent`,
        ///   - inputFidelity:
        ///   - inputImageMask: Optional mask for inpainting. Contains `image_url`
        ///   - partialImages: Number of partial images to generate in streaming mode, from 0 (default value) to 3.
        public init(
            _type: Components.Schemas.ImageGenTool._TypePayload,
            model: Components.Schemas.ImageGenTool.ModelPayload? = nil,
            quality: Components.Schemas.ImageGenTool.QualityPayload? = nil,
            size: Components.Schemas.ImageGenTool.SizePayload? = nil,
            outputFormat: Components.Schemas.ImageGenTool.OutputFormatPayload? = nil,
            outputCompression: Swift.Int? = nil,
            moderation: Components.Schemas.ImageGenTool.ModerationPayload? = nil,
            background: Components.Schemas.ImageGenTool.BackgroundPayload? = nil,
            inputFidelity: Components.Schemas.ImageGenTool.InputFidelityPayload? = nil,
            inputImageMask: Components.Schemas.ImageGenTool.InputImageMaskPayload? = nil,
            partialImages: Swift.Int? = nil
        ) {
            self._type = _type
            self.model = model
            self.quality = quality
            self.size = size
            self.outputFormat = outputFormat
            self.outputCompression = outputCompression
            self.moderation = moderation
            self.background = background
            self.inputFidelity = inputFidelity
            self.inputImageMask = inputImageMask
            self.partialImages = partialImages
        }
        public enum CodingKeys: String, CodingKey {
            case _type = "type"
            case model
            case quality
            case size
            case outputFormat = "output_format"
            case outputCompression = "output_compression"
            case moderation
            case background
            case inputFidelity = "input_fidelity"
            case inputImageMask = "input_image_mask"
            case partialImages = "partial_images"
        }
    }
}
