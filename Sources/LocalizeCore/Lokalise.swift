import Foundation

public struct RemoteProject: Codable, Identifiable, Sendable {
    public var project_id: String
    public var name: String
    public var id: String { project_id }
}
public struct RemoteLanguage: Codable, Identifiable, Sendable {
    public var lang_id: Int
    public var lang_iso: String
    public var lang_name: String
    public var id: String { lang_iso }
}
public struct RemoteTranslation: Codable, Sendable {
    public var language_iso: String
    public var translation: String
    public var is_unverified: Bool?
    public var is_reviewed: Bool?
    public init(language_iso: String, translation: String, is_unverified: Bool? = false, is_reviewed: Bool? = true) {
        self.language_iso = language_iso; self.translation = translation; self.is_unverified = is_unverified; self.is_reviewed = is_reviewed
    }
}
public struct RemoteKey: Codable, Identifiable, Sendable {
    public var key_id: Int
    public var key_name: [String: String]
    public var description: String?
    public var is_plural: Bool?
    public var translations: [RemoteTranslation]
    public var id: Int { key_id }
    public init(key_id: Int, key_name: [String: String] = [:], description: String? = nil, is_plural: Bool? = false, translations: [RemoteTranslation]) {
        self.key_id = key_id; self.key_name = key_name; self.description = description; self.is_plural = is_plural; self.translations = translations
    }
}
public actor LokaliseClient {
    private let token: String
    private let session: URLSession
    private let base: URL
    public init(token: String, session: URLSession = URLSession(configuration: LokaliseClient.privateConfiguration()), base: URL = URL(string: "https://api.lokalise.com/api2")!) { self.token = token; self.session = session; self.base = base }
    public nonisolated static func privateConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return config
    }
    public func projects() async throws -> [RemoteProject] { try await paged(path: "projects", collection: "projects") }
    public func languages(project: String) async throws -> [RemoteLanguage] { try await paged(path: "projects/\(try projectPath(project))/languages", collection: "languages", cursor: false) }
    public func keys(project: String, progress: @escaping @Sendable (Int) -> Void = { _ in }) async throws -> [RemoteKey] { try await paged(path: "projects/\(try projectPath(project))/keys", collection: "keys", extra: [URLQueryItem(name: "include_translations", value: "1"), URLQueryItem(name: "disable_references", value: "1")], progress: progress) }
    private func projectPath(_ value: String) throws -> String {
        guard !value.isEmpty, !value.contains("/"), !value.contains("?"), !value.contains("#"), !value.contains("..") else { throw StudioError.message("Enter a valid Lokalise project ID and optional branch.") }
        return value
    }
    private func paged<T: Decodable>(path: String, collection: String, extra: [URLQueryItem] = [], cursor: Bool = true, progress: @Sendable (Int) -> Void = { _ in }) async throws -> [T] {
        var values: [T] = [], next: String?, seen = Set<String>(), page = 1
        repeat {
            try Task.checkCancellation()
            var query = extra + [URLQueryItem(name: "limit", value: "500")]
            if cursor { query.append(URLQueryItem(name: "pagination", value: "cursor")); if let next { query.append(URLQueryItem(name: "cursor", value: next)) } }
            else { query.append(URLQueryItem(name: "page", value: String(page))) }
            let (data, response) = try await request(path: path, query: query)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let array = json[collection] as? [[String: Any]] else { throw StudioError.message("Unexpected Lokalise response for \(collection). No local files were changed.") }
            values += try JSONDecoder().decode([T].self, from: JSONSerialization.data(withJSONObject: array))
            progress(values.count)
            next = response.value(forHTTPHeaderField: "X-Pagination-Next-Cursor") ?? response.value(forHTTPHeaderField: "nextCursor")
            if next == "" { next = nil }
            if let next, !seen.insert(next).inserted { throw StudioError.message("Lokalise returned a repeating pagination cursor. Retry the import.") }
            if !cursor {
                let totalPages = Int(response.value(forHTTPHeaderField: "X-Pagination-Page-Count") ?? "")
                next = (totalPages.map { page < $0 } ?? (array.count == 500)) ? String(page + 1) : nil
                page += 1
            }
            if values.count > 1_000_000 { throw StudioError.message("Project exceeds the supported one-million-key safety limit.") }
        } while next != nil
        return values
    }
    private func request(path: String, query: [URLQueryItem]) async throws -> (Data, HTTPURLResponse) {
        guard base.scheme == "https", base.host != nil, base.user == nil, base.password == nil else { throw StudioError.message("Lokalise requests require an HTTPS endpoint without URL credentials.") }
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StudioError.message("Add your Lokalise API token in Settings.") }
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!); request.timeoutInterval = 45
        request.setValue(token, forHTTPHeaderField: "X-Api-Token"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        for attempt in 0..<4 {
            try Task.checkCancellation()
            do {
                let (data, raw) = try await session.data(for: request, delegate: LokaliseRedirectPolicy(origin: base))
                guard let response = raw as? HTTPURLResponse else { throw StudioError.message("Invalid network response.") }
                if (200..<300).contains(response.statusCode) { return (data, response) }
                if [429, 500, 502, 503, 504].contains(response.statusCode), attempt < 3 {
                    let proposed = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) ?? pow(2, Double(attempt))
                    let retry = proposed.isFinite ? proposed : 1
                    try await Task.sleep(nanoseconds: UInt64(min(max(retry, 1), 60) * 1_000_000_000 + Double.random(in: 0...250_000_000))); continue
                }
                let message: String
                switch response.statusCode {
                case 401: message = "The Lokalise token is invalid or expired. Update it in Settings."
                case 403: message = "The token lacks permission to read this Lokalise project."
                case 404: message = "The Lokalise project or branch was not found. Check its mapping."
                case 429: message = "Lokalise is rate limiting requests. Retry later."
                default: message = "Lokalise returned HTTP \(response.statusCode). No translation changes were applied."
                }
                throw StudioError.message(message)
            } catch let error as URLError where [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(error.code) && attempt < 3 {
                try await Task.sleep(nanoseconds: UInt64(pow(2, Double(attempt)) * 1_000_000_000))
            }
        }
        throw StudioError.message("Lokalise could not be reached after bounded retries.")
    }
}
public struct TranslationMatch: Sendable {
    public var key: RemoteKey?
    public var candidates: [RemoteKey]
    public var reason: String
}
public struct TranslationIndex: Sendable {
    private let values: [String: [RemoteKey]]
    public init(keys: [RemoteKey], englishLocale: String) {
        values = Dictionary(grouping: keys.filter { $0.translations.contains { $0.language_iso == englishLocale } }, by: { key in key.translations.first { $0.language_iso == englishLocale }!.translation })
    }
    public func match(_ english: String, preferredID: Int? = nil) -> TranslationMatch {
        let candidates = values[english] ?? []
        if let preferredID, let chosen = candidates.first(where: { $0.id == preferredID }) { return TranslationMatch(key: chosen, candidates: candidates, reason: "Confirmed mapping") }
        if candidates.count == 1 { return TranslationMatch(key: candidates[0], candidates: candidates, reason: "Exact English match") }
        if candidates.count > 1 { return TranslationMatch(key: nil, candidates: candidates, reason: "Multiple remote keys share this English value. Choose a key in the review.") }
        let normalized = english.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        let suggestions = values.filter { $0.key.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping == normalized }.flatMap(\.value)
        return TranslationMatch(key: nil, candidates: suggestions, reason: suggestions.isEmpty ? "English value not found in Lokalise." : "Only a normalized match was found; exact source values differ.")
    }
}

/// Never forward a credential-bearing request to another origin or downgrade HTTPS.
final class LokaliseRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let origin: URL
    init(origin: URL) { self.origin = origin }
    func allows(_ url: URL) -> Bool {
        url.scheme == origin.scheme && url.host == origin.host && (url.port ?? 443) == (origin.port ?? 443)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(allows) == true ? request : nil)
    }
}
