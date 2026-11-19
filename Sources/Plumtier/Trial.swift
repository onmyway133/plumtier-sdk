import CryptoKit
import Foundation
import IOKit

/// A free trial the app offers before a license is needed.
public struct Trial: Sendable, Equatable
{
    /// How long the trial lasts from the first launch.
    public let days: Int

    public init(days: Int)
    {
        self.days = max(1, days)
    }

    public static func days(_ days: Int) -> Trial
    {
        Trial(days: days)
    }
}

/// Where the free trial stands on this Mac.
public enum TrialStatus: Sendable, Equatable
{
    /// The app doesn't offer a trial.
    case notOffered
    /// The trial runs until `endsAt`. `daysLeft` counts today, so it is 1 on the last day.
    case active(endsAt: Date, daysLeft: Int)
    /// The trial is over. `endsAt` is nil when it ended early because its record was changed or
    /// the clock was moved back.
    case ended(endsAt: Date?)

    public var isActive: Bool
    {
        if case .active = self
        {
            return true
        }
        return false
    }
}

/// Keeps the trial's start date on this Mac, signed and in several places.
///
/// A record holds when the trial started, the latest time this Mac was seen, and whether it
/// ended early. Every copy is signed with HMAC-SHA256 using a key made from the store, the
/// product and this Mac's hardware UUID, so an edited record, or one copied from another Mac,
/// fails. Copies live in the Keychain (it survives reinstalling the app), a file in
/// Application Support and user defaults: any valid copy means the trial already started, the
/// earliest start wins, and missing copies are written again. A copy that fails its signature,
/// or a clock more than an hour behind the latest time seen, ends the trial for good.
///
/// This is local only. It stops casual resets (reinstalling, deleting preferences, moving the
/// clock back), not someone who removes every copy or patches the app.
struct TrialKeeper: Sendable
{
    let trial: Trial
    let stores: [any DataStore]
    let name: String
    let key: SymmetricKey

    static let clockTolerance: TimeInterval = 60 * 60

    struct Record: Codable, Equatable
    {
        var startedAt: TimeInterval
        var lastSeenAt: TimeInterval
        var ended: Bool
    }

    struct Signed: Codable
    {
        let record: Data
        let signature: Data
    }

    func check(now: Date) -> TrialStatus
    {
        let at = now.timeIntervalSince1970
        var records: [Record] = []
        var tampered = false
        for store in stores
        {
            guard let data = store.read(name) else
            {
                continue
            }
            if let record = open(data)
            {
                records.append(record)
            }
            else
            {
                tampered = true
            }
        }

        var record = Record(startedAt: at, lastSeenAt: at, ended: false)
        if let earliest = records.map(\.startedAt).min(), let latest = records.map(\.lastSeenAt).max()
        {
            record = Record(startedAt: earliest, lastSeenAt: latest, ended: records.contains { $0.ended })
        }
        if tampered || at + Self.clockTolerance < record.lastSeenAt
        {
            record.ended = true
        }
        record.lastSeenAt = max(record.lastSeenAt, at)
        save(record)

        if record.ended
        {
            return .ended(endsAt: nil)
        }
        let endsAt = Date(timeIntervalSince1970: record.startedAt + TimeInterval(trial.days) * 86_400)
        if now >= endsAt
        {
            return .ended(endsAt: endsAt)
        }
        let daysLeft = Int((endsAt.timeIntervalSince(now) / 86_400).rounded(.up))
        return .active(endsAt: endsAt, daysLeft: max(1, daysLeft))
    }

    private func save(_ record: Record)
    {
        guard let body = try? JSONEncoder().encode(record) else
        {
            return
        }
        let signature = Data(HMAC<SHA256>.authenticationCode(for: body, using: key))
        guard let data = try? JSONEncoder().encode(Signed(record: body, signature: signature)) else
        {
            return
        }
        for store in stores
        {
            store.write(data, name)
        }
    }

    private func open(_ data: Data) -> Record?
    {
        guard let signed = try? JSONDecoder().decode(Signed.self, from: data),
              HMAC<SHA256>.isValidAuthenticationCode(signed.signature, authenticating: signed.record, using: key) else
        {
            return nil
        }
        return try? JSONDecoder().decode(Record.self, from: signed.record)
    }

    /// The signing key: tied to the store, the product and this Mac.
    static func signingKey(service: String, machine: String) -> SymmetricKey
    {
        SymmetricKey(data: SHA256.hash(data: Data("plumtier|trial|\(service)|\(machine)".utf8)))
    }

    /// A name for the records that doesn't spell out what they are.
    static func recordName(service: String) -> String
    {
        SHA256.hash(data: Data("plumtier|name|\(service)".utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// The Keychain, a file in Application Support and user defaults.
    static func defaultStores(service: String, name: String) -> [any DataStore]
    {
        var stores: [any DataStore] = [KeychainStore(service: service), DefaultsStore(prefix: "pt.")]
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        {
            let folder = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
            stores.append(FileStore(folder: support.appending(path: folder).appending(path: ".\(name)")))
        }
        return stores
    }

    /// This Mac's hardware UUID, or a fixed string when it can't be read.
    static var machineID: String
    {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer
        {
            IOObjectRelease(service)
        }
        let value = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)
        return value?.takeRetainedValue() as? String ?? "unknown-mac"
    }
}
