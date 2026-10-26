import Foundation

/// The one door every AI feature goes through (FR-A1). Streams text deltas.
public protocol AIClient: Sendable {
    func run(templateID: String, variables: [String: String]) -> AsyncThrowingStream<String, Error>
    /// Same, with screenshots attached. Only the direct client can send them for now.
    func run(templateID: String, variables: [String: String], images: [ClaudeImage]) -> AsyncThrowingStream<String, Error>
}

public extension AIClient {
    func run(templateID: String, variables: [String: String], images: [ClaudeImage]) -> AsyncThrowingStream<String, Error> {
        guard images.isEmpty else {
            return AsyncThrowingStream { $0.finish(throwing: AnthropicError.api("Screenshots need your own Anthropic API key for now. Add it in Settings.")) }
        }
        return run(templateID: templateID, variables: variables)
    }
}

/// Seam for tests; yields the response body line by line as it arrives.
public protocol HTTPStreamTransport: Sendable {
    func lines(for request: URLRequest) async throws -> (statusCode: Int, lines: AsyncThrowingStream<String, Error>)
}

public struct URLSessionStreamTransport: HTTPStreamTransport {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func lines(for request: URLRequest) async throws -> (statusCode: Int, lines: AsyncThrowingStream<String, Error>) {
        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let stream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines { continuation.yield(line) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return (status, stream)
    }
}

/// BYOK: renders the template locally and streams straight from api.anthropic.com
/// with the user's own key (FR-A2). Nothing goes through our servers.
public struct DirectAnthropicClient: AIClient {
    private let config: AnthropicConfig
    private let templates: TemplateLibrary
    private let transport: any HTTPStreamTransport

    public init(config: AnthropicConfig, templates: TemplateLibrary = .bundled,
                transport: any HTTPStreamTransport = URLSessionStreamTransport()) {
        self.config = config
        self.templates = templates
        self.transport = transport
    }

    public func run(templateID: String, variables: [String: String]) -> AsyncThrowingStream<String, Error> {
        run(templateID: templateID, variables: variables, images: [])
    }

    public func run(templateID: String, variables: [String: String], images: [ClaudeImage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let template = try templates.template(id: templateID)
                    let content = ClaudeRequestContent(system: template.system, content: try template.render(variables), images: images)
                    let request = try AnthropicClient().makeRequest(
                        config: config, content: content, maxTokens: template.maxTokens, stream: true)
                    try await stream(request, into: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func stream(_ request: URLRequest, into continuation: AsyncThrowingStream<String, Error>.Continuation) async throws {
        let status: Int
        let lines: AsyncThrowingStream<String, Error>
        do {
            (status, lines) = try await transport.lines(for: request)
        } catch {
            throw AnthropicError.transport(error.localizedDescription)
        }

        guard (200..<300).contains(status) else {
            var body = ""
            for try await line in lines { body += line }
            _ = try AnthropicClient.parseResponse(data: Data(body.utf8), statusCode: status)
            throw AnthropicError.api("API Error: \(status)")
        }

        var gotText = false
        do {
            for try await line in lines {
                switch Self.parse(line) {
                case .text(let delta): gotText = true; continuation.yield(delta)
                case .error(let message): throw AnthropicError.api(message)
                case .ignore: break
                }
            }
        } catch let error as AnthropicError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AnthropicError.transport(error.localizedDescription)
        }
        if !gotText { throw AnthropicError.emptyResponse("the stream ended without any text") }
    }

    enum Event: Equatable { case text(String), error(String), ignore }

    /// One server-sent-events line. Only `data:` lines carry JSON; thinking
    /// deltas, pings and the rest are skipped.
    static func parse(_ line: String) -> Event {
        guard line.hasPrefix("data:") else { return .ignore }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let json = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any] else { return .ignore }
        switch json["type"] as? String {
        case "content_block_delta":
            let delta = json["delta"] as? [String: Any]
            if delta?["type"] as? String == "text_delta", let text = delta?["text"] as? String, !text.isEmpty {
                return .text(text)
            }
            return .ignore
        case "error":
            return .error(((json["error"] as? [String: Any])?["message"] as? String) ?? "The API reported an error.")
        default:
            return .ignore
        }
    }
}
