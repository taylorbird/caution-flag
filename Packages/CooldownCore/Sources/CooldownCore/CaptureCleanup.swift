import Foundation

/// Removes text that isn't the user's words but rides along in a composer's
/// accessibility value, such as the hidden label on a mention chip's remove button.
/// Without this, the model reads (and quotes) UI labels as if the user typed them.
public enum CaptureCleanup {
    /// Accessibility labels seen inside composer values. Matched case-insensitively.
    /// Only phrases nobody would type themselves: "remove link" alone could be a real request.
    public static let labels: [String] = [
        "Remove mention link",
    ]

    public static func clean(_ raw: String) -> String {
        var text = raw
        var changed = false
        for label in labels where text.range(of: label, options: .caseInsensitive) != nil {
            text = text.replacingOccurrences(of: label, with: "", options: .caseInsensitive)
            changed = true
        }
        guard changed else { return raw }
        // Collapse the gaps the labels leave behind, line by line, keeping line breaks.
        return text
            .components(separatedBy: "\n")
            .map { $0.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ") }
            .joined(separator: "\n")
    }
}
