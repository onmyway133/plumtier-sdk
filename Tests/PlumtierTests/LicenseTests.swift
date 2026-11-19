import Foundation
import Testing
@testable import Plumtier

@MainActor
@Suite struct LicenseTests
{
    func make(_ answers: StubProtocol.Answer..., keychain: MemoryStore = MemoryStore()) -> (PlumtierLicense, String)
    {
        let (client, host) = StubProtocol.client()
        answers.forEach { StubProtocol.add(host, $0) }
        let license = PlumtierLicense(store: client.store, product: "clipboard-pro", displayName: "Clipboard", client: client, keychain: keychain, instanceName: "Test Mac", checkNow: false)
        return (license, host)
    }

    func savedKeychain() -> MemoryStore
    {
        let keychain = MemoryStore()
        keychain.write(Data(#"{"key":"7KQ2M-XW9PA-4TB8N-R2HDE","instanceID":"inst_1"}"#.utf8), "license")
        return keychain
    }

    @Test func noKeyIsUnlicensed() async
    {
        let (license, host) = make()
        await license.refresh()
        #expect(license.status == .unlicensed)
        #expect(!license.isLicensed)
        #expect(StubProtocol.requests(host).isEmpty)
    }

    @Test func activateSavesAndLicenses() async throws
    {
        let keychain = MemoryStore()
        let (license, host) = make(.json(200, Fixture.body("activated", true)), keychain: keychain)
        try await license.activate(key: "  7kq2m-xw9pa-4tb8n-r2hde \n")

        #expect(license.isLicensed)
        #expect(license.info?.meta?.customerEmail == "ada@example.com")
        #expect(license.saved == .init(key: "7KQ2M-XW9PA-4TB8N-R2HDE", instanceID: "inst_1"))
        let request = try #require(StubProtocol.requests(host).first)
        #expect(request.body["license_key"] == "7KQ2M-XW9PA-4TB8N-R2HDE")
        #expect(request.body["instance_name"] == "Test Mac")
        #expect(request.body["product_id"] == "clipboard-pro")
    }

    @Test func activateRefusedKeepsStatus() async
    {
        let body = Fixture.body("activated", false, error: "This license key doesn't exist.", instance: false, key: false)
        let (license, _) = make(.json(404, body))
        await #expect(throws: LicenseActionError(message: "This license key doesn't exist."))
        {
            try await license.activate(key: "NOPE")
        }
        #expect(license.status == .unlicensed)
        #expect(license.saved == nil)
    }

    @Test func activateEmptyKey() async
    {
        let (license, host) = make()
        await #expect(throws: LicenseActionError.self)
        {
            try await license.activate(key: "   ")
        }
        #expect(StubProtocol.requests(host).isEmpty)
    }

    @Test func refreshValid() async
    {
        let (license, host) = make(.json(200, Fixture.body("valid", true)), keychain: savedKeychain())
        #expect(license.status == .checking)
        await license.refresh()
        #expect(license.isLicensed)
        #expect(StubProtocol.requests(host).first?.body["instance_id"] == "inst_1")
    }

    @Test func refreshDisabledKeepsKey() async
    {
        let body = Fixture.body("valid", false, error: "This license key has been disabled.").replacingOccurrences(of: "\"active\"", with: "\"disabled\"")
        let keychain = savedKeychain()
        let (license, _) = make(.json(200, body), keychain: keychain)
        await license.refresh()
        #expect(license.status == .invalid(reason: "This license key has been disabled.", info: license.info))
        #expect(license.info?.key.status == .disabled)
        #expect(license.saved != nil)
    }

    @Test func refreshInstanceRemovedForgetsKey() async
    {
        let body = Fixture.body("valid", false, error: "This instance isn't activated for this key.", instance: false)
        let (license, _) = make(.json(404, body), keychain: savedKeychain())
        await license.refresh()
        #expect(license.status == .invalid(reason: "This Mac was removed from the license. Activate it again to keep using it.", info: nil))
        #expect(license.saved == nil)
    }

    @Test func refreshOfflineIsUnreachable() async
    {
        let (license, _) = make(.fail(.notConnectedToInternet), keychain: savedKeychain())
        await license.refresh()
        guard case .unreachable = license.status else
        {
            Issue.record("Expected unreachable, got \(license.status)")
            return
        }
        #expect(!license.isLicensed)
        #expect(license.saved != nil)
    }

    @Test func deactivateForgets() async throws
    {
        let (license, host) = make(.json(200, Fixture.body("deactivated", true, instance: false)), keychain: savedKeychain())
        try await license.deactivate()
        #expect(license.status == .unlicensed)
        #expect(license.saved == nil)
        #expect(StubProtocol.requests(host).first?.path == "/api/v1/licenses/deactivate")
    }

    @Test func deactivateOfflineKeepsKey() async
    {
        let (license, _) = make(.fail(.timedOut), keychain: savedKeychain())
        await #expect(throws: LicenseActionError.self)
        {
            try await license.deactivate()
        }
        #expect(license.saved != nil)
    }

    @Test func buyAndPortalURLs()
    {
        let license = PlumtierLicense(store: URL(string: "https://store.example.com")!, product: "clipboard-pro", displayName: "Clipboard", client: PlumtierClient(store: URL(string: "https://store.example.com")!), keychain: MemoryStore(), instanceName: "Mac", checkNow: false)
        #expect(license.buyURL().absoluteString == "https://store.example.com/p/clipboard-pro")
        #expect(license.buyURL(variant: "var_1", code: "LAUNCH").absoluteString == "https://store.example.com/p/clipboard-pro?variant=var_1&code=LAUNCH")
        #expect(license.portalURL.absoluteString == "https://store.example.com/portal")
    }
}
