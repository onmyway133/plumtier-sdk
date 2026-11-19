import AppKit
import SwiftUI

/// The license screen: activate a key, see the license, buy, and free this Mac's seat.
///
/// Show it in a window (`PlumtierLicenseWindow`), a sheet (`.plumtierLicenseSheet`) or a tab in
/// your Settings.
public struct PlumtierLicenseView: View
{
    let license: PlumtierLicense

    public init(license: PlumtierLicense)
    {
        self.license = license
    }

    public var body: some View
    {
        VStack(alignment: .leading, spacing: 20)
        {
            LicenseHeader(license: license)
            if !license.isLicensed, license.trialStatus != .notOffered
            {
                TrialCard(status: license.trialStatus)
            }
            content
        }
        .padding(24)
        .frame(width: 460)
        .animation(.smooth(duration: 0.25), value: license.status)
        .onAppear
        {
            license.checkTrial()
        }
    }

    @ViewBuilder
    private var content: some View
    {
        switch license.status
        {
        case .checking:
            HStack(spacing: 10)
            {
                ProgressView().controlSize(.small)
                Text("Checking your license…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        case .licensed(let info):
            LicensedSection(license: license, info: info)
        case .invalid(let reason, _):
            NoticeCard(symbol: "exclamationmark.triangle.fill", tint: .orange, title: "License not valid", message: reason)
            ActivateSection(license: license)
        case .unreachable(let message):
            NoticeCard(symbol: "wifi.exclamationmark", tint: .orange, title: "Can't check your license", message: message)
            {
                Button("Try Again")
                {
                    Task { await license.refresh() }
                }
                .buttonStyle(.glass)
            }
            ActivateSection(license: license)
        case .unlicensed:
            ActivateSection(license: license)
        }
    }
}

// MARK: Header

struct LicenseHeader: View
{
    let license: PlumtierLicense

    var body: some View
    {
        HStack(spacing: 14)
        {
            Image(nsImage: NSApp?.applicationIconImage ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)!)
                .resizable()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3)
            {
                Text(license.displayName)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            StatusCapsule(title: badge.title, tint: badge.tint)
        }
    }

    private var subtitle: String
    {
        switch license.status
        {
        case .licensed(let info):
            let name = info.meta?.customerName ?? ""
            return name.isEmpty ? "Thank you for your support." : "Licensed to \(name)"
        case .checking:
            return "One moment."
        default:
            if case .active = license.trialStatus
            {
                return "Enjoy the full app during your trial."
            }
            return "Enter your license key to unlock everything."
        }
    }

    private var badge: (title: String, tint: Color)
    {
        switch license.status
        {
        case .licensed:
            return ("Licensed", .green)
        case .checking:
            return ("Checking", .secondary)
        case .invalid, .unreachable:
            return ("Needs Attention", .orange)
        case .unlicensed:
            switch license.trialStatus
            {
            case .active:
                return ("Trial", .blue)
            case .ended:
                return ("Trial Ended", .orange)
            case .notOffered:
                return ("Not Activated", .secondary)
            }
        }
    }
}

struct StatusCapsule: View
{
    let title: String
    let tint: Color

    var body: some View
    {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint == .secondary ? Color.secondary : tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background((tint == .secondary ? Color.gray : tint).opacity(0.15), in: .capsule)
    }
}

// MARK: Trial

struct TrialCard: View
{
    let status: TrialStatus

    var body: some View
    {
        switch status
        {
        case .active(let endsAt, let daysLeft):
            InfoRow(symbol: "hourglass", tint: .blue, title: daysLeft == 1 ? "Last day of your free trial" : "\(daysLeft) days left in your free trial", subtitle: "Ends \(endsAt.formatted(date: .abbreviated, time: .shortened))")
        case .ended:
            InfoRow(symbol: "hourglass.bottomhalf.filled", tint: .orange, title: "Your free trial has ended", subtitle: "Buy a license to keep using every feature.")
        case .notOffered:
            EmptyView()
        }
    }
}

// MARK: Activate

struct ActivateSection: View
{
    let license: PlumtierLicense
    @State private var key = ""
    @State private var error: String?
    @State private var working = false
    @FocusState private var focused: Bool

