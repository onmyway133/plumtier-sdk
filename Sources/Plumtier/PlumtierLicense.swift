import AppKit
import Foundation
import Observation

/// What the store said about the license on this Mac.
public struct LicenseInfo: Sendable, Equatable
{
    public let key: LicenseKey
    public let instance: LicenseInstance?
    public let meta: LicenseMeta?

    public init(key: LicenseKey, instance: LicenseInstance?, meta: LicenseMeta?)
    {
        self.key = key
        self.instance = instance
        self.meta = meta
    }
}

/// Where the license on this Mac stands.
public enum LicenseStatus: Sendable, Equatable
{
    /// No license key on this Mac.
    case unlicensed
    /// Asking the store.
    case checking
    /// The store confirmed the key and this Mac's activation.
    case licensed(LicenseInfo)
    /// The store refused the key: disabled, expired, for another product, or this Mac was
    /// removed from it. `info` is set when the store still described the key.
    case invalid(reason: String, info: LicenseInfo?)
    /// The store couldn't be reached, so the license couldn't be checked. Counts as not licensed.
    case unreachable(message: String)
}

/// A license action that didn't work, with a message to show as is.
public struct LicenseActionError: Error, Sendable, Equatable, LocalizedError
{
    public let message: String

    public var errorDescription: String? { message }
}

/// The license for one product on one Plumtier store.
///
/// Create one when the app starts and keep it, for example in `@State` on your `App`. It checks
/// the stored license with the store right away and every time you call `refresh()`.
@MainActor
@Observable
public final class PlumtierLicense
{
    /// The store's address, for example `https://store.example.com`.
    public let store: URL
    /// The product's link (slug), as in `https://store.example.com/p/<link>`.
    public let product: String
    /// The name shown in the license window. Defaults to the app's name.
    public let displayName: String
    /// What this Mac is called in the buyer's list of devices.
    public let instanceName: String

    public internal(set) var status: LicenseStatus = .unlicensed

    /// The free trial, when the app offers one. `.notOffered` otherwise.
    public internal(set) var trialStatus: TrialStatus = .notOffered

    /// True when the app should unlock its paid features: licensed, or in the free trial.
    public var isUnlocked: Bool
    {
        isLicensed || trialStatus.isActive
    }

    /// True when the store confirmed the license on this Mac.
    public var isLicensed: Bool
    {
        if case .licensed = status
        {
            return true
        }
        return false
    }

    /// The license details, when the store described the key.
    public var info: LicenseInfo?
    {
        switch status
        {
        case .licensed(let info):
            return info
        case .invalid(_, let info):
            return info
        default:
            return nil
        }
    }

    let client: PlumtierClient
    let keychain: any DataStore
    let trialKeeper: TrialKeeper?
    let now: @Sendable () -> Date
    private var checkTask: Task<Void, Never>?

    /// - Parameters:
    ///   - store: the store's address, for example `https://store.example.com`.
    ///   - product: the product's link (slug). Keys for other products are refused.
    ///   - displayName: the name shown in the license window. Defaults to the app's name.
    ///   - trial: a free trial to offer from the first launch, for example `.days(14)`. `nil`
    ///     (the default) offers no trial.
    public convenience init(store: URL, product: String, displayName: String? = nil, trial: Trial? = nil)
    {
        let service = "plumtier.\(store.host() ?? store.absoluteString).\(product)"
        let keeper = trial.map
        { trial in
            let name = TrialKeeper.recordName(service: service)
            return TrialKeeper(trial: trial, stores: TrialKeeper.defaultStores(service: service, name: name), name: name, key: TrialKeeper.signingKey(service: service, machine: TrialKeeper.machineID))
        }
        self.init(store: store, product: product, displayName: displayName, client: PlumtierClient(store: store), keychain: KeychainStore(service: service), trial: keeper, checkNow: true)
    }

    init(store: URL, product: String, displayName: String?, client: PlumtierClient, keychain: any DataStore, trial: TrialKeeper? = nil, instanceName: String? = nil, now: @escaping @Sendable () -> Date = { Date() }, checkNow: Bool)
    {
        self.trialKeeper = trial
        self.now = now
        self.store = store
        self.product = product
        self.displayName = displayName ?? Self.appName
        self.instanceName = instanceName ?? Host.current().localizedName ?? "Mac"
        self.client = client
        self.keychain = keychain
        if saved != nil
        {
            status = .checking
        }
        checkTrial()
        if checkNow
        {
            checkTask = Task { await refresh() }
        }
    }

    // MARK: Actions

