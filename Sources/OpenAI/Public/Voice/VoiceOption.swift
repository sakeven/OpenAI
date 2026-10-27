import Foundation

/// A backend voice identifier and its user-facing proper name.
public struct VoiceOption: Identifiable, Hashable, Sendable {
    /// Exact identifier accepted by the voice service.
    public let id: String
    /// Display name, which may differ from the service identifier.
    public let name: String

    /// Creates one supported voice entry.
    public init(id: String, name: String) { self.id = id; self.name = name }

    /// Built-in public Realtime voices, with the recommended voices first.
    public static let realtime: [VoiceOption] = [
        "marin", "cedar", "alloy", "ash", "ballad", "coral", "echo", "sage", "shimmer", "verse"
    ].map { VoiceOption(id: $0, name: $0.capitalized) }

    /// Desktop wingman catalog verified from settings/voices on 2026-10-27.
    public static let codex: [VoiceOption] = [
        VoiceOption(id: "cove", name: "Cove"), VoiceOption(id: "juniper", name: "Juniper"),
        VoiceOption(id: "ember", name: "Ember"), VoiceOption(id: "breeze", name: "Breeze"),
        VoiceOption(id: "maple", name: "Maple"), VoiceOption(id: "vale", name: "Vale"),
        VoiceOption(id: "fathom", name: "Arbor"), VoiceOption(id: "orbit", name: "Spruce"),
        VoiceOption(id: "glimmer", name: "Sol"), VoiceOption(id: "bubbie", name: "Bubbie"),
        VoiceOption(id: "neer", name: "Neer"), VoiceOption(id: "leher", name: "Leher"),
        VoiceOption(id: "arrullo", name: "Arrullo"), VoiceOption(id: "tinta", name: "Tinta"),
        VoiceOption(id: "viola", name: "Viola"), VoiceOption(id: "rio", name: "Rio"),
        VoiceOption(id: "sonna", name: "Sonna"), VoiceOption(id: "miko", name: "Miko"),
        VoiceOption(id: "rindo", name: "Rindō"), VoiceOption(id: "himari", name: "Himari"),
        VoiceOption(id: "aube", name: "Aube"), VoiceOption(id: "rivage", name: "Rivage"),
        VoiceOption(id: "hanul", name: "Hanul"), VoiceOption(id: "haetsal", name: "Haetsal")
    ]
}
