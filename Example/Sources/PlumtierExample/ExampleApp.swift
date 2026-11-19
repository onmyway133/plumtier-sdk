import AppKit
import Plumtier
import SwiftUI

// Change these to your store and your product's link (https://your-store/p/<link>).
let storeURL = URL(string: "https://store.example.com")!
let productLink = "my-app"

@main
struct ExampleApp: App
{
    @State private var license = PlumtierLicense(store: storeURL, product: productLink, trial: .days(14))

    init()
    {
        // `swift run` starts a plain process; make it a regular app with a Dock icon.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    var body: some Scene
    {
        WindowGroup("Plumtier Example")
        {
            ContentView(license: license)
        }
        .windowResizability(.contentSize)
        .commands
        {
            LicenseCommands()
        }

        PlumtierLicenseWindow(license: license)
    }
}

struct LicenseCommands: Commands
{
    @Environment(\.openWindow) private var openWindow

    var body: some Commands
    {
        CommandGroup(after: .appInfo)
        {
            Button("License…")
            {
                openWindow(id: PlumtierLicenseWindow.id)
            }
        }
    }
}

struct ContentView: View
{
    let license: PlumtierLicense
    @Environment(\.openWindow) private var openWindow

    var body: some View
    {
        VStack(spacing: 16)
        {
            Image(systemName: license.isUnlocked ? "sparkles" : "lock.fill")
                .font(.system(size: 40))
                .foregroundStyle(license.isUnlocked ? Color.accentColor : .secondary)
                .contentTransition(.symbolEffect(.replace))
            Text(license.isUnlocked ? "Pro features are on" : "Pro features are locked")
                .font(.title2.weight(.semibold))
            Text(caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(license.isLicensed ? "View License" : "Activate or Buy")
            {
                openWindow(id: PlumtierLicenseWindow.id)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding(40)
        .frame(width: 420)
        .onAppear
        {
            if ProcessInfo.processInfo.arguments.contains("--show-license")
            {
                openWindow(id: PlumtierLicenseWindow.id)
            }
        }
    }

    private var caption: String
    {
        if license.isLicensed
        {
            return "Thanks for buying."
        }
        if case .active(_, let daysLeft) = license.trialStatus
        {
            return "\(daysLeft) days left in your free trial."
        }
        return "Activate a license key to use them."
    }
}
