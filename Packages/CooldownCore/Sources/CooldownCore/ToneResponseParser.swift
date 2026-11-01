import Foundation

public enum ToneParseError: Error, Equatable {
    case noJSON
    case invalidJSON
    case missingHeat
}

/// Turns loosely-structured model output into a `ToneResult`.
/// Small local models wrap JSON in prose or code fences, stringify numbers, and
/// invent category spellings; this tolerates all of that.
public enum ToneResponseParser {
    public static func parse(_ raw: String) throws -> ToneResult {
        guard let json = extractJSONObject(from: raw) else { throw ToneParseError.noJSON }
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ToneParseError.invalidJSON }
        return try parse(object: object)
    }

    public static func parse(object: [String: Any]) throws -> ToneResult {
        let lowered = Dictionary(object.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })

        guard let heat = firstValue(in: lowered, keys: ["heat", "heat_score", "heatscore", "score"]).flatMap(number(from:))
        else { throw ToneParseError.missingHeat }
        let clamped = min(10, max(0, heat))

        let categoryRaw = firstValue(in: lowered, keys: ["category", "tone", "label"]) as? String
        let category = categoryRaw.flatMap(ToneCategory.normalize) ?? (clamped < HeatLevel.warmThreshold ? .calm : .frustrated)

        let reason = (firstValue(in: lowered, keys: ["reason", "explanation", "why"]) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var rewrite = (firstValue(in: lowered, keys: ["rewrite", "calmer_rewrite", "calmerrewrite", "suggested_rewrite", "suggestion"]) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = rewrite, r.isEmpty || ["none", "n/a", "na", "null", "-"].contains(r.lowercased()) {
            rewrite = nil
        }

        return ToneResult(heat: clamped, category: category, reason: reason, rewrite: rewrite)
    }

    // MARK: - Helpers

    private static func firstValue(in dict: [String: Any], keys: [String]) -> Any? {
        for key in keys {
            if let value = dict[key], !(value is NSNull) { return value }
        }
        return nil
    }

    static func number(from value: Any) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String {
            // Accept "7", "7.5", "7/10", "heat 7".
            let scanner = Scanner(string: s)
            scanner.charactersToBeSkipped = CharacterSet.decimalDigits.union(["."]).inverted
            return scanner.scanDouble()
        }
        return nil
    }

    /// Finds the first balanced `{ ... }` block, ignoring braces inside strings.
    static func extractJSONObject(from raw: String) -> String? {
        let chars = Array(raw)
        guard let start = chars.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        for i in start..<chars.count {
            let c = chars[i]
            if inString {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
                continue
            }
            switch c {
            case "\"": inString = true
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(chars[start...i]) }
            default: break
            }
        }
        return nil
    }
}
