import Foundation
import Testing
@testable import Plumtier

@Suite struct ClientTests
{
    @Test func activateSendsFieldsAndDecodes() async throws
    {
        let (client, host) = StubProtocol.client(.json(200, Fixture.body("activated", true)))
        let response = try await client.activate(key: "7KQ2M-XW9PA-4TB8N-R2HDE", instanceName: "Ada's MacBook Pro", product: "clipboard-pro")

        #expect(response.success)
        #expect(response.error == nil)
        #expect(response.instance?.id == "inst_1")
        #expect(response.licenseKey?.status == .active)
        #expect(response.licenseKey?.activationLimit == 3)
        #expect(response.licenseKey?.activationUsage == 1)
        #expect(response.licenseKey?.expiresAt == nil)
        #expect(response.licenseKey?.createdAt == Date(timeIntervalSince1970: 1_761_991_200))
        #expect(response.meta?.customerName == "Ada Lovelace")
        #expect(response.meta?.variantName == "3 Macs")
        #expect(response.meta?.orderNumber == 1042)

        let request = try #require(StubProtocol.requests(host).first)
        #expect(request.path == "/api/v1/licenses/activate")
        #expect(request.body == ["license_key": "7KQ2M-XW9PA-4TB8N-R2HDE", "instance_name": "Ada's MacBook Pro", "product_id": "clipboard-pro"])
    }

    @Test func activationLimitReachedKeepsDetails() async throws
    {
        let body = Fixture.body("activated", false, error: "This license key has reached its activation limit of 3.", instance: false)
        let (client, _) = StubProtocol.client(.json(400, body))
        let response = try await client.activate(key: "7KQ2M-XW9PA-4TB8N-R2HDE", instanceName: "Mac")

        #expect(!response.success)
        #expect(response.statusCode == 400)
        #expect(response.error == "This license key has reached its activation limit of 3.")
        #expect(response.instance == nil)
        #expect(response.licenseKey?.activationLimit == 3)
    }

    @Test func unknownKey() async throws
    {
        let body = Fixture.body("activated", false, error: "This license key doesn't exist.", instance: false, key: false)
        let (client, _) = StubProtocol.client(.json(404, body))
        let response = try await client.activate(key: "NOPE", instanceName: "Mac")

        #expect(!response.success)
        #expect(response.statusCode == 404)
        #expect(response.licenseKey == nil)
        #expect(response.meta == nil)
    }

    @Test func validateValid() async throws
    {
        let (client, host) = StubProtocol.client(.json(200, Fixture.body("valid", true)))
        let response = try await client.validate(key: "7KQ2M-XW9PA-4TB8N-R2HDE", instanceID: "inst_1")

        #expect(response.success)
        #expect(response.instance?.name == "Ada's MacBook Pro")
        let request = try #require(StubProtocol.requests(host).first)
        #expect(request.path == "/api/v1/licenses/validate")
        #expect(request.body == ["license_key": "7KQ2M-XW9PA-4TB8N-R2HDE", "instance_id": "inst_1"])
    }

    @Test func validateDisabled() async throws
    {
        let body = Fixture.body("valid", false, error: "This license key has been disabled.").replacingOccurrences(of: "\"active\"", with: "\"disabled\"")
        let (client, _) = StubProtocol.client(.json(200, body))
        let response = try await client.validate(key: "7KQ2M-XW9PA-4TB8N-R2HDE", instanceID: "inst_1")

        #expect(!response.success)
        #expect(response.licenseKey?.status == .disabled)
        #expect(response.error == "This license key has been disabled.")
    }

    @Test func validateUnknownInstance() async throws
    {
        let body = Fixture.body("valid", false, error: "This instance isn't activated for this key.", instance: false)
        let (client, _) = StubProtocol.client(.json(404, body))
        let response = try await client.validate(key: "7KQ2M-XW9PA-4TB8N-R2HDE", instanceID: "inst_gone")

        #expect(!response.success)
        #expect(response.statusCode == 404)
        #expect(response.licenseKey != nil)
    }

    @Test func deactivate() async throws
    {
        let (client, host) = StubProtocol.client(.json(200, Fixture.body("deactivated", true, instance: false)))
        let response = try await client.deactivate(key: "7KQ2M-XW9PA-4TB8N-R2HDE", instanceID: "inst_1")

        #expect(response.success)
        let request = try #require(StubProtocol.requests(host).first)
        #expect(request.path == "/api/v1/licenses/deactivate")
        #expect(request.body == ["license_key": "7KQ2M-XW9PA-4TB8N-R2HDE", "instance_id": "inst_1"])
    }

    @Test func unknownStatusDecodes() async throws
    {
        let body = Fixture.body("valid", true).replacingOccurrences(of: "\"active\"", with: "\"paused\"")
        let (client, _) = StubProtocol.client(.json(200, body))
        let response = try await client.validate(key: "K")

        #expect(response.licenseKey?.status == .unknown)
    }

    @Test func networkErrorThrows() async
    {
        let (client, _) = StubProtocol.client(.fail(.notConnectedToInternet))
        await #expect(throws: PlumtierError.network(.notConnectedToInternet))
        {
            _ = try await client.validate(key: "K")
        }
    }

    @Test func nonAPIAnswerThrows() async
    {
        let (client, _) = StubProtocol.client(.json(502, "<html>Bad gateway</html>"))
        await #expect(throws: PlumtierError.invalidResponse(statusCode: 502))
        {
            _ = try await client.validate(key: "K")
        }
    }
}
