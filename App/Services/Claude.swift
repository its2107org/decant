import Foundation
import UIKit

enum ClaudeError: LocalizedError {
    case noKey
    case badKey
    case noCredit
    case busy
    case offline
    case dropped
    case unreadable
    case api(String)

    var errorDescription: String? {
        switch self {
        case .noKey: "Add your Claude key in Settings first."
        case .badKey: "Your Claude key isn't working. Check it in Settings."
        case .noCredit: "Your Claude account is out of credit. Top it up at platform.claude.com."
        case .busy: "Claude is busy right now. Try again in a moment."
        case .offline: "No internet connection."
        case .dropped: "The connection dropped before Claude finished. Try again, and stay in Decant until it's done."
        case .unreadable: "Couldn't make sense of the answer. Try again."
        case .api(let message): message
        }
    }
}

/// Talks to Claude directly from the phone with Ian's own key.
enum Claude {
    static let sonnet = "claude-sonnet-5-5"
    static let haiku = "claude-haiku-5-5"

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    // MARK: - Calls

    /// Asks for an answer in a fixed JSON shape and decodes it.
    static func structured<T: Decodable>(_ type: T.Type, model: String, system: String, content: [[String: Any]],
                                         schema: [String: Any], effort: String = "medium",
                                         maxTokens: Int = 8000) async throws -> T {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": content]],
            "output_config": [
                "effort": effort,
                "format": ["type": "json_schema", "schema": schema]
            ]
        ]
        let response = try await send(body)
        guard let data = text(of: response).data(using: .utf8) else { throw ClaudeError.unreadable }
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw ClaudeError.unreadable }
    }

    /// Lets Claude search the web, then decodes the JSON it ends its answer with.
    static func searchThenAnswer<T: Decodable>(_ type: T.Type, system: String, prompt: String,
                                               allowedDomains: [String]? = nil, maxSearches: Int = 5,
                                               effort: String = "low") async throws -> T {
        var tool: [String: Any] = [
            "type": "web_search_20260209",
            "name": "web_search",
            "max_uses": maxSearches,
            "user_location": [
                "type": "approximate",
                "city": "New York",
                "region": "New York",
                "country": "US",
                "timezone": "America/New_York"
            ]
        ]
        if let allowedDomains { tool["allowed_domains"] = allowedDomains }
        let body: [String: Any] = [
            "model": sonnet,
            "max_tokens": 16000,
            "system": system,
            "tools": [tool],
            "messages": [["role": "user", "content": prompt]],
            "output_config": ["effort": effort]
        ]
        let response = try await send(body)
        guard let data = lastJSONObject(in: text(of: response)) else { throw ClaudeError.unreadable }
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw ClaudeError.unreadable }
    }

    /// A tiny call to check a key works.
    static func checkKey() async throws {
        let body: [String: Any] = [
            "model": haiku,
            "max_tokens": 64,
            "messages": [["role": "user", "content": "Reply with the word ok."]],
            "output_config": ["effort": "low"]
        ]
        _ = try await send(body)
    }

    // MARK: - Plumbing

    /// Sends a request, carrying on if Claude pauses mid-search, and retrying once if it's busy.
    static func send(_ initialBody: [String: Any]) async throws -> [String: Any] {
        guard let key = KeyStore.claudeKey else { throw ClaudeError.noKey }
        // Ask iOS for extra time so a look-up can finish if Ian briefly switches apps.
        let background = await MainActor.run { UIApplication.shared.beginBackgroundTask(withName: "Claude") }
        defer { Task { @MainActor in UIApplication.shared.endBackgroundTask(background) } }
        var body = initialBody
        let model = body["model"] as? String ?? sonnet

        for _ in 0..<5 {
            let response = try await post(body, key: key)
            Spend.record(usage: response["usage"] as? [String: Any], model: model)
            guard (response["stop_reason"] as? String) == "pause_turn" else { return response }
            // Hand the unfinished turn straight back so the server picks up where it left off.
            var messages = body["messages"] as? [[String: Any]] ?? []
            messages.append(["role": "assistant", "content": response["content"] ?? []])
            body["messages"] = messages
        }
        throw ClaudeError.busy
    }

    private static func post(_ body: [String: Any], key: String, attempt: Int = 0) async throws -> [String: Any] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .dataNotAllowed:
                throw ClaudeError.offline
            case .networkConnectionLost, .timedOut, .cannotConnectToHost, .secureConnectionFailed:
                // A dropped connection (common on a phone moving between Wi-Fi and mobile data) isn't the
                // same as being offline; try again before giving up.
                guard attempt < 2 else { throw ClaudeError.dropped }
                try await Task.sleep(for: .seconds(2))
                return try await post(body, key: key, attempt: attempt + 1)
            default:
                throw error
            }
        }
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.dropped }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let message = ((json["error"] as? [String: Any])?["message"] as? String) ?? ""

        switch http.statusCode {
        case 200:
            return json
        case 401, 403:
            throw ClaudeError.badKey
        case 400 where message.localizedCaseInsensitiveContains("credit"):
            throw ClaudeError.noCredit
        case 429, 500...599:
            guard attempt < 2 else { throw ClaudeError.busy }
            try await Task.sleep(for: .seconds(Double(attempt + 1) * 3))
            return try await post(body, key: key, attempt: attempt + 1)
        default:
            throw ClaudeError.api(message.isEmpty ? "Claude returned an error (\(http.statusCode))." : message)
        }
    }

    static func text(of response: [String: Any]) -> String {
        let blocks = response["content"] as? [[String: Any]] ?? []
        return blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
    }

    /// The last complete {...} in a piece of text, skipping anything inside quoted strings.
    static func lastJSONObject(in text: String) -> Data? {
        let chars = Array(text)
        var end = chars.count - 1
        while end >= 0 {
            while end >= 0 && chars[end] != "}" { end -= 1 }
            guard end >= 0 else { return nil }
            // Walk forward from each "{" to find the one that closes exactly at `end`.
            var start = 0
            while start < end {
                if chars[start] == "{", let close = matchingBrace(chars, from: start), close == end {
                    let candidate = String(chars[start...end])
                    if let data = candidate.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil {
                        return data
                    }
                }
                start += 1
            }
            end -= 1
        }
        return nil
    }

    private static func matchingBrace(_ chars: [Character], from start: Int) -> Int? {
        var depth = 0
        var inString = false
        var escaped = false
        var i = start
        while i < chars.count {
            let c = chars[i]
            if inString {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
            } else if c == "\"" {
                inString = true
            } else if c == "{" {
                depth += 1
            } else if c == "}" {
                depth -= 1
                if depth == 0 { return i }
            }
            i += 1
        }
        return nil
    }
}

/// A running total of what Decant has spent on Claude this month, shown in Settings.
enum Spend {
    private static let defaults = UserDefaults.standard

    private static var monthKey: String {
        let c = Calendar.current.dateComponents([.year, .month], from: Date())
        return String(format: "spend-%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    static var thisMonth: Double { defaults.double(forKey: monthKey) }

    static func record(usage: [String: Any]?, model: String) {
        guard let usage else { return }
        let (inPrice, outPrice) = model == Claude.haiku ? (0.10, 0.50) : (2.0, 10.0)
        func n(_ key: String) -> Double { (usage[key] as? NSNumber)?.doubleValue ?? 0 }
        let input = n("input_tokens") + n("cache_creation_input_tokens") * 1.25 + n("cache_read_input_tokens") * 0.1
        let searches = ((usage["server_tool_use"] as? [String: Any])?["web_search_requests"] as? NSNumber)?.doubleValue ?? 0
        let dollars = input / 1_000_000 * inPrice + n("output_tokens") / 1_000_000 * outPrice + searches * 0.01
        defaults.set(thisMonth + dollars, forKey: monthKey)
    }
}
