#if os(iOS)
import AVFoundation
import UIKit

/// Keeps an active call's audio session aligned with system interruptions and route changes.
@available(iOS 17.0, *)
@MainActor final class VoiceAudioSession {
    /// Notification registrations exist only while this call owns audio.
    private var observers: [NSObjectProtocol] = []
    /// Prevents route and foreground events from overriding a system interruption.
    private var isInterrupted = false
    /// Updates the native call status without changing the user's mute preference.
    private let onInterruption: (Bool) -> Void
    /// Restarts the existing WebKit audio graph after the system permits audio again.
    private let onResume: () -> Void
    /// Lets the owner release media when resumption requires user action or fails.
    private let onFailure: (Error) -> Void

    /// Binds system audio events to the single owning media session.
    init(onInterruption: @escaping (Bool) -> Void, onResume: @escaping () -> Void,
         onFailure: @escaping (Error) -> Void) {
        self.onInterruption = onInterruption
        self.onResume = onResume
        self.onFailure = onFailure
    }

    /// Activates real recording or playback before the app may enter the background.
    func start(reading: Bool) throws {
        observe(AVAudioSession.interruptionNotification) { [weak self] note in
            self?.handleInterruption(note)
        }
        observe(AVAudioSession.routeChangeNotification) { [weak self] note in
            guard let self, !isInterrupted,
                  let value = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: value),
                  reason == .newDeviceAvailable || reason == .oldDeviceUnavailable else { return }
            onResume()
        }
        observe(AVAudioSession.mediaServicesWereResetNotification) { [weak self] _ in
            self?.onFailure(VoiceSessionError.audioInterrupted)
        }
        observe(UIApplication.didBecomeActiveNotification) { [weak self] _ in
            guard let self, !isInterrupted else { return }
            onResume()
        }
        let audio = AVAudioSession.sharedInstance()
        if reading {
            try audio.setCategory(.playback, mode: .spokenAudio)
        } else {
            try audio.setCategory(.playAndRecord, mode: .voiceChat,
                                  options: [.defaultToSpeaker, .allowBluetoothHFP])
        }
        try audio.setActive(true)
    }

    /// Removes callbacks before deactivating audio so stopped calls cannot resume themselves.
    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// A ready WebKit audio graph can supersede a stale host interruption even while both sides are silent.
    func mediaDidResume() {
        guard isInterrupted else { return }
        isInterrupted = false
        onInterruption(false)
    }

    /// Delivers all audio notifications on the main actor and ignores already removed observers.
    private func observe(_ name: Notification.Name, handler: @escaping @MainActor (Notification) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, !self.observers.isEmpty else { return }
                handler(note)
            }
        })
    }

    /// Resumes only when iOS recommends it; other endings preserve the call as a user-resumable pause.
    private func handleInterruption(_ note: Notification) {
        guard let value = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: value) else { return }
        switch type {
        case .began:
            isInterrupted = true
            onInterruption(true)
        case .ended:
            guard isInterrupted else { return }
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            guard AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) else {
                onFailure(VoiceSessionError.audioInterrupted)
                return
            }
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                isInterrupted = false
                onInterruption(false)
                onResume()
            } catch { onFailure(error) }
        @unknown default:
            break
        }
    }
}
#endif
