//
//  ImagesQuery.swift
//
//
//  Created by Sergii Kryvoblotskyi on 02/04/2023.
//

import Foundation

/// Given a prompt and/or an input image, the model will generate a new image.
/// https://platform.openai.com/docs/guides/images
public struct ImagesQuery: Codable, Equatable, Sendable {
    
    public enum ResponseFormat: String, Codable, Hashable, Sendable {
        case url
        case b64_json
    }
    
    /// A text description of the desired image(s). The maximum length is 1000 characters for dall-e-2 and 4000 characters for dall-e-3.
    public let prompt: String
    /// The model to use for image generation.
    /// Defaults to dall-e-2
    public let model: Model?
    /// The format in which the generated images are returned. Must be one of url or b64_json.
    /// Defaults to url
    public let responseFormat: Self.ResponseFormat?
    /// The number of images to generate. Must be between 1 and 10. For dall-e-3, only n=1 is supported.
    /// Defaults to 1
    public let n: Int?
    /// The size of the generated images. Must be one of 256x256, 512x512, or 1024x1024 for dall-e-2. Must be one of 1024x1024, 1792x1024, or 1024x1792 for dall-e-3 models.
    /// Defaults to 1024x1024
    public let size: Self.Size?
    /// A unique identifier representing your end-user, which can help OpenAI to monitor and detect abuse.
    /// https://platform.openai.com/docs/guides/safety-best-practices/end-user-ids
    public let user: String?
    /// The style of the generated images. Must be one of vivid or natural. Vivid causes the model to lean towards generating hyper-real and dramatic images. Natural causes the model to produce more natural, less hyper-real looking images. This param is only supported for dall-e-3.
    /// Defaults to vivid
    public let style: Self.Style?
    /// The quality of the image that will be generated. hd creates images with finer details and greater consistency across the image. This param is only supported for dall-e-3.
    /// Defaults to standard
    public let quality: Self.Quality?

    /// Encoded image format. GPT Image 2.6 additionally supports static SVG and animated GIF.
    public let outputFormat: OutputFormat?
    /// Optional SVG author selection. Omit unless the account supports SVG model selection.
    public let svg: SVGOptions?
    /// Number of GIF frames, from 2 through 16. Omit for other formats.
    public let frameCount: Int?
    /// GIF frame duration in milliseconds, at least 20. The service rounds to 10 ms and caps the encoded delay at 655350 ms. Omit for other formats.
    public let frameDurationMs: Int?

    /// Creates a generation request; SVG and GIF use non-streaming output with no response_format override.
    public init(
        prompt: String,
        model: Model? = nil,
        n: Int? = nil,
        quality:Self.Quality? = nil,
        responseFormat: Self.ResponseFormat? = nil,
        size: Size? = nil,
        style: Self.Style? = nil,
        user: String? = nil,
        outputFormat: OutputFormat? = nil,
        frameCount: Int? = nil,
        frameDurationMs: Int? = nil,
        svg: SVGOptions? = nil
    ) {
        self.prompt = prompt
        self.n = n
        self.size = size
        self.model = model
        self.responseFormat = responseFormat
        self.style = style
        self.user = user
        self.quality = quality
        self.outputFormat = outputFormat
        self.frameCount = frameCount
        self.frameDurationMs = frameDurationMs
        self.svg = svg
    }

    /// Maps generation parameters to their API field names.
    public enum CodingKeys: String, CodingKey {
        case model
        case prompt
        case n
        case size
        case user
        case style
        case responseFormat = "response_format"
        case quality
        case outputFormat = "output_format"
        case svg
        case frameCount = "frame_count"
        case frameDurationMs = "frame_duration_ms"
    }

    /// Selects the SVG author independently of the image model that creates its reference image.
    public struct SVGOptions: Codable, Equatable, Sendable {
        /// SVG author model required when the account has SVG model selection enabled.
        public let model: Model

        /// Creates explicit SVG author selection while leaving its reasoning at the service default.
        public init(model: Model) {
            self.model = model
        }
    }

    /// File formats returned as base64 bytes by GPT Image models.
    public enum OutputFormat: String, Codable, CaseIterable, Hashable, Sendable {
        /// Portable Network Graphics, also the default for image edits.
        case png
        /// JPEG raster image.
        case jpeg
        /// WebP raster image.
        case webp
        /// Animated GIF; generation only on GPT Image 2.6.
        case gif
        /// Static vector SVG; generation only on GPT Image 2.6.
        case svg
    }

    public enum Style: String, Codable, CaseIterable, Hashable, Sendable {
        case natural
        case vivid
    }

    public enum Quality: String, Codable, CaseIterable, Hashable, Sendable {
        case standard
        case hd
        case high, medium, low  /// for gpt-image-1
    }

    /// The size of the generated images.
    /// - For gpt-image-1, one of `1024x1024`, `1536x1024` (landscape), `1024x1536` (portrait), or `auto` (default value)
    public enum Size: String, Codable, CaseIterable, Hashable, Sendable {
        case _256 = "256x256"
        case _512 = "512x512"
        case _1024 = "1024x1024"
        case _1792_1024 = "1792x1024" // for dall-e-3 models
        case _1024_1792 = "1024x1792" // for dall-e-3 models
        case _1536x1024 = "1536x1024" // only for gpt-image-1
        case _1024x1536 = "1024x1536" // only for gpt-image-1
        case auto                     // only for gpt-image-1
    }

    public enum InputImage: Codable, Hashable, Sendable {
        case png(Data)
        case jpeg(Data)

        public var content: Data {
            switch self {
            case let .png(data), let .jpeg(data):
                return data
            }
        }

        public var contentType: String {
            switch self {
            case .png:
                return "image/png"
            case .jpeg:
                return "image/jpeg"
            }
        }
    }
}
