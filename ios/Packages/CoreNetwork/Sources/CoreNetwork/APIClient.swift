// CoreNetwork/Sources/CoreNetwork/APIClient.swift
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Ошибка API в формате RFC 7807 (раздел 6.1). `code` — машинный код (SLOT_ALREADY_TAKEN и т.д.).
public struct ProblemDetails: Error, Decodable, Equatable, Sendable {
    public let type: String
    public let title: String
    public let status: Int
    public let code: String
    public let detail: String?
    public let traceId: String?
}

public enum APIError: Error, Equatable, Sendable {
    case problem(ProblemDetails)
    case unexpectedStatus(Int)
    case unauthorized
}

public struct APIRequest: Sendable {
    public var method: String
    public var path: String
    public var body: Data?
    public var idempotencyKey: UUID?
    public var ifMatch: String?

    public init(method: String, path: String, body: Data? = nil, idempotencyKey: UUID? = nil, ifMatch: String? = nil) {
        self.method = method
        self.path = path
        self.body = body
        self.idempotencyKey = idempotencyKey
        self.ifMatch = ifMatch
    }
}

public protocol AccessTokenProvider: Sendable {
    func accessToken() async -> String?
    /// Прозрачное обновление по refresh-токену (AC-001.5). false — выйти из аккаунта.
    func refresh() async -> Bool
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.unexpectedStatus(-1) }
        return (data, http)
    }
}

public struct APIClient: Sendable {
    private let baseURL: URL
    private let transport: HTTPTransport
    private let tokens: AccessTokenProvider
    private let appVersion: String
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public init(baseURL: URL, transport: HTTPTransport = URLSessionTransport(), tokens: AccessTokenProvider, appVersion: String) {
        self.baseURL = baseURL
        self.transport = transport
        self.tokens = tokens
        self.appVersion = appVersion
    }

    public func send<Response: Decodable>(_ request: APIRequest, as type: Response.Type) async throws -> Response {
        let data = try await perform(request, allowRefresh: true)
        return try decoder.decode(Response.self, from: data)
    }

    private func perform(_ request: APIRequest, allowRefresh: Bool) async throws -> Data {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent(request.path))
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(appVersion, forHTTPHeaderField: "X-App-Version")
        urlRequest.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-Id")
        if let key = request.idempotencyKey { urlRequest.setValue(key.uuidString, forHTTPHeaderField: "Idempotency-Key") }
        if let etag = request.ifMatch { urlRequest.setValue(etag, forHTTPHeaderField: "If-Match") }
        if let token = await tokens.accessToken() { urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let (data, response) = try await transport.send(urlRequest)
        switch response.statusCode {
        case 200..<300:
            return data
        case 401 where allowRefresh:
            guard await tokens.refresh() else { throw APIError.unauthorized }
            return try await perform(request, allowRefresh: false)   // тот же Idempotency-Key
        default:
            if let problem = try? decoder.decode(ProblemDetails.self, from: data) { throw APIError.problem(problem) }
            throw APIError.unexpectedStatus(response.statusCode)
        }
    }
}
