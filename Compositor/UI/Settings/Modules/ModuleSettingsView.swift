import SwiftUI

struct ModuleSettingsView: View {
    @Bindable var manager: ModuleManager

    var body: some View {
        Form {
            Section {
                Text("Optional resources for image editing. Downloads use the versions listed here.")
                    .foregroundStyle(.secondary)
                LabeledContent("Storage location") {
                    Text(verbatim: manager.root.path).textSelection(.enabled)
                        .accessibilityIdentifier("modulesStoragePath")
                }
            }
            ForEach(manager.descriptors) { descriptor in
                ModuleSettingsRow(manager: manager, descriptor: descriptor)
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("moduleSettings")
        .task { await manager.refresh() }
    }
}

private struct ModuleSettingsRow: View {
    @Bindable var manager: ModuleManager
    let descriptor: ModuleDescriptor
    @State private var confirmsUninstall = false

    private var state: ModuleState { manager.state(for: descriptor.id) }
    private var presentation: ModulePresentation { ModulePresentation(state: state) }

    var body: some View {
        Section {
            Text(L10n.text(descriptor.summary)).foregroundStyle(.secondary)
            LabeledContent("Status", value: L10n.text(presentation.status))
                .accessibilityIdentifier("moduleStatus-\(descriptor.id)")
            Toggle("Enabled", isOn: Binding(
                get: { state.isEnabled },
                set: { enabled in Task { await manager.setEnabled(enabled, for: descriptor.id) } }
            ))
            .disabled(!presentation.canToggle)
            .accessibilityIdentifier("moduleEnabled-\(descriptor.id)")
            LabeledContent("Version", value: descriptor.version)
            LabeledContent("Publisher", value: descriptor.publisher)
            LabeledContent("Download size", value: byteCount(descriptor.downloadBytes))
                .accessibilityIdentifier("moduleDownloadSize-\(descriptor.id)")
            LabeledContent("Installed size", value: state.isInstalled ? byteCount(state.installedBytes) : L10n.text("Not installed"))
                .accessibilityIdentifier("moduleInstalledSize-\(descriptor.id)")
            Text("Installed size counts source and compiled file contents, not allocated disk space.")
                .font(.caption).foregroundStyle(.secondary)
            if let provenance = state.provenance {
                Text(L10n.text(provenance == .verifiedDownload
                    ? "Verified source download"
                    : "Migrated compiled cache; source hashes not verified"))
                    .font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("moduleProvenance-\(descriptor.id)")
            }
            if presentation.canCancel || state.phase == .removing {
                progress
            }
            if let title = presentation.issueTitle {
                Text(L10n.text(title)).foregroundStyle(.orange)
                DisclosureGroup("Technical details") {
                    Text(verbatim: state.issue?.message ?? "").font(.caption).textSelection(.enabled)
                }
            }
            HStack {
                if presentation.canInstall {
                    Button(L10n.text(presentation.isRetry ? "Retry" : "Download")) {
                        Task { await manager.install(descriptor.id) }
                    }
                    .accessibilityIdentifier("moduleInstall-\(descriptor.id)")
                }
                if presentation.canCancel {
                    Button("Cancel") { manager.cancel(descriptor.id) }
                        .accessibilityIdentifier("moduleCancel-\(descriptor.id)")
                }
                if presentation.canUninstall {
                    Button("Uninstall…", role: .destructive) { confirmsUninstall = true }
                        .accessibilityIdentifier("moduleUninstall-\(descriptor.id)")
                }
            }
            DisclosureGroup("Source & Licenses") {
                LabeledContent("Module ID", value: descriptor.id)
                HStack {
                    Link("Source project", destination: descriptor.homepage)
                    Link("Release", destination: descriptor.releasePage)
                }
                LabeledContent("Download origin") {
                    Text(verbatim: descriptor.source.absoluteString).textSelection(.enabled)
                }
                ForEach(descriptor.attributions, id: \.name) { attribution in
                    HStack {
                        Link(attribution.name, destination: attribution.homepage)
                        Spacer()
                        Link(attribution.license, destination: attribution.licenseURL)
                    }
                }
                ForEach(descriptor.assets, id: \.path) { asset in
                    VStack(alignment: .leading, spacing: 4) {
                        Link(asset.name, destination: descriptor.source.appendingPathComponent(asset.name))
                        Text(verbatim: "SHA-256: \(asset.sha256)")
                            .font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }
        } header: {
            Text(verbatim: descriptor.name)
        }
        .alert(L10n.format("Uninstall %@?", descriptor.name), isPresented: $confirmsUninstall) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall", role: .destructive) {
                Task { await manager.uninstall(descriptor.id) }
            }
        } message: {
            Text("This removes the module’s managed files. Volumetric Light will use estimated depth, and depth extraction will be unavailable. Download manually to install it again.")
        }
    }

    @ViewBuilder private var progress: some View {
        if let fraction = presentation.downloadFraction {
            ProgressView(value: fraction)
                .accessibilityLabel(L10n.text(presentation.status))
                .accessibilityIdentifier("moduleProgress-\(descriptor.id)")
        } else {
            ProgressView().controlSize(.small)
                .accessibilityLabel(L10n.text(presentation.status))
                .accessibilityIdentifier("moduleProgress-\(descriptor.id)")
        }
        if state.phase == .downloading {
            if let total = state.totalBytes, total > 0 {
                Text(L10n.format("%@ of %@", byteCount(state.receivedBytes), byteCount(total)))
                    .font(.caption).monospacedDigit()
            } else {
                Text(L10n.format("%@ received", byteCount(state.receivedBytes)))
                    .font(.caption).monospacedDigit()
            }
        }
    }

    private func byteCount(_ bytes: Int64) -> String {
        L10n.format("%@ (%lld bytes)", ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file), bytes)
    }
}