    var body: some View
    {
        VStack(alignment: .leading, spacing: 14)
        {
            VStack(alignment: .leading, spacing: 6)
            {
                Text("License key")
                    .font(.callout.weight(.medium))
                TextField("XXXXX-XXXXX-XXXXX-XXXXX", text: $key)
                    .textFieldStyle(.plain)
                    .font(.system(.title3, design: .monospaced))
                    .autocorrectionDisabled()
                    .focused($focused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.fill.tertiary, in: .rect(cornerRadius: 10))
                    .onChange(of: key)
                    { _, new in
                        // The store compares keys uppercased. Keep everything else as typed: imported
                        // keys can have any shape.
                        let upper = new.uppercased()
                        if upper != new
                        {
                            key = upper
                        }
                        error = nil
                    }
                    .onSubmit(activate)
                    .disabled(working)
                if let error
                {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .transition(.opacity)
                }
                else
                {
                    Text("You'll find it in your receipt email.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            GlassEffectContainer
            {
                HStack(spacing: 10)
                {
                    Button
                    {
                        license.openBuyPage()
                    }
                    label:
                    {
                        Label("Buy a License", systemImage: "cart")
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.glass)

                    Spacer()

                    Button(action: activate)
                    {
                        HStack(spacing: 6)
                        {
                            if working
                            {
                                ProgressView().controlSize(.small)
                            }
                            Text("Activate")
                        }
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(working || key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .controlSize(.large)
            }

            Button("Lost your key? Find it in your orders")
            {
                license.openPortal()
            }
            .buttonStyle(.link)
            .font(.callout)
        }
        .onAppear
        {
            focused = true
        }
    }

    private func activate()
    {
        guard !working else
        {
            return
        }
        working = true
        error = nil
        Task
        {
            do
            {
                try await license.activate(key: key)
                key = ""
            }
            catch
            {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}

// MARK: Licensed

struct LicensedSection: View
{
    let license: PlumtierLicense
    let info: LicenseInfo
    @State private var confirming = false
    @State private var working = false
    @State private var error: String?
    @State private var copied = false

    var body: some View
    {
        VStack(alignment: .leading, spacing: 16)
        {
            VStack(spacing: 8)
            {
                if let meta = info.meta, !(meta.customerName.isEmpty && meta.customerEmail.isEmpty)
                {
                    InfoRow(symbol: "person.fill", tint: .blue, title: meta.customerName.isEmpty ? meta.customerEmail : meta.customerName, subtitle: meta.customerName.isEmpty ? "Customer" : meta.customerEmail)
                }
                InfoRow(symbol: "shippingbox.fill", tint: .purple, title: productTitle, subtitle: productSubtitle)
                InfoRow(symbol: "laptopcomputer", tint: .teal, title: devicesTitle, subtitle: "This Mac is \(info.instance?.name ?? license.instanceName)")
                {
                    if let limit = info.key.activationLimit, limit > 0
                    {
                        Gauge(value: Double(min(info.key.activationUsage, limit)), in: 0...Double(limit)) {}
                            .gaugeStyle(.accessoryCircularCapacity)
                            .tint(info.key.activationUsage >= limit ? .orange : .teal)
                            .scaleEffect(0.6)
                            .frame(width: 34, height: 34)
                            .accessibilityLabel(devicesTitle)
                    }
                }
                InfoRow(symbol: "calendar", tint: .orange, title: expiryTitle, subtitle: info.key.createdAt.map { "Bought \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "")
                InfoRow(symbol: "key.fill", tint: .gray, title: masked(info.key.key), subtitle: "License key", monospaced: true)
                {
                    Button
                    {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(info.key.key, forType: .string)
                        copied = true
                        Task
                        {
                            try? await Task.sleep(for: .seconds(1.5))
                            copied = false
                        }
                    }
                    label:
                    {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.glass)
                    .help("Copy License Key")
                    .accessibilityLabel(copied ? "Copied" : "Copy License Key")
                }
            }

            if let error
            {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            GlassEffectContainer
            {
                HStack(spacing: 10)
                {
                    Button
                    {
                        license.openPortal()
                    }
                    label:
                    {
                        Label("Manage Devices", systemImage: "macbook.and.iphone")
                    }
                    .buttonStyle(.glass)

                    Spacer()

                    Button(role: .destructive)
                    {
                        confirming = true
                    }
                    label:
                    {
                        HStack(spacing: 6)
                        {
                            if working
                            {
                                ProgressView().controlSize(.small)
                            }
                            Text("Deactivate This Mac")
                        }
                    }
                    .buttonStyle(.glass)
                    .disabled(working)
                }
                .controlSize(.large)
            }
        }
        .confirmationDialog("Deactivate this Mac?", isPresented: $confirming)
        {
            Button("Deactivate", role: .destructive, action: deactivate)
        }
        message:
        {
            Text("This frees a seat on your license so you can use it on another Mac. You can activate this Mac again later with the same key.")
        }
    }

    private var productTitle: String
    {
        let name = info.meta?.productName ?? ""
        return name.isEmpty ? license.displayName : name
    }

    private var productSubtitle: String
    {
        var parts: [String] = []
        if let variant = info.meta?.variantName, !variant.isEmpty
        {
            parts.append(variant)
        }
        if let number = info.meta?.orderNumber
        {
            parts.append("Order #\(number)")
        }
        return parts.isEmpty ? "Product" : parts.joined(separator: " · ")
    }

    private var devicesTitle: String
    {
        let used = info.key.activationUsage
        guard let limit = info.key.activationLimit else
        {
            return used == 1 ? "1 Mac, no limit" : "\(used) Macs, no limit"
        }
        return "\(used) of \(limit) \(limit == 1 ? "Mac" : "Macs") in use"
    }

    private var expiryTitle: String
    {
        guard let expires = info.key.expiresAt else
        {
            return "Never expires"
        }
        return "Expires \(expires.formatted(date: .abbreviated, time: .omitted))"
    }

    private func masked(_ key: String) -> String
    {
        guard key.count > 5 else
        {
            return key
        }
        return String(repeating: "•", count: min(15, key.count - 5)) + key.suffix(5)
    }

    private func deactivate()
    {
        working = true
        error = nil
        Task
        {
            do
            {
                try await license.deactivate()
            }
            catch
            {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}

// MARK: Building blocks

/// A row with a tinted icon, a title over a subtitle, and an optional trailing accessory, on a
/// rounded card.
struct InfoRow<Accessory: View>: View
{
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    var monospaced = false
    @ViewBuilder var accessory: Accessory

    var body: some View
    {
        HStack(spacing: 12)
        {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.15), in: .rect(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2)
            {
                Text(title)
                    .font(monospaced ? .system(.body, design: .monospaced).weight(.medium) : .body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !subtitle.isEmpty
                {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            accessory
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.fill.quaternary, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

extension InfoRow where Accessory == EmptyView
{
    init(symbol: String, tint: Color, title: String, subtitle: String, monospaced: Bool = false)
    {
        self.init(symbol: symbol, tint: tint, title: title, subtitle: subtitle, monospaced: monospaced) { EmptyView() }
    }
}

/// A problem with what happened and, optionally, a way forward.
struct NoticeCard<Action: View>: View
{
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    @ViewBuilder var action: Action

    var body: some View
    {
        HStack(alignment: .top, spacing: 12)
        {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.15), in: .rect(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4)
            {
                Text(title).font(.body.weight(.semibold))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            action
        }
        .padding(12)
        .background(tint.opacity(0.08), in: .rect(cornerRadius: 12))
    }
}

extension NoticeCard where Action == EmptyView
{
    init(symbol: String, tint: Color, title: String, message: String)
    {
        self.init(symbol: symbol, tint: tint, title: title, message: message) { EmptyView() }
    }
}
