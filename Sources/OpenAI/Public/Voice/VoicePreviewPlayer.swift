#if canImport(AVFoundation) && (os(iOS) || os(macOS))
import AVFoundation
import Foundation
import Observation

/// Shared, cancellable sample playback for API-key and Codex voice settings.
@available(iOS 17.0, macOS 14.0, *)
@MainActor @Observable public final class VoicePreviewPlayer {
    /// Covers authentication, sample generation, and download.
    public private(set) var isLoading = false
    /// Remains true until the sample ends or the user stops it.
    public private(set) var isPlaying = false
    /// Latest failure, cleared by a new preview or an explicit stop.
    public private(set) var error: Error?
    /// Owns the pending request and the playback lifetime.
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Plays the complete sample without opening a microphone.
    @ObservationIgnored private var player: AVAudioPlayer?
    /// Prevents cancelled requests from updating a newer preview.
    @ObservationIgnored private var generation = UUID()
    /// Transport for the authenticated catalog and its separate audio download.
    @ObservationIgnored private let urlSession: URLSession

    /// Creates a player whose lifetime is owned by the settings view.
    public init(urlSession: URLSession = .shared) { self.urlSession = urlSession }

    /// Starts one sample, replacing any previous request or playback.
    public func play(voice: String, language: String, text: String,
                     authentication: @escaping @MainActor () async throws -> VoiceSessionAuthentication) {
        stop()
        let current = generation
        isLoading = true
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == current {
                    player?.stop()
                    player = nil
                    task = nil
                    isLoading = false
                    isPlaying = false
                }
            }
            do {
                let auth = try await authentication()
                try Task.checkCancellation()
                let data = try await VoicePreviewAudio.load(voice: voice, language: language, text: text,
                                                           authentication: auth, urlSession: urlSession)
                try Task.checkCancellation()
                guard generation == current else { return }
                let audio = try AVAudioPlayer(data: data)
                player = audio
                guard audio.play() else { throw URLError(.cannotDecodeContentData) }
                isLoading = false
                isPlaying = true
                while audio.isPlaying {
                    try await Task.sleep(for: .milliseconds(100))
                }
            } catch {
                guard generation == current, !Task.isCancelled else { return }
                self.error = error
            }
        }
    }

    /// Stops immediately, including a sample still waiting for authentication or network data.
    public func stop() {
        generation = UUID()
        task?.cancel()
        task = nil
        player?.stop()
        player = nil
        isLoading = false
        isPlaying = false
        error = nil
    }
}
#endif
