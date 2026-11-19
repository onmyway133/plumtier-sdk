# Plumtier SDK

SDKs for apps sold on a [Plumtier](https://plumtier.com) store. Plumtier is a self-hosted storefront
and checkout: you sell your app from your own store, and these SDKs let the app itself sell, check
and manage its license.

| SDK | Platforms | Folder |
|---|---|---|
| Swift | macOS 26 and later | repo root (`Package.swift`, `Sources/Plumtier`) |

More SDKs will live in this repo later.

## Swift SDK for Mac apps

With a few lines your Mac app can:

- open your store's product page so people can **buy** a license
- **activate** a license key on this Mac and **check** it at every launch
- **deactivate** this Mac (reset), to free its seat for another Mac
- send buyers to your store's portal to **manage their devices**
- offer an optional **free trial**, kept on this Mac and hard to reset
- show all of this in a ready **license window** with Liquid Glass, in light and dark mode

### Requirements

- macOS 26 or later, Swift 6.2 (Xcode 26) or later.
- A Plumtier store with your app as a product, **license keys turned on** and an **activation
  limit** (the number of Macs one key can be used on). The product's link is the last part of its
  page address: for `https://store.example.com/p/my-app` the link is `my-app`.
- Sandboxed apps need the **Outgoing Connections (Client)** capability
  (`com.apple.security.network.client`) to reach the store.

### Install

In Xcode, choose **File > Add Package Dependencies** and enter:

```
https://github.com/onmyway133/plumtier-sdk
```

Or in `Package.swift`:

```swift
.package(url: "https://github.com/onmyway133/plumtier-sdk", branch: "main")
```

The repo is private for now, so Xcode needs a GitHub account with access (**Xcode > Settings >
Accounts**).

### Set up

Create one `PlumtierLicense` when the app starts and keep it for the life of the app. It reads the
saved key from the Keychain and checks it with your store right away.

```swift
import Plumtier
import SwiftUI

@main
struct MyApp: App
{
    @State private var license = PlumtierLicense(
        store: URL(string: "https://store.example.com")!,
        product: "my-app",
        trial: .days(14) // optional, leave it out for no trial
    )

    var body: some Scene
    {
        WindowGroup
        {
            ContentView()
                .environment(license)
        }

        PlumtierLicenseWindow(license: license)
    }
}
```

| Parameter | What it does |
|---|---|
| `store` | Your store's address. |
| `product` | The product's link (or its id). Keys for other products are refused. |
| `displayName` | The name at the top of the license window. Defaults to your app's name. |
| `trial` | A free trial from the first launch, for example `.days(14)`. `nil` (the default) means no trial. |

### Unlock paid features

`PlumtierLicense` is `@Observable`, so views update by themselves when the license changes.

```swift
struct ContentView: View
{
    @Environment(PlumtierLicense.self) private var license
    @Environment(\.openWindow) private var openWindow

    var body: some View
    {
        if license.isUnlocked
        {
            ProFeatureView()
        }
        else
        {
            Button("Unlock Pro")
            {
                openWindow(id: PlumtierLicenseWindow.id)
            }
        }
    }
}
```

- `isUnlocked`: licensed, or in the free trial. Use this to gate features.
- `isLicensed`: the store confirmed a key on this Mac. The trial doesn't count.

### Show the license window

The license window handles every case for you: entering a key, the trial countdown, the license
details (customer, product, Macs in use, expiry, key), buying, managing devices and deactivating.

As its own window, opened from a menu command or a button:

```swift
// In your App's body
PlumtierLicenseWindow(license: license)

// In a Commands or a view
@Environment(\.openWindow) private var openWindow
openWindow(id: PlumtierLicenseWindow.id)
```

A ready menu command, placed under **About** in the app menu:

```swift
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
```

As a sheet:

```swift
@State private var showLicense = false

SomeView()
    .plumtierLicenseSheet(isPresented: $showLicense, license: license)
```

Or as a tab in your Settings:

```swift
Settings
{
    TabView
    {
        GeneralSettings()
            .tabItem { Label("General", systemImage: "gear") }
        PlumtierLicenseView(license: license)
            .tabItem { Label("License", systemImage: "key") }
    }
}
```

### Build your own screen

Everything the window does is available on `PlumtierLicense`:

```swift
// Activate a key on this Mac. Throws LicenseActionError with a message to show.
try await license.activate(key: "7KQ2M-XW9PA-4TB8N-R2HDE")

// Check the saved key with the store again. Done for you at launch.
await license.refresh()

// Free this Mac's seat and remove the key from this Mac (reset).
try await license.deactivate()

// Open the product page, optionally with a variant, a discount code or an affiliate.
license.openBuyPage()
license.openBuyPage(variant: "var_123", code: "LAUNCH")
let url = license.buyURL()

// Open the customer portal, where buyers find their keys and remove other Macs.
license.openPortal()
```

`license.status` tells you where the license stands:

| Status | Meaning |
|---|---|
| `.unlicensed` | No key on this Mac. |
| `.checking` | Asking the store. |
| `.licensed(info)` | The store confirmed the key on this Mac. `info` has the key, this Mac's activation and the order details. |
| `.invalid(reason, info)` | The store refused the key: disabled (for example after a refund), expired, for another product, or this Mac was removed from it. `reason` is ready to show. |
| `.unreachable(message)` | The store couldn't be reached. Counts as not licensed. |

`license.trialStatus` is `.notOffered`, `.active(endsAt, daysLeft)` or `.ended(endsAt)`.

### How checking works

- The key and this Mac's activation id are kept in the Keychain.
- The license is checked with the store **at every launch**, and whenever you call `refresh()`.
  There is no offline grace: when the store can't be reached, the status is `.unreachable` and
  `isLicensed` is false until a check succeeds. Offer a free trial if you want people to keep
  working offline at first.
- When a buyer removes this Mac in the portal, or the seller deletes the key, the next check forgets
  the key and asks for it again.
- When a key is disabled or expires, the key stays on this Mac and the window explains why. If the
  seller turns it back on, or a renewal extends it, the next check unlocks the app again.
- Deactivating frees the seat on the store first, then removes the key from this Mac. If the store
  can't be reached, nothing is removed and the window shows the error.

### Free trial

Pass `trial: .days(n)` to offer a trial. It starts the first time the app runs with the SDK and
needs no account or network.

To make it hard to reset, the SDK:

- signs the trial record with a key tied to your store, your product and this Mac's hardware, so an
  edited record, or one copied from another Mac, ends the trial
- keeps copies in the Keychain, in Application Support and in user defaults: deleting the app,
  its preferences or its container doesn't restart the trial, because any copy left over still
  counts and missing copies are written again
- watches the clock: moving the date back by more than an hour ends the trial

A trial kept only on the Mac can't be made impossible to cheat. Someone who finds and deletes
every copy, or patches your app, can still get around it. It stops the easy tricks, which is what
matters for most apps.

### Use the API directly

For your own flows, `PlumtierClient` calls the store's license API (`/api/v1/licenses/activate`,
`/validate` and `/deactivate`) without any storage or UI:

