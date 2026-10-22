import Foundation

/// A prompt template (FR-A5). The system prompt and the shape of the user message
/// live here; callers supply only variables. `model` is optional: the direct
/// (BYOK) client always uses the model the user picked in Settings.
public struct PromptTemplate: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let description: String
    public let system: String
    public let userTemplate: String
    public let variables: [String]
    public let model: String?
    public let maxTokens: Int
    public let version: Int

    private enum CodingKeys: String, CodingKey {
        case id, title, description, system, variables, model, version
        case userTemplate = "user_template"
        case maxTokens = "max_tokens"
    }

    /// Fills `{{variable}}` placeholders in one pass, so a value that itself
    /// contains `{{…}}` is never substituted again. Every declared variable is required.
    public func render(_ values: [String: String]) throws -> String {
        for name in variables where values[name] == nil { throw AnthropicError.missingVariable(name) }
        var out = ""
        var rest = Substring(userTemplate)
        while let open = rest.range(of: "{{") {
            out += rest[..<open.lowerBound]
            let afterOpen = rest[open.upperBound...]
            guard let close = afterOpen.range(of: "}}") else { out += rest[open.lowerBound...]; rest = ""; break }
            let name = String(afterOpen[..<close.lowerBound])
            if let value = values[name] {
                out += value
            } else {
                out += rest[open.lowerBound..<close.upperBound]
            }
            rest = afterOpen[close.upperBound...]
        }
        return out + rest
    }
}

public struct TemplateBundle: Codable, Equatable, Sendable {
    public let version: Int
    public let templates: [PromptTemplate]
}

/// The set of templates the app can run. Phase 1 ships the bundled copy only;
/// a later phase fetches and caches a newer one (FR-A6) and falls back to this.
public struct TemplateLibrary: Sendable {
    public let version: Int
    private let byID: [String: PromptTemplate]

    public init(bundle: TemplateBundle) {
        version = bundle.version
        byID = Dictionary(bundle.templates.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    public init(jsonData: Data) throws {
        self.init(bundle: try JSONDecoder().decode(TemplateBundle.self, from: jsonData))
    }

    public func template(id: String) throws -> PromptTemplate {
        guard let template = byID[id] else { throw AnthropicError.unknownTemplate(id) }
        return template
    }

    public var templates: [PromptTemplate] { byID.values.sorted { $0.id < $1.id } }

    /// The copy shipped inside the app (`Resources/Templates.json`).
    public static let bundled: TemplateLibrary = {
        guard let url = Bundle.module.url(forResource: "Templates", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let library = try? TemplateLibrary(jsonData: data) else {
            preconditionFailure("Bundled Templates.json is missing or invalid")
        }
        return library
    }()
}

/// Template ids the app uses today.
public enum TemplateID {
    public static let textProcess = "text.process"
    public static let emailReply = "email.reply"
    public static let ask = "ask"
}

/// What to run: a template and its variables.
public struct TemplateRun: Equatable, Sendable {
    public let templateID: String
    public let variables: [String: String]
}
