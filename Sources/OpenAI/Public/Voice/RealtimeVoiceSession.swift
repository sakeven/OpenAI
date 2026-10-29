#if canImport(WebKit) && (os(iOS) || os(macOS))
import AVFoundation
import Observation
import WebKit

/// Owns one cancellable WebRTC call and its native presentation state.
@available(iOS 17.0, macOS 14.0, *)
@MainActor @Observable
public final class RealtimeVoiceSession: NSObject {
    /// The currently mounted local media document, retained only while a call is active.
    public private(set) var webView: WKWebView?
    /// Indicates an established voice session rather than a merely completed HTTP request.
    public private(set) var isConnected = false
    /// True during permission checks, connection setup, and media playback.
    public private(set) var isActive = false
    /// Reflects the actual microphone track state.
    public private(set) var isMuted = false
    /// True while WebRTC is giving a temporarily disconnected transport time to recover.
    public private(set) var isReconnecting = false
    /// Reports a system audio interruption, never a user-muted or temporarily muted input track.
    public private(set) var isInterrupted = false
    #if os(iOS)
    /// Owns system audio observers for exactly the current call's lifetime.
    @ObservationIgnored private var audioSession: VoiceAudioSession?
    #endif
    /// Current playback energy, used to distinguish listening from speaking.
    public private(set) var outputLevel = 0.0
    /// Recent measured audio levels for the native waveform.
    public private(set) var levels = Array(repeating: 0.0, count: 31)
    /// Ephemeral live captions; partial display text is never emitted as a completed message.
    public private(set) var captions: [VoiceCaption] = []
    /// Service-confirmed conversation messages, distinct from the live caption stream.
    public private(set) var messages: [VoiceMessage] = []
    /// Start time of the connected session for the elapsed-time display.
    public private(set) var connectedAt: Date?
    /// Terminal failure displayed by the native controls.
    public private(set) var errorMessage: String?
    /// Prevents two chat windows from capturing the microphone simultaneously.
    private static weak var activeSession: RealtimeVoiceSession?
    /// Identifies this attempt so a cancelled predecessor cannot close a retry.
    @ObservationIgnored private var generation = UUID()
    /// Creates a disconnected call, without requesting permission or starting media.
    public override init() { super.init() }

    /// Native continuation resolved exactly once when the session finishes or is stopped.
    @ObservationIgnored private var completion: CheckedContinuation<Void, Error>?
    /// Cancellable native HTTP handshake.
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
    /// Deadline covering negotiation, complete history replay, and media readiness.
    @ObservationIgnored private var startupTask: Task<Void, Never>?
    /// Bounded lifetime of a one-shot reading request.
    @ObservationIgnored private var readingTask: Task<Void, Never>?
    /// Credentials refreshed in Swift immediately before the handshake.
    @ObservationIgnored private var authentication: (() async throws -> VoiceSessionAuthentication)?
    /// Prompt and existing full text conversation sent during call creation.
    @ObservationIgnored private var instructions = ""
    /// Complete prior chat messages, never a truncated note-body preview.
    @ObservationIgnored private var history: [[String: Any]] = []
    /// Identity shared with the current native chat.
    @ObservationIgnored private var threadID = ""
    /// Voice captured at the start of this call; settings changes apply to the next call.
    @ObservationIgnored private var voice: String?
    /// A non-nil value selects microphone-free read-aloud mode.
    @ObservationIgnored private var readingText: String?
    /// Routes delegation events to the existing AI Chat tools.
    @ObservationIgnored private var delegationHandler: ((VoiceDelegation) -> Void)?
    /// Publishes only authoritative service messages for the embedding application to persist.
    @ObservationIgnored private var messageHandler: ((VoiceMessage) -> Void)?
    /// Notifies the owner after complete history replay and live media readiness, including silent input.
    @ObservationIgnored private var readyHandler: (() -> Void)?
    /// Holds the ready callback until WebKit confirms its audio clock and tracks are running.
    @ObservationIgnored private var awaitsMediaReadiness = false
    /// Selects the established protocol after native authentication resolves.
    @ObservationIgnored private var usesCodex = true
    /// Outstanding API function calls must all receive results before requesting another response.
    @ObservationIgnored private var pendingCallIDs: Set<String> = []
    /// Partial caption identities for independent user and assistant turns.
    @ObservationIgnored private var partialIDs: [String: String] = [:]
    /// Prevents replayed completion events from duplicating captions.
    @ObservationIgnored private var completedTurnIDs: Set<String> = []

