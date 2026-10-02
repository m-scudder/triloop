import Foundation

#if DEBUG
struct CoachLocalLLMConfiguration: Equatable {
    let endpoint: URL
    let model: String

    static var current: CoachLocalLLMConfiguration? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ATHEVIA_COACH_LOCAL_ENABLED"] == "1" else {
            return nil
        }

        let endpointString = environment["ATHEVIA_COACH_LOCAL_URL"]
            ?? "http://127.0.0.1:11434/v1/chat/completions"
        guard let endpoint = URL(string: endpointString) else {
            return nil
        }

        let model = environment["ATHEVIA_COACH_LOCAL_MODEL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let model, !model.isEmpty else {
            return nil
        }

        return CoachLocalLLMConfiguration(
            endpoint: endpoint,
            model: model
        )
    }
}

struct CoachLocalLLMClient {
    private struct ChatMessage: Encodable {
        let role: String
        let content: String
    }

    private struct RequestBody: Encodable {
        let model: String
        let messages: [ChatMessage]
        let temperature: Double
        let stream: Bool
    }

    private struct ResponseBody: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String
            }

            let message: Message
        }

        let choices: [Choice]
    }

    let configuration: CoachLocalLLMConfiguration
    var session: URLSession = .shared
    var timeoutSeconds: TimeInterval = 60

    func respond(payloadJSON: String) async throws -> CoachLLMResponse {
        debugLog("Local model request started")
        debugLog("Endpoint: \(configuration.endpoint.absoluteString)")
        debugLog("Model: \(configuration.model)")
        debugLogBlock("System prompt", CoachSystemPrompt.instructions)
        debugLogBlock("Sanitized Coach payload", prettyPrintedJSON(payloadJSON) ?? payloadJSON)

        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = RequestBody(
            model: configuration.model,
            messages: [
                ChatMessage(role: "system", content: CoachSystemPrompt.instructions),
                ChatMessage(role: "user", content: payloadJSON)
            ],
            temperature: 0.2,
            stream: false
        )

        request.httpBody = try JSONEncoder().encode(body)

        let startedAt = Date()
        let (data, response) = try await session.data(for: request)
        let elapsed = Date().timeIntervalSince(startedAt)

        guard let httpResponse = response as? HTTPURLResponse else {
            debugLog("Local model response had no HTTP status")
            throw CoachLLMError.unavailable
        }

        debugLog("HTTP status: \(httpResponse.statusCode) in \(String(format: "%.2f", elapsed))s")
        debugLogBlock("Raw Ollama HTTP response", String(data: data, encoding: .utf8) ?? "<non-UTF8 response>")

        guard (200..<300).contains(httpResponse.statusCode) else {
            debugLog("Local model request rejected by server")
            throw CoachLLMError.unavailable
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let output = decoded.choices.first?.message.content,
              let outputData = output.data(using: .utf8) else {
            debugLog("Local model response contained no assistant content")
            throw CoachLLMError.invalidResponse
        }

        debugLogBlock("Assistant content", output)

        do {
            let validated = try CoachLLMResponseGuard.decodeAndValidate(outputData)
            debugLog("Local response accepted by CoachLLMResponseGuard")
            debugLog("Response kind: \(validated.kind.rawValue)")
            return validated
        } catch {
            debugLog("Local response rejected by CoachLLMResponseGuard: \(String(describing: error))")
            throw error
        }
    }

    private func debugLog(_ message: String) {
        print("[CoachAI][Local] \(message)")
    }

    private func debugLogBlock(_ title: String, _ value: String) {
        print("""
        [CoachAI][Local] ----- \(title) -----
        \(value)
        [CoachAI][Local] ----- End \(title) -----
        """)
    }

    private func prettyPrintedJSON(_ value: String) -> String? {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
              ) else {
            return nil
        }

        return String(data: prettyData, encoding: .utf8)
    }
}

#endif