    /// Checks the stored license with the store. Call it at launch (done for you) and whenever
    /// you want a fresh answer.
    public func refresh() async
    {
        checkTrial()
        guard let saved else
        {
            status = .unlicensed
            return
        }
        status = .checking
        do
        {
            let response = try await client.validate(key: saved.key, instanceID: saved.instanceID, product: product)
            let info = response.licenseKey.map { LicenseInfo(key: $0, instance: response.instance, meta: response.meta) }
            if response.success, let info
            {
                status = .licensed(info)
            }
            else if response.statusCode == 404
            {
                // The key is gone, or this Mac was removed from it (for example from the portal).
                // Either way this Mac has no seat any more.
                forget()
                let reason = info == nil ? (response.error ?? "This license key doesn't exist.") : "This Mac was removed from the license. Activate it again to keep using it."
                status = .invalid(reason: reason, info: nil)
            }
            else
            {
                // Disabled, expired or another product. Keep the key: the seller can turn it back
                // on, or a renewal can extend it.
                status = .invalid(reason: response.error ?? "This license key can't be used.", info: info)
            }
        }
        catch
        {
            status = .unreachable(message: error.localizedDescription)
        }
    }

    /// Activates `key` on this Mac.
    ///
    /// - Throws: `LicenseActionError` with a message to show when the key is refused or the
    ///   store can't be reached. The status stays as it was.
    public func activate(key: String) async throws
    {
        let key = Self.normalize(key)
        guard !key.isEmpty else
        {
            throw LicenseActionError(message: "Enter your license key.")
        }
        let previous = saved
        let response: LicenseResponse
        do
        {
            response = try await client.activate(key: key, instanceName: instanceName, product: product)
        }
        catch
        {
            throw LicenseActionError(message: error.localizedDescription)
        }
        guard response.success, let instance = response.instance, let licenseKey = response.licenseKey else
        {
            throw LicenseActionError(message: response.error ?? "This license key couldn't be activated.")
        }
        // Free the seat an older key held on this Mac. Best effort: the new key works either way.
        if let previous, previous.key != key
        {
            _ = try? await client.deactivate(key: previous.key, instanceID: previous.instanceID)
        }
        saved = SavedLicense(key: key, instanceID: instance.id)
        status = .licensed(LicenseInfo(key: licenseKey, instance: instance, meta: response.meta))
    }

    /// Frees this Mac's seat and removes the key from this Mac.
    ///
    /// - Throws: `LicenseActionError` when the store can't be reached or refuses. The key stays
    ///   on this Mac so the buyer can try again.
    public func deactivate() async throws
    {
        guard let saved else
        {
            status = .unlicensed
            return
        }
        let response: LicenseResponse
        do
        {
            response = try await client.deactivate(key: saved.key, instanceID: saved.instanceID)
        }
        catch
        {
            throw LicenseActionError(message: error.localizedDescription)
        }
        // 404: the seat or the key is already gone, which is what deactivating wanted.
        guard response.success || response.statusCode == 404 else
        {
            throw LicenseActionError(message: response.error ?? "This Mac couldn't be deactivated.")
        }
        forget()
        status = .unlicensed
    }

    /// The product page, where buyers pay.
    ///
    /// - Parameters:
    ///   - variant: a variant id to preselect.
    ///   - code: a discount code to prefill.
    ///   - ref: an affiliate code.
    public func buyURL(variant: String? = nil, code: String? = nil, ref: String? = nil) -> URL
    {
        var url = store.appending(path: "p/\(product)")
        let items = [("variant", variant), ("code", code), ("ref", ref)].compactMap
        { name, value in
            value.map { URLQueryItem(name: name, value: $0) }
        }
        if !items.isEmpty
        {
            url.append(queryItems: items)
        }
        return url
    }

    /// The customer portal, where buyers see their keys and remove Macs they no longer use.
    public var portalURL: URL
    {
        store.appending(path: "portal")
    }

    /// Opens the product page in the browser.
    public func openBuyPage(variant: String? = nil, code: String? = nil, ref: String? = nil)
    {
        NSWorkspace.shared.open(buyURL(variant: variant, code: code, ref: ref))
    }

    /// Opens the customer portal in the browser.
    public func openPortal()
    {
        NSWorkspace.shared.open(portalURL)
    }

    /// Updates `trialStatus`. `refresh()` does this too; call it when you want an up to date
    /// countdown without asking the store, for example when a window opens.
    public func checkTrial()
    {
        guard let trialKeeper else
        {
            return
        }
        trialStatus = trialKeeper.check(now: now())
    }

    // MARK: Storage

    struct SavedLicense: Codable, Equatable
    {
        let key: String
        let instanceID: String
    }

    var saved: SavedLicense?
    {
        get
        {
            keychain.read("license").flatMap { try? JSONDecoder().decode(SavedLicense.self, from: $0) }
        }
        set
        {
            if let newValue, let data = try? JSONEncoder().encode(newValue)
            {
                keychain.write(data, "license")
            }
            else
            {
                keychain.delete("license")
            }
        }
    }

    private func forget()
    {
        saved = nil
    }

    /// Matches the store: keys are compared trimmed and uppercased.
    static func normalize(_ key: String) -> String
    {
        key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    static var appName: String
    {
        let bundle = Bundle.main
        return bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ProcessInfo.processInfo.processName
    }
}
