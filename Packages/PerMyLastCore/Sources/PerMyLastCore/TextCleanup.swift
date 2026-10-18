import Foundation

public enum TextCleanup {
    /// Cleans text captured from other apps, pasted, or returned by the model:
    /// normalises line endings, drops a line that repeats the one before it,
    /// squeezes runs of blank lines down to one, and trims the ends. (Some apps,
    /// Microsoft Teams among them, put paragraph gaps on the clipboard that grow
    /// every time they're copied.)
    public static func beautify(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var kept: [String] = []
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if i > 0, !trimmed.isEmpty, trimmed == lines[i - 1].trimmingCharacters(in: .whitespaces) { continue }
            kept.append(line)
        }
        var result = kept.joined(separator: "\n")
        while result.contains("\n\n\n") { result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}
