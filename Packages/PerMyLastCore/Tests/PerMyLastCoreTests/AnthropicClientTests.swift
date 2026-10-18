import Foundation
import Testing
@testable import PerMyLastCore

private final class FakeTransport: HTTPTransport, @unchecked Sendable {
    var status = 200
    var body = Data()
    var error: Error?
    private(set) var lastRequest: URLRequest?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        if let error { throw error }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (body, response)
    }
}

private func json(_ object: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: object)
}

private func requestBody(_ request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Suite("AnthropicClient")
struct AnthropicClientTests {
    let config = AnthropicConfig(apiKey: "sk-test", model: "claude-sonnet-5", effort: .high)

    @Test func buildsTheRequest() throws {
        let client = AnthropicClient(transport: FakeTransport())
        let request = try client.makeRequest(config: config, text: "hello", prompt: "Fix grammar.", isEmail: false)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "anthropic-workspace-id") == nil)

        let body = try requestBody(request)
        #expect(body["model"] as? String == "claude-sonnet-5")
        #expect(body["max_tokens"] as? Int == 1024)
        #expect((body["output_config"] as? [String: String])?["effort"] == "high")
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages == [["role": "user", "content": "Fix grammar.\n\nText: hello"]])
    }

    @Test func writeMyWayChoicesReachTheRequestThatIsActuallySent() throws {
        var wmw = WriteMyWaySettings()
        wmw.enabled = true; wmw.englishLevelEnabled = true; wmw.testType = "TOEIC"; wmw.testScore = "850"
        wmw.tone = "friendly"; wmw.length = "custom"; wmw.customLength = "40"; wmw.format = "message"
        let like = try #require(PresetLibrary.defaultPresets.first { $0.label == "Like Me" })
        let prompt = PromptBuilder.finalPrompt(preset: like, motherLanguage: "", intent: nil, tabTakesIntent: false, writeMyWay: wmw)

        let request = try AnthropicClient().makeRequest(config: config, text: "hey can u join the call at 3", prompt: prompt, isEmail: like.isEmail)
        let body = try requestBody(request)
        let content = try #require((body["messages"] as? [[String: String]])?.first?["content"])
        #expect(content.hasPrefix(PresetLibrary.likeMePrompt))
        #expect(content.contains("- Tone: friendly."))
        #expect(content.contains("- Length: no more than 40 words."))
        #expect(content.contains("- Format: a chat message (Teams or Slack style)."))
        #expect(content.contains("English level: the writer's English is around TOEIC 850"))
        #expect(content.hasSuffix("Text: hey can u join the call at 3"))   // the user's text still comes last
    }

    @Test func askUsesItsOwnSystemPromptAndAHigherTokenLimit() async throws {
        let transport = FakeTransport()
        transport.body = json(["content": [["type": "text", "text": "A monad is..."]]])
        let out = try await AnthropicClient(transport: transport).ask(config: config, prompt: "What is a monad?", input: "")
        #expect(out == "A monad is...")
        let body = try requestBody(try #require(transport.lastRequest))
        #expect(body["max_tokens"] as? Int == AnthropicClient.askMaxTokens)
        #expect((body["system"] as? String)?.contains("helpful assistant") == true)
        #expect((body["messages"] as? [[String: String]]) == [["role": "user", "content": "What is a monad?"]])
    }

    @Test func sendsWorkspaceHeaderWhenSet() throws {
        var c = config
        c.workspaceId = "wrkspc_123"
        let request = try AnthropicClient().makeRequest(config: c, text: "x", prompt: "y", isEmail: false)
        #expect(request.value(forHTTPHeaderField: "anthropic-workspace-id") == "wrkspc_123")
    }

    @Test func omitsEffortForHaiku() throws {
        var c = config
        c.model = "claude-haiku-4-5"
        let request = try AnthropicClient().makeRequest(config: c, text: "x", prompt: "y", isEmail: false)
        let body = try requestBody(request)
        #expect(body["output_config"] == nil)
    }

    @Test func refusesToSendWithoutAKey() async {
        let client = AnthropicClient(transport: FakeTransport())
        await #expect(throws: AnthropicError.missingAPIKey) {
            _ = try await client.process(config: AnthropicConfig(apiKey: ""), text: "x", prompt: "y", isEmail: false)
        }
    }

    @Test func returnsTheFirstNonEmptyTextBlock() async throws {
        let transport = FakeTransport()
        transport.body = json(["content": [["type": "thinking", "thinking": "..."], ["type": "text", "text": ""], ["type": "text", "text": "Fixed."]]])
        let out = try await AnthropicClient(transport: transport).process(config: config, text: "x", prompt: "y", isEmail: false)
        #expect(out == "Fixed.")
    }

    @Test func surfacesTheAPIErrorMessage() async {
        let transport = FakeTransport()
        transport.status = 401
        transport.body = json(["error": ["type": "authentication_error", "message": "invalid x-api-key"]])
        await #expect(throws: AnthropicError.api("invalid x-api-key")) {
            _ = try await AnthropicClient(transport: transport).process(config: config, text: "x", prompt: "y", isEmail: false)
        }
    }

    @Test func fallsBackToStatusCodeWhenErrorBodyIsUnparseable() async {
        let transport = FakeTransport()
        transport.status = 529
        transport.body = Data("<html>overloaded</html>".utf8)
        await #expect(throws: AnthropicError.api("API Error: 529")) {
            _ = try await AnthropicClient(transport: transport).process(config: config, text: "x", prompt: "y", isEmail: false)
        }
    }

    @Test func reportsAnEmptyResponse() async {
        let transport = FakeTransport()
        transport.body = json(["content": [["type": "text", "text": ""]]])
        do {
            _ = try await AnthropicClient(transport: transport).process(config: config, text: "x", prompt: "y", isEmail: false)
            Issue.record("expected an error")
        } catch let AnthropicError.emptyResponse(detail) {
            #expect(detail.contains("content"))
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test func wrapsNetworkFailures() async {
        let transport = FakeTransport()
        transport.error = URLError(.notConnectedToInternet)
        do {
            _ = try await AnthropicClient(transport: transport).process(config: config, text: "x", prompt: "y", isEmail: false)
            Issue.record("expected an error")
        } catch AnthropicError.transport {
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }
}
