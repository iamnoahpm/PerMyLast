import Foundation

/// How much thinking the model does. Sent as `output_config.effort`.
public enum Effort: String, Codable, CaseIterable, Sendable {
    case low, medium, high, xhigh, max
}

public struct ModelOption: Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
}

public enum ModelCatalog {
    public static let defaultModel = "claude-sonnet-5"
    public static let defaultEffort = Effort.medium

    /// Older-tier models reject the `output_config` effort parameter outright.
    public static let effortUnsupportedModels: Set<String> = ["claude-haiku-4-5"]

    public static let standardModels: [ModelOption] = [
        ModelOption(id: "claude-sonnet-5", displayName: "Claude Sonnet 5 — Recommended"),
        ModelOption(id: "claude-opus-5", displayName: "Claude Opus 5 (Most Capable)"),
        ModelOption(id: "claude-haiku-4-5", displayName: "Claude Haiku 4.5 (Fastest)"),
        ModelOption(id: "claude-fable-5", displayName: "Claude Fable 5 (Frontier)")
    ]

    public static func supportsEffort(_ model: String) -> Bool {
        !effortUnsupportedModels.contains(model)
    }
}
