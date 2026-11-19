import CryptoKit
import Foundation
import Testing
@testable import Plumtier

@Suite struct TrialTests
{
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 86_400

    func keeper(_ stores: [MemoryStore], machine: String = "mac-a", days: Int = 14) -> TrialKeeper
    {
        TrialKeeper(trial: .days(days), stores: stores, name: "t", key: TrialKeeper.signingKey(service: "plumtier.store.test.app", machine: machine))
    }

    @Test func freshTrialStarts()
    {
        let stores = [MemoryStore(), MemoryStore(), MemoryStore()]
        let status = keeper(stores).check(now: start)
        #expect(status == .active(endsAt: start.addingTimeInterval(14 * day), daysLeft: 14))
        #expect(stores.allSatisfy { $0.read("t") != nil })
    }

    @Test func countsDownAndEnds()
    {
        let stores = [MemoryStore()]
        let keeper = keeper(stores)
        _ = keeper.check(now: start)
        #expect(keeper.check(now: start.addingTimeInterval(13.5 * day)) == .active(endsAt: start.addingTimeInterval(14 * day), daysLeft: 1))
        #expect(keeper.check(now: start.addingTimeInterval(14 * day)) == .ended(endsAt: start.addingTimeInterval(14 * day)))
    }

    @Test func deletingSomeCopiesDoesNotRestart()
    {
        let stores = [MemoryStore(), MemoryStore(), MemoryStore()]
        let keeper = keeper(stores)
        _ = keeper.check(now: start)
        stores[0].delete("t")
        stores[1].delete("t")
        let later = start.addingTimeInterval(20 * day)
        #expect(keeper.check(now: later) == .ended(endsAt: start.addingTimeInterval(14 * day)))
        #expect(stores.allSatisfy { $0.read("t") != nil })
    }

    @Test func earliestStartWins()
    {
        let old = [MemoryStore()]
        _ = keeper(old).check(now: start)
        let fresh = [MemoryStore()]
        _ = keeper(fresh).check(now: start.addingTimeInterval(10 * day))
        // A reinstall leaves only the newer record in one place and the old one in the Keychain.
        let both = [fresh[0], old[0]]
        #expect(keeper(both).check(now: start.addingTimeInterval(10 * day)) == .active(endsAt: start.addingTimeInterval(14 * day), daysLeft: 4))
    }

    @Test func editedRecordEndsTrial() throws
    {
        let stores = [MemoryStore(), MemoryStore()]
        let keeper = keeper(stores)
        _ = keeper.check(now: start)
        let data = try #require(stores[0].read("t"))
        let text = String(decoding: data, as: UTF8.self)
        // Swap the signed record for one that starts later, keeping the old signature.
        let signed = try JSONDecoder().decode(TrialKeeper.Signed.self, from: data)
        let forged = TrialKeeper.Record(startedAt: start.timeIntervalSince1970 + 30 * day, lastSeenAt: start.timeIntervalSince1970 + 30 * day, ended: false)
        let forgedData = try JSONEncoder().encode(TrialKeeper.Signed(record: try JSONEncoder().encode(forged), signature: signed.signature))
        #expect(!text.isEmpty)
        stores[0].write(forgedData, "t")
        #expect(keeper.check(now: start.addingTimeInterval(day)) == .ended(endsAt: nil))
        // It stays ended even after the forged copy is removed.
        stores[0].delete("t")
        #expect(keeper.check(now: start.addingTimeInterval(day)) == .ended(endsAt: nil))
    }

    @Test func recordFromAnotherMacEndsTrial()
    {
        let stores = [MemoryStore()]
        _ = keeper(stores, machine: "mac-a").check(now: start)
        #expect(keeper(stores, machine: "mac-b").check(now: start) == .ended(endsAt: nil))
    }

    @Test func clockMovedBackEndsTrial()
    {
        let stores = [MemoryStore()]
        let keeper = keeper(stores)
        _ = keeper.check(now: start.addingTimeInterval(5 * day))
        #expect(keeper.check(now: start.addingTimeInterval(5 * day - 30 * 60)).isActive)
        #expect(keeper.check(now: start.addingTimeInterval(2 * day)) == .ended(endsAt: nil))
        #expect(keeper.check(now: start.addingTimeInterval(6 * day)) == .ended(endsAt: nil))
    }

    @MainActor
    @Test func licenseUnlocksAfterTrialEnds() async throws
    {
        let stores = [MemoryStore()]
        _ = keeper(stores).check(now: start)
        let (client, host) = StubProtocol.client(.json(200, Fixture.body("activated", true)))
        let now = start.addingTimeInterval(30 * day)
        let license = PlumtierLicense(store: client.store, product: "clipboard-pro", displayName: "Clipboard", client: client, keychain: MemoryStore(), trial: keeper(stores), instanceName: "Mac", now: { now }, checkNow: false)
        #expect(!license.trialStatus.isActive)
        #expect(!license.isUnlocked)
        try await license.activate(key: "7KQ2M-XW9PA-4TB8N-R2HDE")
        #expect(license.isUnlocked)
        #expect(!StubProtocol.requests(host).isEmpty)
    }

    @MainActor
    @Test func noTrialWhenNotOffered() async
    {
        let (client, _) = StubProtocol.client()
        let license = PlumtierLicense(store: client.store, product: "clipboard-pro", displayName: "Clipboard", client: client, keychain: MemoryStore(), instanceName: "Mac", checkNow: false)
        #expect(license.trialStatus == .notOffered)
        #expect(!license.isUnlocked)
    }

    @MainActor
    @Test func trialUnlocks()
    {
        let (client, _) = StubProtocol.client()
        let start = self.start
        let license = PlumtierLicense(store: client.store, product: "clipboard-pro", displayName: "Clipboard", client: client, keychain: MemoryStore(), trial: keeper([MemoryStore()]), instanceName: "Mac", now: { start }, checkNow: false)
        #expect(license.isUnlocked)
        #expect(!license.isLicensed)
    }

    @Test func machineIDReads()
    {
        #expect(TrialKeeper.machineID != "unknown-mac")
    }
}
