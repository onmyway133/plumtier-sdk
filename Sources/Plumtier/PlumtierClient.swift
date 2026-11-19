import Foundation

/// Something went wrong before the store could answer.
public enum PlumtierError: Error, Sendable, Equatable, LocalizedError
{
    /// The store couldn't be reached: offline, timed out, DNS, TLS.
    case network(URLError.Code)
    /// The store answered with something that isn't a license API response.
    case invalidResponse(statusCode: Int)

    public var errorDescription: String?
    {
        switch self
        {
        case .network(.notConnectedToInternet), .network(.networkConnectionLost):
            return "You're offline. Connect to the internet and try again."
        case .network(.timedOut):
            return "The license server took too long to answer. Try again."
        case .network:
            return "Can't reach the license server. Try again."
        case .invalidResponse(let statusCode):
            return "The license server gave an unexpected answer (HTTP \(statusCode))."
        }
    }
}

/// Calls a Plumtier store's public license API.
///
/// Every call returns a `LicenseResponse` whenever the store answers, including refusals such
/// as an unknown key or a full activation limit; check `success`. Calls only throw a
/// `PlumtierError` when there is no usable answer.
public struct PlumtierClient: Sendable
{
    /// The store's address, for example `https://store.example.com`.
    public let store: URL
    let session: URLSession

    public init(store: URL, session: URLSession = .shared)
    {
        self.store = store
        self.session = session
    }

    /// Activates `key` on a device called `instanceName`. On success, keep `instance.id`; you
    /// need it to validate and deactivate this device later.
    ///
    /// - Parameter product: the product's link (slug) or id. When given, keys for other products
    ///   are refused.
    public func activate(key: String, instanceName: String, product: String? = nil) async throws -> LicenseResponse
    {
        try await call("activate", ["license_key": key, "instance_name": instanceName, "product_id": product])
    }

    /// Checks `key`, and that `instanceID` is still activated for it when given.
    public func validate(key: String, instanceID: String? = nil, product: String? = nil) async throws -> LicenseResponse
    {
        try await call("validate", ["license_key": key, "instance_id": instanceID, "product_id": product])
    }

    /// Frees the seat `instanceID` takes on `key`.
    public func deactivate(key: String, instanceID: String) async throws -> LicenseResponse
    {
        try await call("deactivate", ["license_key": key, "instance_id": instanceID])
    }

    func call(_ action: String, _ fields: [String: String?]) async throws -> LicenseResponse
    {
        var request = URLRequest(url: store.appending(path: "api/v1/licenses/\(action)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        request.httpBody = try JSONEncoder().encode(fields.compactMapValues { $0 })

        let data: Data
        let response: URLResponse
        do
        {
            (data, response) = try await session.data(for: request)
        }
        catch let error as URLError
        {
            throw PlumtierError.network(error.code)
        }
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let body = try? Self.decoder.decode(ResponseBody.self, from: data) else
        {
            throw PlumtierError.invalidResponse(statusCode: statusCode)
        }
        guard let flag = body.activated ?? body.valid ?? body.deactivated else
        {
            throw PlumtierError.invalidResponse(statusCode: statusCode)
        }
        return LicenseResponse(success: flag, error: body.error, licenseKey: body.licenseKey, instance: body.instance, meta: body.meta, statusCode: statusCode)
    }

    static let decoder: JSONDecoder =
    {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom
        { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
            {
                return date
            }
            if let date = try? Date(text, strategy: Date.ISO8601FormatStyle())
            {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not an ISO 8601 date: \(text)"))
        }
        return decoder
    }()
}
