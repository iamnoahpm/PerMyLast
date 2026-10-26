import Foundation
import Testing
@testable import PerMyLastCore

private final class FakeStreamTransport: HTTPStreamTransport, @unchecked Sendable {
    var status = 200
    var lines: [String] = []
    var error: Error?
    private(set) var lastRequest: URLRequest?

    func lines(for request: URLRequest) async throws -> (statusCode: Int, lines: AsyncThrowingStream<String, Error>) {
        lastRequest = request
        if let error { throw error }
        let lines = self.lines
        return (status, AsyncThrowingStream { c in
            for line in lines { c.yield(line) }
            c.finish()
        })
    }
}

private func sse(_ text: String) -> [String] {
    ["event: content_block_delta",
     #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"\#(text)"}}"#]
}

private func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> [String] {
    var out: [String] = []
    for try await delta in stream { out.append(delta) }
    return out
}

private func body(_ request: URLRequest?) throws -> [String: Any] {
    let data = try #require(request?.httpBody)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Suite("Templates")
struct TemplateTests {
    @Test func bundledTemplatesLoad() throws {
        let lib = TemplateLibrary.bundled
        #expect(lib.templates.map(\.id) == ["ask", "email.reply", "text.process"])
        #expect(lib.version == 2)
    }

    /// The system prompts live in Templates.json; PromptBuilder still builds the same
    /// text for the non-streaming client. They must not drift apart.
    @Test func bundledSystemPromptsMatchPromptBuilder() throws {
        let lib = TemplateLibrary.bundled
        #expect(try lib.template(id: TemplateID.textProcess).system == PromptBuilder.buildRequest(text: "x", prompt: "y", isEmail: false).system)
        #expect(try lib.template(id: TemplateID.emailReply).system == PromptBuilder.buildRequest(text: "x", prompt: "y", isEmail: true).system)
        #expect(try lib.template(id: TemplateID.ask).system == PromptBuilder.buildAskRequest(prompt: "y", input: "").system)
        #expect(try lib.template(id: TemplateID.textProcess).maxTokens == AnthropicClient.maxTokens)
        #expect(try lib.template(id: TemplateID.ask).maxTokens == AnthropicClient.askMaxTokens)
    }

    @Test func templateRunsPickTheRightTemplate() {
        #expect(PromptBuilder.templateRun(text: "t", prompt: "p", isEmail: false).templateID == TemplateID.textProcess)
        #expect(PromptBuilder.templateRun(text: "t", prompt: "p", isEmail: true).templateID == TemplateID.emailReply)
        // A full template prompt wins over the email flag, as in buildRequest.
        #expect(PromptBuilder.templateRun(text: "t", prompt: "a {original_message}", isEmail: true).templateID == TemplateID.textProcess)
        let run = PromptBuilder.templateRun(text: "hello", prompt: "Fix.", isEmail: false)
        #expect(run.variables == ["content": "Fix.\n\nText: hello"])
        #expect(PromptBuilder.askRun(prompt: "Why?", input: "").templateID == TemplateID.ask)
    }

    @Test func rendersInOnePass() throws {
        let t = try TemplateLibrary.bundled.template(id: TemplateID.textProcess)
        #expect(try t.render(["content": "a {{content}} b"]) == "a {{content}} b")
    }

    @Test func missingVariableAndUnknownTemplateAreErrors() throws {
        let t = try TemplateLibrary.bundled.template(id: TemplateID.textProcess)
        #expect(throws: AnthropicError.missingVariable("content")) { _ = try t.render([:]) }
        #expect(throws: AnthropicError.unknownTemplate("nope")) { _ = try TemplateLibrary.bundled.template(id: "nope") }
    }
}

@Suite("DirectAnthropicClient")
struct DirectAnthropicClientTests {
    let config = AnthropicConfig(apiKey: "sk-test", model: "claude-sonnet-5", effort: .low)

    @Test func streamsDeltasFromAnthropicWithTheUsersKey() async throws {
        let transport = FakeStreamTransport()
        transport.lines = ["event: message_start", #"data: {"type":"message_start"}"#, ""]
            + sse("Hel") + [#"data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"hm"}}"#]
            + sse("lo") + [#"data: {"type":"message_stop"}"#]
        let client = DirectAnthropicClient(config: config, transport: transport)
        let out = try await collect(client.run(templateID: TemplateID.textProcess, variables: ["content": "Fix.\n\nText: hi"]))
        #expect(out == ["Hel", "lo"])

        let request = try #require(transport.lastRequest)
        #expect(request.url?.host == "api.anthropic.com")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        let b = try body(request)
        #expect(b["stream"] as? Bool == true)
        #expect(b["model"] as? String == "claude-sonnet-5")   // the user's model, not the template's
        #expect(b["max_tokens"] as? Int == 4096)
        #expect((b["messages"] as? [[String: String]]) == [["role": "user", "content": "Fix.\n\nText: hi"]])
    }

    @Test func askUsesItsTemplateLimits() async throws {
        let transport = FakeStreamTransport()
        transport.lines = sse("ok")
        _ = try await collect(DirectAnthropicClient(config: config, transport: transport)
            .run(templateID: TemplateID.ask, variables: ["content": "Why?"]))
        let b = try body(transport.lastRequest)
        #expect(b["max_tokens"] as? Int == 8192)
        #expect((b["system"] as? String)?.contains("helpful assistant") == true)
    }

    @Test func missingKeyFailsBeforeAnyRequest() async {
        let transport = FakeStreamTransport()
        let client = DirectAnthropicClient(config: AnthropicConfig(apiKey: ""), transport: transport)
        await #expect(throws: AnthropicError.missingAPIKey) {
            _ = try await collect(client.run(templateID: TemplateID.ask, variables: ["content": "x"]))
        }
        #expect(transport.lastRequest == nil)
    }

    @Test func surfacesTheAPIErrorForABadStatus() async {
        let transport = FakeStreamTransport()
        transport.status = 401
        transport.lines = [#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#]
        await #expect(throws: AnthropicError.api("invalid x-api-key")) {
            _ = try await collect(DirectAnthropicClient(config: config, transport: transport)
                .run(templateID: TemplateID.ask, variables: ["content": "x"]))
        }
    }

    @Test func surfacesAnErrorEventMidStream() async {
        let transport = FakeStreamTransport()
        transport.lines = sse("par") + [#"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#]
        await #expect(throws: AnthropicError.api("Overloaded")) {
            _ = try await collect(DirectAnthropicClient(config: config, transport: transport)
                .run(templateID: TemplateID.ask, variables: ["content": "x"]))
        }
    }

    @Test func emptyStreamIsAnError() async {
        let transport = FakeStreamTransport()
        transport.lines = [#"data: {"type":"message_stop"}"#]
        do {
            _ = try await collect(DirectAnthropicClient(config: config, transport: transport)
                .run(templateID: TemplateID.ask, variables: ["content": "x"]))
            Issue.record("expected an error")
        } catch AnthropicError.emptyResponse {
        } catch { Issue.record("wrong error: \(error)") }
    }

    @Test func networkFailureIsATransportError() async {
        let transport = FakeStreamTransport()
        transport.error = URLError(.notConnectedToInternet)
        do {
            _ = try await collect(DirectAnthropicClient(config: config, transport: transport)
                .run(templateID: TemplateID.ask, variables: ["content": "x"]))
            Issue.record("expected an error")
        } catch AnthropicError.transport {
        } catch { Issue.record("wrong error: \(error)") }
    }

    @Test func unknownTemplateIsReported() async {
        await #expect(throws: AnthropicError.unknownTemplate("nope")) {
            _ = try await collect(DirectAnthropicClient(config: config, transport: FakeStreamTransport())
                .run(templateID: "nope", variables: [:]))
        }
    }
}

private final class FakeTransport: HTTPTransport, @unchecked Sendable {
    var status = 200
    var body = Data()
    private(set) var lastRequest: URLRequest?
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@Suite("Test key")
struct KeyTestTests {
    @Test func validKeyPasses() async throws {
        let t = FakeTransport()
        t.body = Data(#"{"content":[{"type":"text","text":"Hi"}]}"#.utf8)
        try await AnthropicClient(transport: t).testKey(apiKey: "sk-ant-good")
        let b = try body(t.lastRequest)
        #expect(b["max_tokens"] as? Int == 1)
        #expect(b["model"] as? String == AnthropicClient.keyTestModel)
        #expect(t.lastRequest?.value(forHTTPHeaderField: "x-api-key") == "sk-ant-good")
    }

    @Test func invalidKeyShowsTheAPIMessage() async {
        let t = FakeTransport()
        t.status = 401
        t.body = Data(#"{"error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8)
        await #expect(throws: AnthropicError.api("invalid x-api-key")) {
            try await AnthropicClient(transport: t).testKey(apiKey: "sk-ant-bad")
        }
    }

    @Test func noCreditAndRateLimitMessagesComeThrough() async {
        for (status, message) in [(400, "Your credit balance is too low"), (429, "rate limit exceeded")] {
            let t = FakeTransport()
            t.status = status
            t.body = Data(#"{"error":{"message":"\#(message)"}}"#.utf8)
            await #expect(throws: AnthropicError.api(message)) {
                try await AnthropicClient(transport: t).testKey(apiKey: "sk-ant-x")
            }
        }
    }
}

private struct FailingStore: APIKeyStore {
    var failLoad = false, failSave = false
    func load() throws -> String? { if failLoad { throw KeychainError(status: -25293) }; return nil }
    func save(_ key: String) throws { if failSave { throw KeychainError(status: -25308) } }
    func delete() throws {}
}

@Suite("API key storage")
struct APIKeyStoreTests {
    @Test func migratesTheLegacyKeyOnceAndClearsTheOldCopy() throws {
        let store = InMemoryAPIKeyStore()
        var cleared = 0
        let r = APIKeyMigration.migrate(legacy: " sk-ant-old \n", store: store, clearLegacy: { cleared += 1 })
        #expect(r.key == "sk-ant-old" && r.error == nil && cleared == 1)
        #expect(try store.load() == "sk-ant-old")
    }

    @Test func keychainCopyWinsAndLeftoverLegacyIsCleared() throws {
        let store = InMemoryAPIKeyStore(key: "sk-ant-new")
        var cleared = 0
        let r = APIKeyMigration.migrate(legacy: "sk-ant-old", store: store, clearLegacy: { cleared += 1 })
        #expect(r.key == "sk-ant-new" && cleared == 1)
    }

    @Test func nothingToMigrate() {
        var cleared = 0
        let r = APIKeyMigration.migrate(legacy: nil, store: InMemoryAPIKeyStore(), clearLegacy: { cleared += 1 })
        #expect(r.key == "" && r.error == nil && cleared == 0)
    }

    @Test func aFailedSaveKeepsTheOldKeyWorkingAndTheLegacyCopy() {
        var cleared = 0
        let r = APIKeyMigration.migrate(legacy: "sk-ant-old", store: FailingStore(failSave: true), clearLegacy: { cleared += 1 })
        #expect(r.key == "sk-ant-old" && r.error != nil && cleared == 0)
    }

    @Test func anUnreadableKeychainKeepsTheLegacyCopy() {
        var cleared = 0
        let r = APIKeyMigration.migrate(legacy: "sk-ant-old", store: FailingStore(failLoad: true), clearLegacy: { cleared += 1 })
        #expect(r.key == "sk-ant-old" && r.error != nil && cleared == 0)
    }

    @Test func keychainRoundTrip() throws {
        let store = KeychainAPIKeyStore(service: "app.permylast.tests.\(UUID().uuidString)")
        defer { try? store.delete() }
        #expect(try store.load() == nil)
        try store.save("sk-ant-one")
        #expect(try store.load() == "sk-ant-one")
        try store.save("sk-ant-two")
        #expect(try store.load() == "sk-ant-two")
        try store.delete()
        #expect(try store.load() == nil)
    }
}
