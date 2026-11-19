import Foundation
import Synchronization
@testable import Plumtier

/// Answers requests for one fake store host. Each test uses its own host, so tests can run in
/// parallel without sharing answers.
final class StubProtocol: URLProtocol
{
    enum Answer: Sendable
    {
        case json(Int, String)
        case fail(URLError.Code)
    }

    struct Seen: Sendable
    {
        let path: String
        let body: [String: String]
    }

    static let answers = Mutex<[String: [Answer]]>([:])
    static let seen = Mutex<[String: [Seen]]>([:])

    /// A client for a new fake store that gives `answers` in order.
    static func client(_ answers: Answer...) -> (PlumtierClient, String)
    {
        let host = "store-\(UUID().uuidString.lowercased()).test"
        self.answers.withLock { $0[host] = answers }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return (PlumtierClient(store: URL(string: "https://\(host)")!, session: URLSession(configuration: config)), host)
    }

    /// Adds more answers for a host made by `client`.
    static func add(_ host: String, _ more: Answer...)
    {
        answers.withLock { $0[host, default: []].append(contentsOf: more) }
    }

    static func requests(_ host: String) -> [Seen]
    {
        seen.withLock { $0[host] ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading()
    {
        let host = request.url?.host() ?? ""
        let body = Self.readBody(request)
        Self.seen.withLock { $0[host, default: []].append(Seen(path: request.url?.path() ?? "", body: body)) }
        let answer = Self.answers.withLock
        { answers -> Answer in
            guard var list = answers[host], !list.isEmpty else
            {
                return .fail(.cannotFindHost)
            }
            let first = list.removeFirst()
            answers[host] = list
            return first
        }
        switch answer
        {
        case .json(let status, let text):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(text.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .fail(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    static func readBody(_ request: URLRequest) -> [String: String]
    {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream
        {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable
            {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0
                {
                    break
                }
                data.append(buffer, count: count)
            }
            stream.close()
        }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }
}

/// Response bodies shaped like src/worker/licenses/api.ts in the Plumtier repo.
enum Fixture
{
    static let licenseKey = """
    {"id":"lic_1","status":"active","key":"7KQ2M-XW9PA-4TB8N-R2HDE","activation_limit":3,"activation_usage":1,"created_at":"2025-11-01T10:00:00.000Z","expires_at":null}
    """
    static let meta = """
    {"store_id":"st_1","order_id":"ord_1","order_number":1042,"product_id":"prd_1","product_name":"Clipboard Pro","variant_id":"var_1","variant_name":"3 Macs","customer_id":"cus_1","customer_name":"Ada Lovelace","customer_email":"ada@example.com"}
    """
    static let instance = """
    {"id":"inst_1","name":"Ada's MacBook Pro","created_at":"2026-11-19T08:30:00.000Z"}
    """

    static func body(_ flag: String, _ value: Bool, error: String? = nil, instance: Bool = true, key: Bool = true) -> String
    {
        let errorJSON = error.map { "\"\($0)\"" } ?? "null"
        return """
        {"\(flag)":\(value),"error":\(errorJSON),"instance":\(instance ? Self.instance : "null"),"license_key":\(key ? licenseKey : "null"),"meta":\(key ? meta : "null")}
        """
    }
}