    /// Starts a call with the retained mute preference; cancelling its owning task releases the microphone.
    public func run(instructions: String, history: [VoiceMessage] = [], threadID: String = UUID().uuidString,
             voice: String? = nil, readingText: String? = nil, initiallyMuted: Bool = false,
             authentication: @escaping () async throws -> VoiceSessionAuthentication,
             onDelegation: @escaping (VoiceDelegation) -> Void = { _ in },
             onMessage: @escaping (VoiceMessage) -> Void = { _ in },
             onReady: @escaping () -> Void = {}) async throws {
        let runID = UUID()
        Self.activeSession?.stop()
        generation = runID
        Self.activeSession = self
        self.instructions = instructions
        self.history = history.map(\.wireValue)
        self.threadID = threadID
        self.readingText = readingText
        self.voice = voice
        self.authentication = authentication
        delegationHandler = onDelegation
        messageHandler = onMessage
        readyHandler = onReady
        awaitsMediaReadiness = false
        isActive = true
        errorMessage = nil
        isMuted = initiallyMuted
        isReconnecting = false
        isInterrupted = false
        captions = []
        messages = []
        partialIDs = [:]
        completedTurnIDs = []
        pendingCallIDs = []
        connectedAt = nil
        try await withTaskCancellationHandler {
            do {
                if readingText == nil {
                    guard await AVCaptureDevice.requestAccess(for: .audio) else {
                        throw VoiceSessionError.microphoneDenied
                    }
                }
                try Task.checkCancellation()
                guard isActive, generation == runID else { throw CancellationError() }
                #if os(iOS)
                let audio = VoiceAudioSession(
                    onInterruption: { [weak self] in self?.isInterrupted = $0 },
                    onResume: { [weak self] in self?.resumeMedia() },
                    onFailure: { [weak self] in self?.finish(error: $0) })
                audioSession = audio
                try audio.start(reading: readingText != nil)
                #endif
                try await withCheckedThrowingContinuation { continuation in
                    completion = continuation
                    mountDocument()
                }
            } catch {
                if generation == runID { finish(error: error) }
                throw error
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                if self?.generation == runID { self?.stop() }
            }
        }
    }

