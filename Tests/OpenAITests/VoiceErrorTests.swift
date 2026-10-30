#if canImport(WebKit) && (os(iOS) || os(macOS))
import Foundation
import XCTest
@testable import OpenAI

/// Exercises rejected commands independently from media termination and replacement sessions.
@available(iOS 17.0, macOS 14.0, *)
@MainActor
final class VoiceErrorTests: XCTestCase {
    /// Public and Codex errors preserve service diagnostics even when identity and code are null.
    func testServiceErrorShapes() {
        let nested = VoiceServiceError(event: ["error": ["message": "Rejected", "code": "immutable_field", "client_event_id": "one"]])
        XCTAssertEqual(nested.message, "Rejected")
        XCTAssertEqual(nested.code, "immutable_field")
        XCTAssertEqual(nested.clientEventID, "one")
        for event: [String: Any] in [
            ["message": "Rejected", "code": NSNull(), "client_event_id": NSNull()],
            ["error": "Rejected"], ["error": ["message": "Rejected", "code": NSNull()]]
        ] {
            let failure = VoiceServiceError(event: event)
            XCTAssertEqual(failure.message, "Rejected")
            XCTAssertNil(failure.code)
            XCTAssertNil(failure.clientEventID)
        }
        XCTAssertFalse(VoiceServiceError(event: [:]).message.isEmpty)
    }

    /// An immediate rejection reaches its sender, and a subsequent unrelated append can still succeed.
    func testRejectedAppendDoesNotPoisonLaterCommands() async throws {
        let commands = LiveVoiceCommands()
        let failure = VoiceServiceError(event: ["error": ["message": "Invalid delegation", "client_event_id": "bad"]])
        do {
            try await commands.send(id: "bad") {
                XCTAssertFalse(commands.resolve(id: "other", result: .success(())))
                commands.resolve(id: "bad", result: .failure(failure))
            }
            XCTFail("Rejected context must not be reported as delivered")
        } catch let error as VoiceServiceError { XCTAssertEqual(error, failure) }
        try await commands.send(id: "good") {
            commands.resolve(id: "good", result: .success(()))
            XCTAssertFalse(commands.resolve(id: "good", result: .success(())))
        }
    }

    /// Closing releases pending work and late acknowledgments cannot complete a replacement command.
    func testCloseAndCancellationReleaseWaiters() async throws {
        let commands = LiveVoiceCommands()
        do {
            try await commands.send(id: "closing") { commands.finish(error: CancellationError()) }
            XCTFail("Close must cancel the pending append")
        } catch is CancellationError {}
        XCTAssertFalse(commands.resolve(id: "closing", result: .success(())))
        var transmitted = false
        let task = Task {
            try await commands.send(id: "cancelled") { transmitted = true }
        }
        while !transmitted { await Task.yield() }
        task.cancel()
        do { try await task.value; XCTFail("Cancellation must release the sender") }
        catch is CancellationError {}
        try await commands.send(id: "replacement") {
            XCTAssertFalse(commands.resolve(id: "cancelled", result: .success(())))
            commands.resolve(id: "replacement", result: .success(()))
        }
    }

    /// Local transmission errors propagate without waiting for an acknowledgment that cannot arrive.
    func testTransmissionFailure() async {
        do {
            try await LiveVoiceCommands().send(id: "offline") { throw URLError(.notConnectedToInternet) }
            XCTFail("Failed transport must reject its sender")
        } catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
    }

    /// Exercises the real session reducer before its unmounted media document can start a network request.
    func testRunningErrorsKeepCallAliveAndCloseStillEndsIt() async {
        let session = LiveVoiceSession()
        let call = Task {
            try await session.run(instructions: "Test", readingText: "Test", authentication: {
                XCTFail("This test must not authenticate")
                throw CancellationError()
            })
        }
        while !session.isActive { await Task.yield() }
        session.handle(["type": "session.started"])
        session.handle(["type": "error", "error": ["message": "Rejected", "code": "immutable_field"]])
        XCTAssertTrue(session.isActive)
        XCTAssertTrue(session.isConnected)
        XCTAssertEqual(session.serviceError?.code, "immutable_field")
        session.handle(["type": "error", "message": "Audio interrupted"])
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.errorMessage, "Audio interrupted")
        session.handle(["type": "session.closed", "reason": "connection_lost"])
        XCTAssertFalse(session.isActive)
        do { try await call.value; XCTFail("Connection loss must remain recoverable by the host") }
        catch VoiceSessionError.connectionFailed {} catch { XCTFail("Unexpected error: \(error)") }
    }
}
#endif
