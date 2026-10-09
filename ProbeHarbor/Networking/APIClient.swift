import Foundation

enum APIError: LocalizedError, Equatable {
    case unauthorized
    case forbidden(String)
    case http(Int, String)
    case decoding(String)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Session expired — sign in again"
        case .forbidden(let message): return message
        case .http(let code, let body):
            let detail = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "HTTP \(code)" : "HTTP \(code): \(detail.prefix(200))"
        case .decoding(let detail): return "Unexpected response from ProbeHarbor (\(detail))"
        case .message(let message): return message
        }
    }
}

/// HTTP client for probeharbor.dev that carries the dashboard session as cookies,
/// like the web app and the Android app. Cookie handling is manual (no shared
/// cookie storage) so the Keychain session is the single source of truth.
final class APIClient: @unchecked Sendable {
    let config: AppConfig
    let sessionStore: SessionStoring
    private let session: URLSession
    private let noRedirectSession: URLSession
    private let decoder = JSONDecoder()

    /// Called when the server rejects the session (401 or a redirect to /signin).
    var onUnauthorized: (@Sendable () -> Void)?

    init(config: AppConfig = .current, sessionStore: SessionStoring) {
        self.config = config
        self.sessionStore = sessionStore
        let configuration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 35
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
        noRedirectSession = URLSession(
            configuration: configuration,
            delegate: NoRedirectDelegate(),
            delegateQueue: nil
        )
    }

    // MARK: Requests

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var request = URLRequest(url: url(path, query: query))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await send(request)
        try check(response, data: data)
        return try decode(data)
    }

    /// POST a JSON body. Returns the decoded response even for non-2xx when it
    /// decodes, so callers can surface the server's `error` field.
    func postJSON<T: Decodable>(
        _ path: String,
        body: [String: Any],
        method: String = "POST"
    ) async throws -> (T, Int) {
        var request = URLRequest(url: url(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await send(request)
        if response.statusCode == 401 {
            onUnauthorized?()
            throw APIError.unauthorized
        }
        if let decoded = try? decoder.decode(T.self, from: data) {
            return (decoded, response.statusCode)
        }
        try check(response, data: data)
        return (try decode(data), response.statusCode)
    }

    /// Form POST that answers with a redirect (dashboard settings writes).
    /// Returns the Location header on success.
    @discardableResult
    func postForm(_ path: String, fields: [(String, String)], successHints: [String]) async throws -> String {
        var request = URLRequest(url: url(path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(fields).data(using: .utf8)
        let (_, response) = try await send(request, followRedirects: false)
        let location = response.value(forHTTPHeaderField: "Location") ?? ""
        switch FormRedirect.evaluate(status: response.statusCode, location: location, successHints: successHints) {
        case .success(let location):
            return location
        case .failure(let error):
            if error == .unauthorized { onUnauthorized?() }
            throw error
        }
    }

    /// Raw bytes (claims pack HTML).
    func data(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        let (data, response) = try await send(URLRequest(url: url(path, query: query)))
        if response.statusCode == 403 { throw APIError.forbidden("Pro plan required") }
        try check(response, data: data)
        return data
    }

    // MARK: Plumbing

    private func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: config.url(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    private func send(_ request: URLRequest, followRedirects: Bool = true) async throws -> (Data, HTTPURLResponse) {
        var request = request
        if let tokens = sessionStore.load() {
            request.setValue(SessionCookies.header(for: tokens), forHTTPHeaderField: "Cookie")
        }
        let (data, response) = try await (followRedirects ? session : noRedirectSession).data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.message("No HTTP response")
        }
        if let url = http.url ?? request.url,
           let next = SessionCookies.updated(sessionStore.load(), responseHeaders: http.allHeaderFields, url: url) {
            sessionStore.save(next)
        }
        return (data, http)
    }

    private func check(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200...299: return
        case 401:
            onUnauthorized?()
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden(Self.serverError(in: data) ?? "Not allowed for your plan or role")
        default:
            throw APIError.http(response.statusCode, Self.serverError(in: data) ?? String(decoding: data, as: UTF8.self))
        }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch let DecodingError.keyNotFound(key, _) {
            throw APIError.decoding("missing \(key.stringValue)")
        } catch let DecodingError.typeMismatch(_, context) {
            throw APIError.decoding("bad type at \(context.codingPath.map(\.stringValue).joined(separator: "."))")
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    static func serverError(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (object["error"] as? String) ?? (object["message"] as? String)
    }

    static func formEncode(_ fields: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        func encode(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: allowed)?.replacingOccurrences(of: "%20", with: "+") ?? value
        }
        return fields.map { "\(encode($0.0))=\(encode($0.1))" }.joined(separator: "&")
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