    /// Creates the only permitted web document and starts a bounded connection attempt.
    private func mountDocument() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        #if os(iOS)
        configuration.allowsInlineMediaPlayback = true
        #endif
        configuration.userContentController.add(VoiceMessageHandler(session: self), name: "voice")
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = self
        web.uiDelegate = self
        webView = web
        web.loadHTMLString(CodexVoiceWebDocument.html, baseURL: URL(string: "https://localhost"))
        startupTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(35)) } catch { return }
            self?.finish(error: VoiceSessionError.connectionFailed)
        }
    }

    /// Uses the system callback API so older supported OS versions do not need the new Swift WebKit overlay runtime.
    private func evaluateJavaScript(_ script: String, arguments: [String: Any], in web: WKWebView) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            web.__callAsyncJavaScript(script, arguments: arguments, inFrame: nil, in: .page) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    /// Waits through a temporary transport loss and rejects sends from an ended or replaced call.
    func send(_ event: [String: Any]) async throws {
        try Task.checkCancellation()
        guard isConnected, let web = webView else { throw VoiceSessionError.connectionFailed }
        do {
            while isReconnecting, isActive, webView === web {
                try await Task.sleep(for: .milliseconds(100))
            }
            guard isActive, webView === web else { throw CancellationError() }
            try await evaluateJavaScript("window.voiceSend(event)", arguments: ["event": event], in: web)
            try Task.checkCancellation()
            guard webView === web else { throw CancellationError() }
        } catch {
            guard webView === web else { throw CancellationError() }
            let failure: Error = error.localizedDescription.contains("textTooLong") ? VoiceSessionError.textTooLong
                : error.localizedDescription.contains("disconnected") ? VoiceSessionError.connectionFailed : error
            finish(error: failure)
            throw failure
        }
    }

    /// Resumes the existing media graph without replacing its tracks or clearing the user's mute choice.
    private func resumeMedia() {
        guard isConnected, !isInterrupted, let web = webView else { return }
        Task {
            do { try await evaluateJavaScript("await window.voiceResume()", arguments: [:], in: web) }
            catch { if webView === web { finish(error: error) } }
        }
    }

    /// Returns a complete application result using the selected backend's event dialect.
    public func respond(to request: VoiceDelegation, text: String) async throws {
        if usesCodex {
            try await sendCodexContext(text, delegationID: request.id)
        } else {
            try await send(RealtimeVoiceProtocol.result(text, id: request.id))
            pendingCallIDs.remove(request.id)
            if pendingCallIDs.isEmpty { try await send(["type": "response.create"]) }
        }
    }

    /// Supplies a full application update after reconnection, without reusing a delegation ID from the old call.
    public func provideContext(_ text: String) async throws {
        if usesCodex {
            try await sendCodexContext(text)
        } else {
            try await send(["type": "conversation.item.create",
                            "item": VoiceMessage(role: .user, text: text).wireValue])
        }
    }

    /// Sends ordered, bounded updates for task replies, resumed results and reading alike.
    private func sendCodexContext(_ text: String, delegationID: String? = nil) async throws {
        for event in CodexVoiceProtocol.contextEvents(text, delegationID: delegationID) {
            try await send(event)
        }
    }

    /// Toggles the real input track, leaving incoming audio and captions available.
    public func toggleMute() {
        guard isConnected, readingText == nil, let web = webView else { return }
        let muted = !isMuted
        Task {
            do {
                try await evaluateJavaScript("window.voiceMute(muted)", arguments: ["muted": muted], in: web)
                if webView === web { isMuted = muted }
            } catch { if webView === web { finish(error: error) } }
        }
    }

    /// Ends the call without presenting intentional cancellation as an error.
    public func stop() { finish(error: CancellationError()) }

    /// Preserves system interruption semantics while releasing media before resuming the owning operation.
    private func finish(error: Error? = nil) {
        guard isActive else { return }
        let finalError: Error? = isInterrupted && error != nil && !(error is CancellationError)
            ? VoiceSessionError.audioInterrupted : error
        isActive = false
        isConnected = false
        isReconnecting = false
        isInterrupted = false
        outputLevel = 0
        levels = Array(repeating: 0, count: 31)
        if let finalError {
            switch finalError {
            case is CancellationError, VoiceSessionError.audioInterrupted: break
            default: errorMessage = finalError.localizedDescription
            }
        }
        startupTask?.cancel(); startupTask = nil
        connectionTask?.cancel(); connectionTask = nil
        readingTask?.cancel(); readingTask = nil
        webView?.evaluateJavaScript("window.voiceClose()", completionHandler: nil)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "voice")
        webView = nil
        authentication = nil
        delegationHandler = nil
        messageHandler = nil
        readyHandler = nil
        awaitsMediaReadiness = false
        if Self.activeSession === self { Self.activeSession = nil }
        #if os(iOS)
        audioSession?.stop()
        audioSession = nil
        #endif
        let continuation = completion
        completion = nil
        if let finalError { continuation?.resume(throwing: finalError) } else { continuation?.resume() }
    }

    /// Accepts media recovery and service events only from the current local main frame.
    func receive(_ message: WKScriptMessage) {
        guard isActive, message.webView === webView, message.frameInfo.isMainFrame,
              let value = message.body as? [String: Any] else { return }
        if let failure = value["failure"] as? String {
            finish(error: failure == "permission" ? VoiceSessionError.microphoneDenied
                   : failure == "disconnected" ? VoiceSessionError.connectionFailed : VoiceSessionError.server(failure))
        } else if let recovering = value["reconnecting"] as? Bool {
            isReconnecting = recovering
        } else if let sdp = value["sdp"] as? String {
            connectionTask = Task { await connect(sdp: sdp) }
        } else if let event = value["event"] as? [String: Any] {
            handle(event)
        } else if value["finished"] as? Bool == true, readingText != nil {
            finish()
        } else if let input = value["inputLevel"] as? Double, let output = value["outputLevel"] as? Double {
            // Clear setup interruptions before exposing readiness so the UI never waits for audible speech.
            if value["mediaReady"] as? Bool == true {
                if isInterrupted {
                    isInterrupted = false
                    #if os(iOS)
                    audioSession?.mediaDidResume()
                    #endif
                }
                if awaitsMediaReadiness {
                    awaitsMediaReadiness = false
                    startupTask?.cancel(); startupTask = nil
                    readyHandler?()
                }
            }
            outputLevel = output
            levels.removeFirst()
            levels.append(min(1, max(isMuted ? 0 : input, output) * 8))
        }
    }

    /// Exchanges the SDP in Swift and installs the answer only if the same call is still active.
    private func connect(sdp: String) async {
        guard let authentication, let web = webView else { return }
        do {
            let auth = try await authentication()
            try Task.checkCancellation()
            let request: URLRequest
            usesCodex = auth.isCodex
            switch auth {
            case .codexOAuth(let token, let accountID):
                request = try CodexVoiceProtocol.request(sdp: sdp, accessToken: token, accountID: accountID,
                    instructions: instructions, history: history, threadID: threadID, voice: voice ?? "cove")
            case .apiKey(let token, let host):
                request = try RealtimeVoiceProtocol.request(sdp: sdp, token: token, host: host, instructions: instructions, voice: voice ?? "marin")
            }
            try await evaluateJavaScript("window.voiceIsCodex = codex", arguments: ["codex": usesCodex], in: web)
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            let answer = try CodexVoiceProtocol.answer(data: data, response: response)
            guard isActive, webView === web else { return }
            try await evaluateJavaScript("await window.voiceAnswer(sdp)", arguments: ["sdp": answer], in: web)
        } catch { if webView === web { finish(error: error) } }
    }

    /// Replays history before applying the retained mute state and accepting new speech or tool results.
    func handle(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "session.started", "session.created":
            guard !isConnected else { return }
            isConnected = true
            connectedAt = Date()
            if readingText != nil { startupTask?.cancel(); startupTask = nil }
            readingTask = Task { [weak self] in
                guard let self, let web = webView else { return }
                do {
                    if !usesCodex {
                        for event in RealtimeVoiceProtocol.historyEvents(history) { try await send(event) }
                    }
                    if let readingText {
                        if usesCodex { try await sendCodexContext(readingText) }
                        else { try await send(RealtimeVoiceProtocol.reading(readingText)) }
                        try await Task.sleep(for: .seconds(300))
                        if webView === web { finish(error: VoiceSessionError.readingTimedOut) }
                    } else {
                        try await evaluateJavaScript("window.voiceMute(muted)", arguments: ["muted": isMuted], in: web)
                        if webView === web { awaitsMediaReadiness = true }
                    }
                } catch is CancellationError {} catch { if webView === web { finish(error: error) } }
            }
        case "input_audio_buffer.speech_started":
            // Reserve the user's position before slower transcription completes after an assistant reply.
            if let id = event["item_id"] as? String {
                updateCaption(role: "user", text: "", complete: false, itemID: id)
            }
        case "conversation.item.input_audio_transcription.delta", "response.output_audio_transcript.delta":
            if let id = event["item_id"] as? String, let text = event["delta"] as? String {
                let role = event["type"] as? String == "conversation.item.input_audio_transcription.delta" ? "user" : "assistant"
                updateCaption(role: role, text: text, complete: false, itemID: id)
            }
        case "conversation.item.input_audio_transcription.completed", "response.output_audio_transcript.done":
            if let id = event["item_id"] as? String, let text = event["transcript"] as? String {
                let role = event["type"] as? String == "conversation.item.input_audio_transcription.completed" ? "user" : "assistant"
                updateCaption(role: role, text: text, complete: true, itemID: id)
                if role == "user" { commitMessage(.init(id: id, role: .user, text: text)) }
            }
        case "conversation.item.input_audio_transcription.failed":
            let error = event["error"] as? [String: Any]
            finish(error: VoiceSessionError.server(error?["message"] as? String ?? String(localized: "The voice service returned an invalid response.")))
        case "response.done":
            do {
                for message in RealtimeVoiceProtocol.messages(from: event) { commitMessage(message) }
                let requests = try RealtimeVoiceProtocol.delegations(from: event)
                pendingCallIDs.formUnion(requests.map(\.id))
                for request in requests { delegationHandler?(request) }
            } catch { finish(error: error) }
        case "input_transcript.added", "output_transcript.added":
            if let item = event["item"] as? [String: Any], let text = item["text"] as? String {
                let role = event["type"] as? String == "input_transcript.added" ? "user" : "assistant"
                updateCaption(role: role, text: text, complete: false)
            }
        case "turn.done":
            if let turn = event["turn"] as? [String: Any], let id = turn["id"] as? String,
               let role = turn["role"] as? String, ["user", "assistant"].contains(role),
               let text = turn["transcript"] as? String, completedTurnIDs.insert(id).inserted {
                let messageID = partialIDs[role] ?? id
                updateCaption(role: role, text: text, complete: true, itemID: messageID)
                partialIDs[role] = nil
                commitMessage(.init(id: messageID, role: role == "user" ? .user : .assistant, text: text))
            }
        case "error":
            let error = event["error"] as? [String: Any]
            finish(error: VoiceSessionError.server(error?["message"] as? String ?? String(localized: "The voice service returned an invalid response.")))
        case "session.closed": finish()
        default: break
        }
        if let request = CodexVoiceProtocol.delegation(from: event) {
            delegationHandler?(VoiceDelegation(id: request.id, text: request.text))
        }
    }

    /// Commits complete service messages in speech order without reading text back from the caption view.
    private func commitMessage(_ message: VoiceMessage) {
        guard !message.text.isEmpty else { return }
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            guard messages[index] != message else { return }
            messages[index] = message
        } else if let position = captions.firstIndex(where: { $0.id == message.id }),
                  let next = messages.firstIndex(where: { item in
                      captions.firstIndex(where: { $0.id == item.id }).map { $0 > position } ?? false
                  }) {
            messages.insert(message, at: next)
        } else {
            messages.append(message)
        }
        messageHandler?(message)
    }

    /// Accumulates partial words, then replaces them with the complete authoritative turn text.
    private func updateCaption(role: String, text: String, complete: Bool, itemID: String? = nil) {
        let id = itemID ?? partialIDs[role] ?? UUID().uuidString
        if let index = captions.firstIndex(where: { $0.id == id }) {
            guard !captions[index].isComplete else { return }
            captions[index].text = complete ? text : captions[index].text + text
            captions[index].isComplete = complete
        } else {
            captions.append(.init(id: id, role: role, text: text, isComplete: complete))
        }
        if itemID == nil { partialIDs[role] = complete ? nil : id }
    }
}

@available(iOS 17.0, macOS 14.0, *)
extension RealtimeVoiceSession: WKNavigationDelegate, WKUIDelegate {
    /// Starts WebRTC after the local document is loaded and mounted by SwiftUI.
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard isActive, self.webView === webView else { return }
        Task {
            do {
                try await evaluateJavaScript("await window.voiceStart(microphone)",
                    arguments: ["microphone": readingText == nil], in: webView)
            } catch { if self.webView === webView { finish(error: error) } }
        }
    }

    /// Grants only microphone capture to the app-owned document after native permission approval.
    public func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(isActive && self.webView === webView && readingText == nil && frame.isMainFrame
                        && origin.host == "localhost" && type == .microphone ? .grant : .deny)
    }

    /// Blocks any attempt to navigate the media document to external content.
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.host == "localhost" ? .allow : .cancel)
    }

    /// Treats a terminated media process as a disconnected call.
    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if self.webView === webView { finish(error: VoiceSessionError.connectionFailed) }
    }
}

#endif
