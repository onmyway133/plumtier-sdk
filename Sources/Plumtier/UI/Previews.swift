import SwiftUI

#if DEBUG
extension PlumtierLicense
{
    /// A license that never calls a store, for previews.
    static func preview(_ status: LicenseStatus, trial: TrialStatus = .notOffered) -> PlumtierLicense
    {
        let store = URL(string: "https://store.example.com")!
        let license = PlumtierLicense(store: store, product: "clipboard-pro", displayName: "Clipboard Pro", client: PlumtierClient(store: store), keychain: MemoryStore(), instanceName: "Ada's MacBook Pro", checkNow: false)
        license.status = status
        license.trialStatus = trial
        return license
    }

    static let previewInfo = LicenseInfo(
        key: LicenseKey(id: "lic_1", status: .active, key: "7KQ2M-XW9PA-4TB8N-R2HDE", activationLimit: 3, activationUsage: 2, createdAt: Date(timeIntervalSince1970: 1_761_991_200), expiresAt: nil),
        instance: LicenseInstance(id: "inst_1", name: "Ada's MacBook Pro", createdAt: nil),
        meta: LicenseMeta(orderNumber: 1042, productName: "Clipboard Pro", variantName: "3 Macs", customerName: "Ada Lovelace", customerEmail: "ada@example.com")
    )
}

#Preview("Not activated")
{
    PlumtierLicenseView(license: .preview(.unlicensed))
}

#Preview("Trial")
{
    PlumtierLicenseView(license: .preview(.unlicensed, trial: .active(endsAt: .now.addingTimeInterval(9 * 86_400), daysLeft: 9)))
}

#Preview("Trial ended")
{
    PlumtierLicenseView(license: .preview(.unlicensed, trial: .ended(endsAt: .now)))
}

#Preview("Licensed")
{
    PlumtierLicenseView(license: .preview(.licensed(PlumtierLicense.previewInfo)))
}

#Preview("Checking")
{
    PlumtierLicenseView(license: .preview(.checking))
}

#Preview("Disabled")
{
    PlumtierLicenseView(license: .preview(.invalid(reason: "This license key has been disabled.", info: PlumtierLicense.previewInfo)))
}

#Preview("Offline")
{
    PlumtierLicenseView(license: .preview(.unreachable(message: "You're offline. Connect to the internet and try again.")))
}
#endif
