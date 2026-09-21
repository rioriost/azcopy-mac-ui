import AzCopyMacUICore
import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: Section? = .operations

    enum Section: String, CaseIterable, Identifiable {
        case operations = "Operations"
        case settings = "Settings"
        case logs = "Logs"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .operations:
                "arrow.left.arrow.right"
            case .settings:
                "gearshape"
            case .logs:
                "doc.text.magnifyingglass"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                NavigationLink(value: section) {
                    Label(section.rawValue, systemImage: section.systemImage)
                }
            }
            .navigationTitle("AzCopy")
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 260)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                if !model.settingsNotice.isEmpty {
                    Label(model.settingsNotice, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .padding()
                }
                ExecutionStatusView()
                    .padding()
                Divider()
                Group {
                    switch selection ?? .operations {
                    case .operations:
                        OperationsView()
                    case .settings:
                        SettingsView()
                    case .logs:
                        LogsView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct ExecutionStatusView: View {
    @EnvironmentObject private var model: AppModel

    private var statusSymbol: String {
        switch model.executionState {
        case .idle: "circle.dotted"
        case .running: "arrow.triangle.2.circlepath"
        case .succeeded: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        case .cancelled: "stop.circle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(model.statusMessage, systemImage: statusSymbol)
                    .font(.headline)
                    .textSelection(.enabled)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(model.statusMessage)
                    .accessibilityAddTraits(.isStaticText)
                Spacer()
                if model.isRunning {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("AzCopy is running")
                    Button("Cancel", action: model.cancelCommand)
                        .keyboardShortcut(.cancelAction)
                }
            }
            if model.isRunning {
                Text(model.activeCommandPreview)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                ScrollView {
                    Text(String(model.logText.suffix(4000)))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 100)
            }
        }
    }
}

// Let the native form allocate space and wrap labels as the window changes size.
private struct FormRow<Content: View>: View {
    let title: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        if let title, !title.isEmpty {
            LabeledContent {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .labeledContentStyle(AlignedFormRowStyle())
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AlignedFormRowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            configuration.label
                .frame(width: 170, alignment: .leading)
            configuration.content
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
    }
}

private struct FormSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        SwiftUI.Section(title, content: content)
    }
}

private struct TextInputRow: View {
    let title: String
    let prompt: String
    @Binding var text: String
    var disabled = false
    var onChange: () -> Void

    var body: some View {
        FormRow(title: title) {
            TextField(title, text: $text, prompt: Text(prompt))
                .labelsHidden()
                .accessibilityLabel(title)
                .textFieldStyle(.roundedBorder)
                .disabled(disabled)
                .onChange(of: text) { _, _ in onChange() }
        }
    }
}

private struct SecureInputRow: View {
    let title: String
    let prompt: String
    @Binding var text: String
    var onChange: () -> Void = {}

    var body: some View {
        FormRow(title: title) {
            SecureField(title, text: $text, prompt: Text(prompt))
                .labelsHidden()
                .accessibilityLabel(title)
                .textFieldStyle(.roundedBorder)
                .onChange(of: text) { _, _ in onChange() }
        }
    }
}

private struct FileInputRow: View {
    let title: String
    let prompt: String
    let buttonHelp: String
    @Binding var text: String
    var disabled = false
    var onChoose: () -> Void
    var onChange: () -> Void

    var body: some View {
        FormRow(title: title) {
            HStack(spacing: 8) {
                TextField(title, text: $text, prompt: Text(prompt))
                .labelsHidden()
                .accessibilityLabel(title)
                    .textFieldStyle(.roundedBorder)
                    .disabled(disabled)
                    .onChange(of: text) { _, _ in onChange() }
                Button(action: onChoose) {
                    Image(systemName: "folder")
                }
                .disabled(disabled)
                .help(buttonHelp)
                .accessibilityLabel(buttonHelp)
            }
        }
    }
}

private enum CommandCategory: String, CaseIterable, Identifiable {
    case transfer = "Transfer"
    case benchmark = "Benchmark"
    case storage = "Storage"
    case jobs = "Jobs"
    case session = "Session"
    case environment = "Environment"

    var id: String { rawValue }
}

private extension TransferAction {
    var title: String {
        switch self {
        case .copy: "Copy"
        case .sync: "Sync"
        case .list: "List"
        case .remove: "Remove"
        case .bench: "Bench"
        case .make: "Make container/share"
        case .setProperties: "Set properties"
        case .env: "Environment"
        case .jobsList: "List"
        case .jobsShow: "Show"
        case .jobsResume: "Resume"
        case .jobsRemove: "Remove"
        case .jobsClean: "Clean"
        case .loginStatus: "Login status"
        case .logout: "Logout"
        }
    }

    var category: CommandCategory {
        switch self {
        case .copy, .sync, .list, .remove:
            .transfer
        case .bench:
            .benchmark
        case .make, .setProperties:
            .storage
        case .jobsList, .jobsShow, .jobsResume, .jobsRemove, .jobsClean:
            .jobs
        case .loginStatus, .logout:
            .session
        case .env:
            .environment
        }
    }

    var needsSource: Bool {
        switch self {
        case .copy, .sync, .list, .remove, .bench, .make, .setProperties:
            true
        default:
            false
        }
    }

    var needsDestination: Bool {
        self == .copy || self == .sync
    }

    var needsJobID: Bool {
        switch self {
        case .jobsShow, .jobsResume, .jobsRemove:
            true
        default:
            false
        }
    }

    var hasStandardOptions: Bool {
        supportsRecursive ||
            supportsDryRun ||
            supportsCapMbps ||
            supportsPatternFlags ||
            self == .copy ||
            self == .sync
    }

    var sourceTitle: String {
        switch self {
        case .bench:
            "Benchmark target URL"
        case .make:
            "Resource URL"
        case .setProperties:
            "Resource path or URL"
        case .list:
            "Resource URL"
        case .remove:
            "Resource path or URL"
        default:
            "Source path or URL"
        }
    }

    var sourcePrompt: String {
        switch self {
        case .bench:
            "https://account.blob.core.windows.net/container?[SAS]"
        case .make:
            "https://account.blob.core.windows.net/container"
        case .setProperties:
            "https://account.blob.core.windows.net/container/path"
        case .list:
            "https://account.blob.core.windows.net/container"
        case .remove:
            "https://account.blob.core.windows.net/container/blob"
        default:
            "/Users/you/Documents or https://account.blob.core.windows.net/container"
        }
    }

    static func actions(in category: CommandCategory) -> [TransferAction] {
        allCases.filter { $0.category == category }
    }
}

struct OperationsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var category: CommandCategory = .transfer

    var body: some View {
        Form {
            FormSection("Operation") {
                FormRow(title: "Category") {
                    Picker("Category", selection: $category) {
                        ForEach(CommandCategory.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize(horizontal: true, vertical: false)
                }
                .onChange(of: category) { _, newCategory in
                    let actions = TransferAction.actions(in: newCategory)
                    if !actions.contains(model.selectedAction), let firstAction = actions.first {
                        model.selectedAction = firstAction
                        model.refreshPreview()
                    }
                }

                FormRow(title: "Command") {
                    Picker("Command", selection: $model.selectedAction) {
                        ForEach(TransferAction.actions(in: category), id: \.self) { action in
                            Text(action.title).tag(action)
                        }
                    }
                    .labelsHidden()
                    .fixedSize(horizontal: true, vertical: false)
                }
                .onChange(of: model.selectedAction) { _, newAction in
                    category = newAction.category
                    model.refreshPreview()
                }

                if model.selectedAction.needsSource {
                    if [.copy, .sync].contains(model.selectedAction) {
                        FileInputRow(
                            title: model.selectedAction.sourceTitle,
                            prompt: model.selectedAction.sourcePrompt,
                            buttonHelp: "Choose local source path",
                            text: $model.source,
                            onChoose: {
                                choosePath(title: "Choose Source", binding: $model.source)
                            },
                            onChange: model.refreshPreview
                        )
                    } else {
                        TextInputRow(
                            title: model.selectedAction.sourceTitle,
                            prompt: model.selectedAction.sourcePrompt,
                            text: $model.source,
                            onChange: model.refreshPreview
                        )
                    }
                }

                if model.selectedAction.needsDestination {
                    FileInputRow(
                        title: "Destination path or URL",
                        prompt: "/Users/you/Downloads or https://account.blob.core.windows.net/container",
                        buttonHelp: "Choose local destination path",
                        text: $model.destination,
                        onChoose: {
                            choosePath(title: "Choose Destination", binding: $model.destination)
                        },
                        onChange: model.refreshPreview
                    )
                }

                if model.selectedAction.needsJobID {
                    TextInputRow(title: "Job ID", prompt: "00000000-0000-0000-0000-000000000000", text: $model.jobID, onChange: model.refreshPreview)
                }

            }

            if model.selectedAction == .bench {
                FormSection("Benchmark") {
                    FormRow(title: "Mode") {
                        Picker("Mode", selection: $model.benchMode) {
                            Text("Upload").tag("upload")
                            Text("Download").tag("download")
                        }
                        .labelsHidden()
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .onChange(of: model.benchMode) { _, _ in model.refreshPreview() }

                    TextInputRow(title: "File count", prompt: "100", text: $model.benchFileCount, onChange: model.refreshPreview)
                    TextInputRow(title: "Size per file", prompt: "250M", text: $model.benchSizePerFile, onChange: model.refreshPreview)
                    TextInputRow(title: "Number of folders", prompt: "5", text: $model.benchNumberOfFolders, onChange: model.refreshPreview)
                    FormRow(title: nil) {
                        Toggle("Delete test data", isOn: $model.benchDeleteTestData)
                            .onChange(of: model.benchDeleteTestData) { _, _ in model.refreshPreview() }
                    }
                    FormRow(title: nil) {
                        Toggle("Put MD5", isOn: $model.benchPutMD5)
                            .onChange(of: model.benchPutMD5) { _, _ in model.refreshPreview() }
                    }
                    FormRow(title: nil) {
                        Toggle("Check length", isOn: $model.benchCheckLength)
                            .onChange(of: model.benchCheckLength) { _, _ in model.refreshPreview() }
                    }
                }
            }

            if model.selectedAction == .make {
                FormSection("Storage") {
                    TextInputRow(title: "Quota GB", prompt: "100", text: $model.makeQuotaGB, onChange: model.refreshPreview)
                }
            }

            if model.selectedAction == .setProperties {
                FormSection("Properties") {
                    FormRow(title: "Block blob tier") {
                        Picker("Block blob tier", selection: $model.blockBlobTier) {
                            ForEach(["None", "Hot", "Cool", "Cold", "Archive"], id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .onChange(of: model.blockBlobTier) { _, _ in model.refreshPreview() }

                    FormRow(title: "Page blob tier") {
                        Picker("Page blob tier", selection: $model.pageBlobTier) {
                            ForEach(["None", "P4", "P6", "P10", "P15", "P20", "P30", "P40", "P50"], id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .onChange(of: model.pageBlobTier) { _, _ in model.refreshPreview() }

                    FormRow(title: "Rehydrate priority") {
                        Picker("Rehydrate priority", selection: $model.rehydratePriority) {
                            ForEach(["Standard", "High"], id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .onChange(of: model.rehydratePriority) { _, _ in model.refreshPreview() }

                    TextInputRow(title: "Metadata", prompt: "key=value;owner=team", text: $model.metadata, onChange: model.refreshPreview)
                    TextInputRow(title: "Blob tags", prompt: "key=value&project=demo", text: $model.blobTags, onChange: model.refreshPreview)
                    TextInputRow(title: "Include pattern", prompt: "*.jpg;*.png", text: $model.includePattern, onChange: model.refreshPreview)
                    TextInputRow(title: "Exclude pattern", prompt: "*.tmp;*.log", text: $model.excludePattern, onChange: model.refreshPreview)
                    TextInputRow(title: "Include path", prompt: "folder/file.txt;other/path", text: $model.includePath, onChange: model.refreshPreview)
                    TextInputRow(title: "Exclude path", prompt: "tmp;archive/old", text: $model.excludePath, onChange: model.refreshPreview)
                    TextInputRow(title: "List of files", prompt: "/Users/you/files.txt", text: $model.listOfFiles, onChange: model.refreshPreview)
                }
            }

            if model.selectedAction == .jobsShow {
                FormSection("Job filters") {
                    FormRow(title: "Transfer status") {
                        Picker("Transfer status", selection: $model.jobTransferStatus) {
                            Text("Any").tag("")
                            ForEach(["All", "Started", "Success", "Failed"], id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .onChange(of: model.jobTransferStatus) { _, _ in model.refreshPreview() }
                }
            }

            if model.selectedAction == .jobsResume {
                FormSection("Resume filters") {
                    SecureInputRow(title: "Source SAS", prompt: "sv=...&sig=...", text: $model.sourceSAS)
                    SecureInputRow(title: "Destination SAS", prompt: "sv=...&sig=...", text: $model.destinationSAS)
                    TextInputRow(title: "Include failed transfers", prompt: "path1;path2", text: $model.includePath, onChange: model.refreshPreview)
                    TextInputRow(title: "Exclude failed transfers", prompt: "path1;path2", text: $model.excludePath, onChange: model.refreshPreview)
                }
                .onChange(of: model.sourceSAS) { _, _ in model.refreshPreview() }
                .onChange(of: model.destinationSAS) { _, _ in model.refreshPreview() }
            }

            if model.selectedAction == .env {
                FormRow(title: nil) {
                    Toggle("Show sensitive variables", isOn: $model.showSensitiveEnvironment)
                        .onChange(of: model.showSensitiveEnvironment) { _, _ in model.refreshPreview() }
                }
            }

            if model.selectedAction.hasStandardOptions {
                FormSection("Options") {
                    if model.selectedAction.supportsRecursive {
                        FormRow(title: nil) {
                            Toggle("Recursive", isOn: $model.recursive)
                                .onChange(of: model.recursive) { _, _ in model.refreshPreview() }
                        }
                    }

                    if model.selectedAction.supportsDryRun {
                        FormRow(title: nil) {
                            Toggle("Dry run", isOn: $model.dryRun)
                                .onChange(of: model.dryRun) { _, _ in model.refreshPreview() }
                        }
                    }

                    if model.selectedAction == .copy {
                        FormRow(title: nil) {
                            Toggle("Overwrite existing files", isOn: $model.overwriteExisting)
                                .onChange(of: model.overwriteExisting) { _, _ in model.refreshPreview() }
                        }
                    }

                    if model.selectedAction == .sync {
                        FormRow(title: nil) {
                            Toggle("Delete destination extras", isOn: $model.deleteDestination)
                                .onChange(of: model.deleteDestination) { _, _ in model.refreshPreview() }
                        }
                    }

                    if model.selectedAction.supportsCapMbps {
                        TextInputRow(title: "Cap Mbps", prompt: "100", text: $model.capMbps, onChange: model.refreshPreview)
                    }

                    if model.selectedAction.supportsPatternFlags, model.selectedAction != .setProperties {
                        TextInputRow(title: "Include pattern", prompt: "*.jpg;*.png", text: $model.includePattern, onChange: model.refreshPreview)

                        TextInputRow(title: "Exclude pattern", prompt: "*.tmp;*.log", text: $model.excludePattern, onChange: model.refreshPreview)
                    }
                }
            }

        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            commandFooter
        }
        .navigationTitle("Operations")
        .focusedSceneValue(\.azCopyCommand, AzCopyCommandAction(
            title: runTitle,
            isEnabled: !model.commandPreview.isEmpty && !model.isRunning && model.pendingCommand == nil,
            perform: model.runSelectedCommand
        ))
        .onAppear {
            category = model.selectedAction.category
        }
        .alert("Confirm destructive operation", isPresented: Binding(
            get: { model.pendingCommand != nil },
            set: { if !$0 { model.pendingCommand = nil } }
        ), presenting: model.pendingCommand) { command in
            Button("Run", role: .destructive) {
                model.confirmPendingCommand(command)
            }
            Button("Cancel", role: .cancel) {
                model.pendingCommand = nil
            }
        } message: { command in
            Text("This operation can permanently delete data. Confirm the exact command below. Changes to the form will not change this command.\n\n\(command.preview)")
        }
    }

    private var runTitle: String {
        model.dryRun && model.selectedAction.supportsDryRun
            ? "Preview \(model.selectedAction.title)"
            : model.selectedAction.title
    }

    private var commandFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Command preview")
                    .font(.headline)
                Spacer()
                Button(action: copyPreviewToClipboard) {
                    Label("Copy command", systemImage: "doc.on.doc")
                }
                .disabled(model.commandPreview.isEmpty)
                .help("Copy the command with credentials redacted")
            }
            if model.commandPreview.isEmpty {
                Label(model.validationMessage, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    Text(model.commandPreview)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Command preview: \(model.commandPreview)")
                }
                .frame(height: 64)
            }
            HStack {
                if model.dryRun && model.selectedAction.supportsDryRun {
                    Label("Dry run — no files will be changed", systemImage: "eye")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(runTitle, action: model.runSelectedCommand)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.commandPreview.isEmpty || model.isRunning || model.pendingCommand != nil)
                    .help("Run the selected command (⌘Return)")
            }
        }
        .padding()
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func choosePath(title: String, binding: Binding<String>) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            binding.wrappedValue = url.path
            model.refreshPreview()
        }
    }

    private func copyPreviewToClipboard() {
        guard !model.commandPreview.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(model.commandPreview, forType: .string)
    }
}

struct AuthenticationSettingsSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        FormSection("Authentication") {
            FormRow(title: "Authentication") {
                Picker("Authentication", selection: $model.selectedAuthentication) {
                    ForEach(AuthenticationOption.allCases) { option in
                        Text(option.title).tag(option)
                            .disabled(option == .managedIdentityObjectID)
                    }
                }
                .labelsHidden()
            }
            .onChange(of: model.selectedAuthentication) { _, _ in model.refreshPreview() }

            FormRow(title: "Tenant ID") {
                HStack(spacing: 8) {
                    if model.tenantOptions.isEmpty {
                        TextField("Tenant ID", text: $model.tenantID, prompt: Text("Enter a tenant ID"))
                            .labelsHidden()
                            .accessibilityLabel("Tenant ID")
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: model.tenantID) { _, _ in model.refreshPreview() }
                    } else {
                        Picker("Tenant ID", selection: $model.tenantID) {
                            Text("None").tag("")
                            ForEach(model.tenantOptions) { tenant in
                                Text(tenant.title).tag(tenant.id)
                            }
                        }
                        .labelsHidden()
                        .onChange(of: model.tenantID) { _, _ in model.refreshPreview() }
                    }

                    Button {
                        model.loadTenants()
                    } label: {
                        Label("Load tenants", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isLoadingTenants)
                    .help("Load tenants from Azure CLI")
                    .accessibilityLabel("Load tenants from Azure CLI")
                }
            }

            if !model.tenantLoadMessage.isEmpty {
                FormRow(title: nil) {
                    Text(model.tenantLoadMessage)
                        .foregroundStyle(.secondary)
                    if model.isLoadingTenants {
                        Button("Cancel lookup", action: model.cancelTenantLookup)
                    }
                }
            }

            if [.servicePrincipalSecret, .servicePrincipalCertificate].contains(model.selectedAuthentication) {
                TextInputRow(
                    title: "Application ID",
                    prompt: "00000000-0000-0000-0000-000000000000",
                    text: $model.applicationID,
                    onChange: model.refreshPreview
                )
            }

            if model.selectedAuthentication == .servicePrincipalSecret {
                SecureInputRow(
                    title: "Client secret",
                    prompt: "Client secret value",
                    text: $model.servicePrincipalSecret,
                    onChange: model.refreshPreview
                )
            }

            if model.selectedAuthentication == .servicePrincipalCertificate {
                FileInputRow(
                    title: "Certificate path",
                    prompt: "/Users/you/certs/service-principal.pem",
                    buttonHelp: "Choose service principal certificate",
                    text: $model.certificatePath,
                    onChoose: {
                        chooseCertificatePath()
                    },
                    onChange: model.refreshPreview
                )

                SecureInputRow(
                    title: "Certificate password",
                    prompt: "Optional certificate password",
                    text: $model.certificatePassword,
                    onChange: model.refreshPreview
                )
            }

            if [.managedIdentityClientID, .managedIdentityObjectID, .managedIdentityResourceID].contains(model.selectedAuthentication) {
                TextInputRow(
                    title: "Managed identity identifier",
                    prompt: "Client ID or resource ID",
                    text: $model.managedIdentityID,
                    onChange: model.refreshPreview
                )
            }

            if model.selectedAuthentication == .managedIdentityObjectID {
                FormRow(title: nil) {
                    Text("Object ID is no longer supported. Select client ID or resource ID and enter the corresponding identifier.")
                        .foregroundStyle(.orange)
                }
            }

            if model.selectedAuthentication.supportsSignIn {
                FormRow(title: nil) {
                    Button("Sign In", action: model.signIn)
                        .disabled(model.isRunning)
                    Text("Authentication instructions appear in the status area while signing in.")
                        .foregroundStyle(.secondary)
                }
            }

            FormRow(title: nil) {
                Text("Credentials are used only for the current process and are redacted from previews and logs. URL credentials and additional flags are not saved.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chooseCertificatePath() {
        let panel = NSOpenPanel()
        panel.title = "Choose Service Principal Certificate"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.certificatePath = url.path
            model.refreshPreview()
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            FormSection("AzCopy") {
                FileInputRow(
                    title: "AzCopy executable",
                    prompt: AzCopyLocator.homebrewAppleSiliconPath,
                    buttonHelp: "Choose AzCopy executable",
                    text: $model.azCopyPath,
                    onChoose: {
                        chooseAzCopyExecutable()
                    },
                    onChange: model.refreshPreview
                )
                FormRow(title: nil) {
                    Text("Default Apple Silicon Homebrew path: \(AzCopyLocator.homebrewAppleSiliconPath)")
                        .foregroundStyle(.secondary)
                }
            }

            AuthenticationSettingsSection()

            FormSection("Advanced") {
                TextInputRow(
                    title: "Additional flags",
                    prompt: "--log-level=INFO --output-type=json",
                    text: $model.extraFlagsText,
                    onChange: model.refreshPreview
                )
                FormRow(title: nil) {
                    Text("Quote values containing spaces. Additional flags are not saved and cannot override options managed by the form.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }

    private func chooseAzCopyExecutable() {
        let panel = NSOpenPanel()
        panel.title = "Choose AzCopy Executable"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.azCopyPath = url.path
            model.refreshPreview()
        }
    }
}

struct LogsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if model.logText.isEmpty {
                    ContentUnavailableView("No Output Yet", systemImage: "terminal", description: Text("Run an operation or sign in to see AzCopy output here. Credentials are redacted."))
                } else {
                    Text(model.logText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .navigationTitle("Logs")
    }
}