```swift
let client = PlumtierClient(store: URL(string: "https://store.example.com")!)

let response = try await client.activate(key: key, instanceName: "Ada's MacBook Pro", product: "my-app")
if response.success, let instance = response.instance
{
    // Keep instance.id to validate and deactivate this Mac later.
}
else
{
    print(response.error ?? "Not activated")
}

let check = try await client.validate(key: key, instanceID: instanceID, product: "my-app")
let done = try await client.deactivate(key: key, instanceID: instanceID)
```

Every call returns a `LicenseResponse` when the store answers, including refusals such as an
unknown key or a full activation limit; check `success` and `error`. Calls throw a `PlumtierError`
only when there is no usable answer (offline, timeout, or something that isn't the license API).

### Example app

`Example/` is a small Mac app that gates a feature, offers a 14 day trial and has a **License…**
menu command. Set your store and product link at the top of
`Example/Sources/PlumtierExample/ExampleApp.swift`, then:

```sh
cd Example
swift run
```

Pass `--show-license` to open the license window at launch.

### Develop

```sh
swift build
swift test
```

To look at every state of the license window in light and dark mode:

```sh
PLUMTIER_SNAPSHOT_DIR=/tmp/plumtier-shots swift test --filter Snapshot
```

In Xcode, the `#Preview`s in `Sources/Plumtier/UI/Previews.swift` show the same states.

## License

MIT. See [LICENSE](LICENSE).
