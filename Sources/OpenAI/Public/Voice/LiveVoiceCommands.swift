import Foundation

/// Correlates public Live append confirmations without assuming Codex has the same acknowledgment contract.
@MainActor
final class LiveVoiceCommands {
    /// Each suspended sender owns exactly one unique outgoing event identity.
    private var pending: [String: CheckedContinuation<Void, Error>] = [:]

    /// Registers before transmission so even an immediate acknowledgment or rejection resolves its sender.
    func send(id: String, transmit: @escaping @MainActor () async throws -> Void) async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                Task {
                    guard pending[id] != nil else { return }
                    do { try await transmit() }
                    catch { resolve(id: id, result: .failure(error)) }
                }
            }
        } onCancel: {
            Task { @MainActor in self.resolve(id: id, result: .failure(CancellationError())) }
        }
    }

    /// Only the matching append can complete; unrelated or duplicated server events are harmless.
    @discardableResult
    func resolve(id: String, result: Result<Void, Error>) -> Bool {
        guard let continuation = pending.removeValue(forKey: id) else { return false }
        continuation.resume(with: result)
        return true
    }

    /// Closing a call releases all waiting senders so a replacement cannot receive stale completions.
    func finish(error: Error) {
        let continuations = pending.values
        pending.removeAll()
        for continuation in continuations { continuation.resume(throwing: error) }
    }
}
