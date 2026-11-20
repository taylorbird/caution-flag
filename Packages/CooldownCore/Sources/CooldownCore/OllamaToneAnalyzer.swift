import Foundation

/// Guarantees draft text only ever goes to this machine.
public enum LoopbackGuard {
    public static func isLoopback(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased()
        else { return false }
        let trimmed = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return trimmed == "localhost" || trimmed == "::1" || trimmed.hasPrefix("127.")
    }
}

/// Talks to a local Ollama server (`ollama serve`) using structured JSON output.
public struct OllamaToneAnalyzer: ToneAnalyzer {
    public static let defaultURL = URL(string: "http://127.0.0.1:11434")!
    public static let defaultModel = "llama3.2:3b"

    public let baseURL: URL
    public let model: String
    private let session: URLSession

    public var displayName: String { "Ollama · \(model)" }

    public init(baseURL: URL = defaultURL, model: String = defaultModel, session: URLSession = .shared) throws {
        guard LoopbackGuard.isLoopback(baseURL) else {
            throw ToneAnalyzerError.notLoopback(baseURL.host ?? baseURL.absoluteString)
        }
        self.baseURL = baseURL
        self.model = model
        self.session = session
    }

    public func analyze(_ text: String) async throws -> ToneResult {
        let request = try makeRequest(for: text)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ToneAnalyzerError.badResponse("no HTTP response") }
        guard http.statusCode == 200 else {
            if http.statusCode == 404 {
                throw ToneAnalyzerError.unavailable("model \(model) isn't pulled (try `ollama pull \(model)`)")
            }
            throw ToneAnalyzerError.badResponse("HTTP \(http.statusCode)")
        }
        let content = try Self.decodeEnvelope(data)
        do {
            return try ToneResponseParser.parse(content)
        } catch {
            throw ToneAnalyzerError.badResponse("unparseable model output")
        }
    }

    public func suggestRewrite(_ text: String) async throws -> String? {
        var request = try makeRequest(for: text)
        var body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        body.removeValue(forKey: "format")
        body["options"] = ["temperature": 0.4, "num_predict": 300]
        body["messages"] = [
            ["role": "system", "content": TonePrompt.rewriteInstructions],
            ["role": "user", "content": TonePrompt.userPrompt(for: text)],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ToneAnalyzerError.badResponse("rewrite failed") }
        return TonePrompt.cleanRewrite(try Self.decodeEnvelope(data))
    }

    public func explain(_ text: String, assessment: ToneAssessment) async throws -> ToneExplanation {
        var request = try makeRequest(for: text)
        guard let requestBody = request.httpBody,
              var body = try JSONSerialization.jsonObject(with: requestBody) as? [String: Any]
        else { throw ToneAnalyzerError.badResponse("couldn't build the explain request") }
        body["format"] = TonePrompt.explainSchema
        body["options"] = ["temperature": 0.3, "num_predict": 250]
        body["messages"] = [
            ["role": "system", "content": TonePrompt.explainInstructions],
            ["role": "user", "content": TonePrompt.explainPrompt(for: text, assessment: assessment)],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ToneAnalyzerError.badResponse("explain failed") }
        do {
            return try ToneResponseParser.parseExplanation(try Self.decodeEnvelope(data), draft: text)
        } catch let error as ToneAnalyzerError {
            throw error
        } catch {
            throw ToneAnalyzerError.badResponse("unparseable explanation")
        }
    }

    public func makeRequest(for text: String) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "keep_alive": "30m",
            "format": TonePrompt.jsonSchema,
            "options": ["temperature": 0.2, "num_predict": 150],
            "messages": [
                ["role": "system", "content": TonePrompt.instructions],
                ["role": "user", "content": TonePrompt.userPrompt(for: text)],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Pulls `message.content` out of an `/api/chat` response.
    public static func decodeEnvelope(_ data: Data) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ToneAnalyzerError.badResponse("not JSON")
        }
        if let error = object["error"] as? String { throw ToneAnalyzerError.badResponse(error) }
        guard let message = object["message"] as? [String: Any], let content = message["content"] as? String else {
            throw ToneAnalyzerError.badResponse("missing message.content")
        }
        return content
    }

    /// Lists installed models; used by Settings to check the connection.
    public func installedModels() async throws -> [String] {
        let (data, _) = try await session.data(from: baseURL.appendingPathComponent("api/tags"))
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = object["models"] as? [[String: Any]]
        else { throw ToneAnalyzerError.badResponse("unexpected /api/tags payload") }
        return models.compactMap { $0["name"] as? String }
    }
}
