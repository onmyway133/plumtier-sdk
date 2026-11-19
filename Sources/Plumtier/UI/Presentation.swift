import SwiftUI

/// A window with the license screen. Add it to your `App` and open it with
/// `openWindow(id: PlumtierLicenseWindow.id)`.
public struct PlumtierLicenseWindow: Scene
{
    public static let id = "plumtier-license"

    let license: PlumtierLicense
    let title: String

    public init(license: PlumtierLicense, title: String = "License")
    {
        self.license = license
        self.title = title
    }

    public var body: some Scene
    {
        Window(title, id: Self.id)
        {
            PlumtierLicenseView(license: license)
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
    }
}

extension View
{
    /// Shows the license screen in a sheet with a Done button.
    public func plumtierLicenseSheet(isPresented: Binding<Bool>, license: PlumtierLicense) -> some View
    {
        sheet(isPresented: isPresented)
        {
            LicenseSheet(license: license)
        }
    }
}

struct LicenseSheet: View
{
    let license: PlumtierLicense
    @Environment(\.dismiss) private var dismiss

    var body: some View
    {
        PlumtierLicenseView(license: license)
            .toolbar
            {
                ToolbarItem(placement: .confirmationAction)
                {
                    Button("Done") { dismiss() }
                }
            }
    }
}
