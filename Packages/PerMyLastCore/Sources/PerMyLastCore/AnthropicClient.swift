import Foundation

public struct AnthropicConfig: Sendable {
    public var apiKey: String
    public var model: String
    public var effort: Effort
    /// Identity-linked API keys need this header naming the workspace.
    public var workspaceId: String?

    public init(apiKey: String, model: String = ModelCatalog.defaultModel,
                effort: Effort = ModelCatalog.defaultEffort, workspaceId: String? = nil) {
        self.apiKey = apiKey
        self.model = model
        self.effort = effort
        self.workspaceId = workspaceId
    }
}

public enum AnthropicError: Error, LocalizedError, Equatable {
    case missingAPIKey
    case api(String)
    case emptyResponse(String)
    case transport(String)
    case unknownTemplate(String)
    case missingVariable(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "API key not set. Open Settings to add one."
        case .api(let message): return message
        case .emptyResponse(let detail): return "No text in response: \(detail)"
        case .transport(let message): return message
        case .unknownTemplate(let id): return "Unknown prompt template: \(id)"
        case .missingVariable(let name): return "The prompt template needs a value for \"\(name)\"."
        }
    }
}

/// Seam for tests; the real one is a URLSession (which, unlike Node's fetch,
/// uses the system trust store, so TLS-inspecting corporate proxies work).
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

public struct AnthropicClient: Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let apiVersion = "2023-06-01"
    public static let maxTokens = 4096
    /// Free-form answers can be long; the preset actions stay short.
    public static let askMaxTokens = 8192

    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func makeRequest(config: AnthropicConfig, text: String, prompt: String, isEmail: Bool) throws -> URLRequest {
        try makeRequest(config: config, content: PromptBuilder.buildRequest(text: text, prompt: prompt, isEmail: isEmail),
                        maxTokens: Self.maxTokens)
    }

    /// Plain text, or image blocks followed by the text when screenshots are attached.
    static func userContent(_ built: ClaudeRequestContent) -> Any {
        guard !built.images.isEmpty else { return built.content }
        var blocks: [[String: Any]] = built.images.map {
            ["type": "image", "source": ["type": "base64", "media_type": $0.mediaType, "data": $0.data.base64EncodedString()]]
        }
        blocks.append(["type": "text", "text": built.content])
        return blocks
    }

    public func makeRequest(config: AnthropicConfig, content built: ClaudeRequestContent, maxTokens: Int,
                            stream: Bool = false) throws -> URLRequest {
        guard !config.apiKey.isEmpty else { throw AnthropicError.missingAPIKey }

        var body: [String: Any] = [
            "model": config.model,
            "max_tokens": maxTokens,
            "system": built.system,
            "messages": [["role": "user", "content": Self.userContent(built)]]
        ]
        if stream { body["stream"] = true }
        // Sonnet 5 / Opus 5 / Fable 5 think adaptively; effort only tunes how
        // much. Haiku 4.5 rejects the parameter.
        if ModelCatalog.supportsEffort(config.model) {
            body["output_config"] = ["effort": config.effort.rawValue]
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        if let workspaceId = config.workspaceId, !workspaceId.isEmpty {
            request.setValue(workspaceId, forHTTPHeaderField: "anthropic-workspace-id")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    /// Sends the text through the chosen prompt and returns the model's reply.
    public func process(config: AnthropicConfig, text: String, prompt: String, isEmail: Bool) async throws -> String {
        try await send(try makeRequest(config: config, text: text, prompt: prompt, isEmail: isEmail))
    }

    /// The Ask tab: the user's own prompt and (optionally) their text, no preset.
    public func ask(config: AnthropicConfig, prompt: String, input: String) async throws -> String {
        let content = PromptBuilder.buildAskRequest(prompt: prompt, input: input)
        return try await send(try makeRequest(config: config, content: content, maxTokens: Self.askMaxTokens))
    }

    /// Model used for "Test key": cheap, and it takes no effort parameter.
    public static let keyTestModel = "claude-haiku-4-5"

    /// Sends a one-token request to check that a key works (FR-A11). Throws the
    /// API's own message (invalid key, no credit, rate limit) when it doesn't.
    public func testKey(apiKey: String, workspaceId: String? = nil) async throws {
        let config = AnthropicConfig(apiKey: apiKey, model: Self.keyTestModel, workspaceId: workspaceId)
        let request = try makeRequest(config: config, content: ClaudeRequestContent(system: "Reply with one word.", content: "Hi"), maxTokens: 1)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            throw AnthropicError.transport(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            _ = try Self.parseResponse(data: data, statusCode: status)
            throw AnthropicError.api("API Error: \(status)")
        }
    }

    private func send(_ request: URLRequest) async throws -> String {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            throw AnthropicError.transport(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return try Self.parseResponse(data: data, statusCode: status)
    }

    public static func parseResponse(data: Data, statusCode: Int) throws -> String {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(statusCode) else {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "API Error: \(statusCode)"
            throw AnthropicError.api(message)
        }
        let blocks = json?["content"] as? [[String: Any]] ?? []
        for block in blocks where block["type"] as? String == "text" {
            if let text = block["text"] as? String, !text.isEmpty { return text }
        }
        throw AnthropicError.emptyResponse(String((String(data: data, encoding: .utf8) ?? "").prefix(300)))
    }
}
