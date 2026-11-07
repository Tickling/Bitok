import Foundation
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CoreNetwork

actor RecordingTransport: HTTPTransport {
    var requests: [URLRequest] = []
    let responses: [(Int, String)]

    init(responses: [(Int, String)]) { self.responses = responses }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (status, body) = responses[min(requests.count - 1, responses.count - 1)]
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

struct StubTokens: AccessTokenProvider {
    func accessToken() async -> String? { "token" }
    func refresh() async -> Bool { true }
}

struct Echo: Decodable, Equatable { let id: String }

@Suite("APIClient")
struct APIClientTests {
    let base = URL(string: "https://api.bitok.app/v1")!

    @Test func decodesProblemDetails() async {
        let transport = RecordingTransport(responses: [(409, #"{"type":"t","title":"Слот уже занят","status":409,"code":"SLOT_ALREADY_TAKEN"}"#)])
        let client = APIClient(baseURL: base, transport: transport, tokens: StubTokens(), appVersion: "1.0.0")
        do {
            _ = try await client.send(APIRequest(method: "POST", path: "bookings"), as: Echo.self)
            Issue.record("expected error")
        } catch let APIError.problem(problem) {
            #expect(problem.code == "SLOT_ALREADY_TAKEN")
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test("После 401 запрос повторяется с тем же Idempotency-Key")
    func retriesAfterRefreshWithSameKey() async throws {
        let transport = RecordingTransport(responses: [(401, "{}"), (201, #"{"id":"b1"}"#)])
        let client = APIClient(baseURL: base, transport: transport, tokens: StubTokens(), appVersion: "1.0.0")
        let key = UUID()
        let result = try await client.send(APIRequest(method: "POST", path: "bookings", idempotencyKey: key), as: Echo.self)
        #expect(result == Echo(id: "b1"))
        let keys = await transport.requests.map { $0.value(forHTTPHeaderField: "Idempotency-Key") }
        #expect(keys == [key.uuidString, key.uuidString])
    }
}
