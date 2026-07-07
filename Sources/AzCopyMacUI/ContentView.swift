import AzCopyMacUICore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: Section = .transfer

    enum Section: String, CaseIterable, Identifiable {
        case transfer = "Transfer"
        case authentication = "Authentication"
        case jobs = "Jobs"
        case settings = "Settings"
        case logs = "Logs"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Text(section.rawValue)
            }
            .navigationTitle("AzCopy")
        } detail: {
            Group {
                switch selection {
                case .transfer:
                    TransferView()
                case .authentication:
                    AuthenticationView()
                case .jobs:
                    JobsView()
                case .settings:
                    SettingsView()
                case .logs:
                    LogsView()
                }
            }
            .padding()
        }
    }
}

struct TransferView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Picker("Action", selection: $model.selectedAction) {
                Text("Copy").tag(TransferAction.copy)
                Text("Sync").tag(TransferAction.sync)
                Text("List").tag(TransferAction.list)
                Text("Remove").tag(TransferAction.remove)
            }
            .onChange(of: model.selectedAction) { _, _ in model.refreshPreview() }

            TextField("Source path or URL", text: $model.source)
                .textFieldStyle(.roundedBorder)
                .onChange(of: model.source) { _, _ in model.refreshPreview() }

            TextField("Destination path or URL", text: $model.destination)
                .textFieldStyle(.roundedBorder)
                .disabled(model.selectedAction == .list || model.selectedAction == .remove)
                .onChange(of: model.destination) { _, _ in model.refreshPreview() }

            Toggle("Recursive", isOn: $model.recursive)
                .onChange(of: model.recursive) { _, _ in model.refreshPreview() }

            Toggle("Dry run", isOn: $model.dryRun)
                .onChange(of: model.dryRun) { _, _ in model.refreshPreview() }

            LabeledContent("Preview") {
                Text(model.commandPreview.isEmpty ? model.statusMessage : model.commandPreview)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }

            HStack {
                Button("Run") {}
                    .buttonStyle(.borderedProminent)
                    .disabled(model.commandPreview.isEmpty)
                    .accessibilityLabel("Run AzCopy command")
                Button("Cancel") {}
                    .disabled(true)
            }
        }
        .navigationTitle("Transfer")
    }
}

struct AuthenticationView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Picker("Authentication", selection: $model.selectedAuthentication) {
                ForEach(AuthenticationOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .onChange(of: model.selectedAuthentication) { _, _ in model.refreshPreview() }

            TextField("Tenant ID", text: $model.tenantID)
                .textFieldStyle(.roundedBorder)
                .onChange(of: model.tenantID) { _, _ in model.refreshPreview() }

            if [.servicePrincipalSecret, .servicePrincipalCertificate].contains(model.selectedAuthentication) {
                TextField("Application ID", text: $model.applicationID)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: model.applicationID) { _, _ in model.refreshPreview() }
                SecureField("Secret or certificate password", text: .constant(""))
                    .textFieldStyle(.roundedBorder)
            }

            if [.managedIdentityClientID, .managedIdentityObjectID, .managedIdentityResourceID].contains(model.selectedAuthentication) {
                TextField("Managed identity identifier", text: $model.managedIdentityID)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: model.managedIdentityID) { _, _ in model.refreshPreview() }
            }

            Text("Secrets are passed only to the current AzCopy process environment and are redacted from previews and logs.")
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Authentication")
    }
}

struct JobsView: View {
    var body: some View {
        ContentUnavailableView("Jobs", systemImage: "tray.full", description: Text("Job list, resume, and cleanup commands will use AzCopy job subcommands."))
            .navigationTitle("Jobs")
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            TextField("AzCopy executable", text: $model.azCopyPath)
                .textFieldStyle(.roundedBorder)
                .onChange(of: model.azCopyPath) { _, _ in model.refreshPreview() }
            Text("Default Apple Silicon Homebrew path: \(AzCopyLocator.homebrewAppleSiliconPath)")
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Settings")
    }
}

struct LogsView: View {
    var body: some View {
        ContentUnavailableView("Logs", systemImage: "doc.text.magnifyingglass", description: Text("AzCopy output will be streamed here with credentials redacted."))
            .navigationTitle("Logs")
    }
}

