import Foundation

/// A license key as the store reports it.
public struct LicenseKey: Sendable, Equatable, Decodable
{
    public enum Status: String, Sendable, Equatable, Decodable
    {
        /// Bought but not activated on any device yet.
        case inactive
        /// Activated on at least one device.
        case active
        /// Past its expiry date, or its subscription ended.
        case expired
        /// Turned off by the seller, for example after a refund.
        case disabled
        /// A status this version of the SDK doesn't know.
        case unknown

        public init(from decoder: Decoder) throws
        {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Status(rawValue: raw) ?? .unknown
        }
    }

    public let id: String
    public let status: Status
    public let key: String
    /// How many devices can use the key at once. `nil` means unlimited.
    public let activationLimit: Int?
    /// How many devices use the key now.
    public let activationUsage: Int
    public let createdAt: Date?
    public let expiresAt: Date?

    public init(id: String, status: Status, key: String, activationLimit: Int?, activationUsage: Int, createdAt: Date?, expiresAt: Date?)
    {
        self.id = id
        self.status = status
        self.key = key
        self.activationLimit = activationLimit
        self.activationUsage = activationUsage
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

/// One device a license key is activated on.
public struct LicenseInstance: Sendable, Equatable, Decodable
{
    public let id: String
    public let name: String
    public let createdAt: Date?

    public init(id: String, name: String, createdAt: Date?)
    {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

/// The order, product and customer behind a license key.
public struct LicenseMeta: Sendable, Equatable, Decodable
{
    public let storeID: String?
    public let orderID: String?
    public let orderNumber: Int?
    public let productID: String?
    public let productName: String
    public let variantID: String?
    public let variantName: String
    public let customerID: String?
    public let customerName: String
    public let customerEmail: String

    enum CodingKeys: String, CodingKey
    {
        case storeID = "storeId"
        case orderID = "orderId"
        case orderNumber
        case productID = "productId"
        case productName
        case variantID = "variantId"
        case variantName
        case customerID = "customerId"
        case customerName
        case customerEmail
    }

    public init(storeID: String? = nil, orderID: String? = nil, orderNumber: Int? = nil, productID: String? = nil, productName: String, variantID: String? = nil, variantName: String = "", customerID: String? = nil, customerName: String, customerEmail: String)
    {
        self.storeID = storeID
        self.orderID = orderID
        self.orderNumber = orderNumber
        self.productID = productID
        self.productName = productName
        self.variantID = variantID
        self.variantName = variantName
        self.customerID = customerID
        self.customerName = customerName
        self.customerEmail = customerEmail
    }

    public init(from decoder: Decoder) throws
    {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        storeID = try c.decodeIfPresent(String.self, forKey: .storeID)
        orderID = try c.decodeIfPresent(String.self, forKey: .orderID)
        orderNumber = try c.decodeIfPresent(Int.self, forKey: .orderNumber)
        productID = try c.decodeIfPresent(String.self, forKey: .productID)
        productName = try c.decodeIfPresent(String.self, forKey: .productName) ?? ""
        variantID = try c.decodeIfPresent(String.self, forKey: .variantID)
        variantName = try c.decodeIfPresent(String.self, forKey: .variantName) ?? ""
        customerID = try c.decodeIfPresent(String.self, forKey: .customerID)
        customerName = try c.decodeIfPresent(String.self, forKey: .customerName) ?? ""
        customerEmail = try c.decodeIfPresent(String.self, forKey: .customerEmail) ?? ""
    }
}

/// The answer to an activate, validate or deactivate call.
///
/// The store answers every call with the same shape. `success` is the call's own flag
/// (`activated`, `valid` or `deactivated`), and `error` explains a `false`. A refused call can
/// still carry the key and its details, for example when the activation limit is reached.
public struct LicenseResponse: Sendable, Equatable
{
    public let success: Bool
    public let error: String?
    public let licenseKey: LicenseKey?
    public let instance: LicenseInstance?
    public let meta: LicenseMeta?
    /// The HTTP status code. 404 means the key, or the instance on a validate, doesn't exist.
    public let statusCode: Int

    public init(success: Bool, error: String? = nil, licenseKey: LicenseKey? = nil, instance: LicenseInstance? = nil, meta: LicenseMeta? = nil, statusCode: Int = 200)
    {
        self.success = success
        self.error = error
        self.licenseKey = licenseKey
        self.instance = instance
        self.meta = meta
        self.statusCode = statusCode
    }
}

/// The raw body. Exactly one of the three flags is present.
struct ResponseBody: Decodable
{
    let activated: Bool?
    let valid: Bool?
    let deactivated: Bool?
    let error: String?
    let licenseKey: LicenseKey?
    let instance: LicenseInstance?
    let meta: LicenseMeta?
}
