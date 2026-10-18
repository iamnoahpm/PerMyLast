import Testing
@testable import PerMyLastCore

@Suite("TextCleanup")
struct TextCleanupTests {
    @Test func collapsesRunsOfBlankLines() {
        #expect(TextCleanup.beautify("a\n\n\n\n\nb") == "a\n\nb")
    }

    @Test func dropsAnImmediatelyRepeatedLine() {
        #expect(TextCleanup.beautify("Hello\nHello\nWorld") == "Hello\nWorld")
        #expect(TextCleanup.beautify("Hello\n  Hello  \nWorld") == "Hello\nWorld")
    }

    @Test func keepsIntentionalBlankLinesAndNonAdjacentRepeats() {
        #expect(TextCleanup.beautify("a\n\na\n\nb") == "a\n\na\n\nb")
        #expect(TextCleanup.beautify("a\nb\na") == "a\nb\na")
    }

    @Test func normalisesLineEndingsAndTrims() {
        #expect(TextCleanup.beautify("  \r\nline one\r\nline two\r\n\r\n") == "line one\nline two")
        #expect(TextCleanup.beautify("a\rb") == "a\nb")
    }

    @Test func emptyStaysEmpty() {
        #expect(TextCleanup.beautify("") == "")
        #expect(TextCleanup.wordCount("  two   words\nhere ") == 3)
    }
}
