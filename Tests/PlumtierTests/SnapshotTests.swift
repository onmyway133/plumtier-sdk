import AppKit
import SwiftUI
import Testing
@testable import Plumtier

/// Renders every license screen state to PNG files for a visual check. Runs only when
/// PLUMTIER_SNAPSHOT_DIR is set: `PLUMTIER_SNAPSHOT_DIR=/tmp/shots swift test --filter Snapshot`.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PLUMTIER_SNAPSHOT_DIR"] != nil))
struct SnapshotTests
{
    @Test func renderStates() throws
    {
        let folder = URL(filePath: ProcessInfo.processInfo.environment["PLUMTIER_SNAPSHOT_DIR"]!)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let states: [(String, PlumtierLicense)] = [
            ("unlicensed", .preview(.unlicensed)),
            ("trial", .preview(.unlicensed, trial: .active(endsAt: .now.addingTimeInterval(9 * 86_400), daysLeft: 9))),
            ("trial-ended", .preview(.unlicensed, trial: .ended(endsAt: .now))),
            ("licensed", .preview(.licensed(PlumtierLicense.previewInfo))),
            ("checking", .preview(.checking)),
            ("disabled", .preview(.invalid(reason: "This license key has been disabled.", info: PlumtierLicense.previewInfo))),
            ("offline", .preview(.unreachable(message: "You're offline. Connect to the internet and try again."))),
        ]
        for scheme in [ColorScheme.light, .dark]
        {
            for (name, license) in states
            {
                let view = PlumtierLicenseView(license: license)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try #require(renderer.nsImage)
                let tiff = try #require(image.tiffRepresentation)
                let rep = try #require(NSBitmapImageRep(data: tiff))
                let png = try #require(rep.representation(using: .png, properties: [:]))
                try png.write(to: folder.appending(path: "\(name)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }
}
